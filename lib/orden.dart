import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'cliente_service_local.dart';
import 'asesor_service_local.dart';
import 'productos_orden.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class OrdenDePedido extends StatefulWidget {
  const OrdenDePedido({super.key});

  @override
  State<OrdenDePedido> createState() => _OrdenDePedidoState();
}

class _OrdenDePedidoState extends State<OrdenDePedido> {
  final TextEditingController nitController = TextEditingController();
  final TextEditingController idAsesorController = TextEditingController();
  

  int numeroOrdenActual = 1;
  Map<String, String> clienteData = {};
  Map<String, String> asesorData = {};
  
  bool isLoading = false;
  String errorMessage = '';
  final TextEditingController ordenNumeroController = TextEditingController();

  // URL base del servidor - usar la misma que en los servicios
  //static const String baseUrl = 'http://192.168.1.2:3000'; // Para dispositivo real
  static const String baseUrl = 'https://dapautopart.onrender.com'; 

  @override
  void initState() {
    super.initState();
    // Inicializar la localización antes de usarla
    initializeDateFormatting('es_ES', null);
    // Obtener número de orden del servidor
    _obtenerSiguienteNumeroOrden();
  }

  String obtenerFechaActual() {
    final now = DateTime.now();
    final formatter = DateFormat('dd – MMMM – yyyy', 'es_ES');
    String fecha = formatter.format(now).toUpperCase();
    return fecha;
  }

  // Nuevo método para obtener número del servidor
  Future<void> _obtenerSiguienteNumeroOrden() async {
  setState(() {
    isLoading = true;
    errorMessage = '';
  });

  try {
    // Intentar obtener el número únicamente del servidor
    final response = await http.get(
      Uri.parse('$baseUrl/siguiente-orden'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(
      Duration(seconds: 10),
      onTimeout: () => throw Exception('Tiempo de espera agotado al conectar con el servidor'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      
      if (data['success']) {
        // Actualizar el estado con el nuevo número
        setState(() {
          // Guardar el valor numérico para referencia
          numeroOrdenActual = data['valor'];
          // Usar el formato proporcionado por el servidor
          ordenNumeroController.text = data['numeroOrden'];
        });
        
        print("Número de orden obtenido del servidor: ${ordenNumeroController.text}");
      } else {
        // Error en la respuesta del servidor
        throw Exception(data['message'] ?? 'Error al obtener número de orden');
      }
    } else {
      // Error HTTP
      throw Exception('Error en la solicitud: ${response.statusCode}');
    }
  } catch (e) {
    print("Error al obtener número de orden: $e");
    
    // Mostrar mensaje de error específico para la conexión
    String errorMsg = 'Error al obtener número de orden';
    
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
    } else {
      errorMsg = 'Error al obtener número de orden: $e';
    }
    
    // Mostrar diálogo de error
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error de conexión'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMsg),
              SizedBox(height: 10),
              Text('No se puede continuar sin conexión al servidor.', 
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Aceptar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _obtenerSiguienteNumeroOrden(); // Intentar nuevamente
              },
              child: Text('Reintentar'),
            ),
          ],
        );
      },
    );
    
    setState(() {
      // Dejar el campo vacío o con un texto que indique error
      ordenNumeroController.text = 'Error de conexión';
      errorMessage = errorMsg;
    });
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}

  // Método para buscar cliente por NIT usando el servicio
  void buscarClientePorNIT(String nit) async {
  if (nit.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Por favor ingrese un NIT')),
    );
    return;
  }
  
  setState(() {
    isLoading = true;
    clienteData = {};
  });
  
  try {
    // Verificar conectividad con un ping rápido
    try {
      final pingResponse = await http.get(
        Uri.parse('${ClienteServiceLocal.baseUrl}/ping'),
      ).timeout(
        Duration(seconds: 5),
        onTimeout: () => throw Exception('Sin conexión a internet'),
      );
      
      if (pingResponse.statusCode != 200) {
        throw Exception('El servidor no está disponible');
      }
    } catch (connectionError) {
      throw Exception('No se puede conectar al servidor. Verifique su conexión a internet.');
    }
    
    final clienteEncontrado = await ClienteServiceLocal.buscarClientePorNIT(nit);
    
    if (clienteEncontrado != null) {
      // Convertir el Map<String, dynamic> a Map<String, String>
      Map<String, String> newData = {};
      clienteEncontrado.forEach((key, value) {
        newData[key] = value.toString();
      });
      
      setState(() {
        clienteData = newData;
        
        // Si encontramos el cliente, también podemos buscar su asesor automáticamente
        String idAsesor = '';
        if (clienteData.containsKey('ID ASESOR')) {
          idAsesor = clienteData['ID ASESOR']!;
        } else if (clienteData.containsKey('ASESOR ID')) {
          idAsesor = clienteData['ASESOR ID']!;
        }
        
        if (idAsesor.isNotEmpty) {
          idAsesorController.text = idAsesor;
          buscarAsesorPorID(idAsesor);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró cliente con NIT: $nit')),
      );
    }
  } catch (e) {
    // Mensaje más informativo
    String errorMsg = 'Error al buscar cliente';
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
    } else {
      errorMsg = 'Error al buscar cliente: $e';
    }
    
    // Mostrar un diálogo en lugar de un SnackBar
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error de conexión'),
          content: Text(errorMsg),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
    
    setState(() {
      errorMessage = errorMsg;
    });
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}


  // Método para buscar asesor por ID usando el servicio
  void buscarAsesorPorID(String id) async {
  if (id.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Por favor ingrese un ID de asesor')),
    );
    return;
  }
  
  setState(() {
    isLoading = true;
    asesorData = {};
  });
  
  try {
    // Verificar conectividad con un ping rápido
    try {
      final pingResponse = await http.get(
        Uri.parse('${AsesorServiceLocal.baseUrl}/ping'),
      ).timeout(
        Duration(seconds: 5),
        onTimeout: () => throw Exception('Sin conexión a internet'),
      );
      
      if (pingResponse.statusCode != 200) {
        throw Exception('El servidor no está disponible');
      }
    } catch (connectionError) {
      throw Exception('No se puede conectar al servidor. Verifique su conexión a internet.');
    }
    
    final asesorEncontrado = await AsesorServiceLocal.buscarAsesorPorID(id);
    
    if (asesorEncontrado != null) {
      // Convertir el Map<String, dynamic> a Map<String, String>
      Map<String, String> newData = {};
      asesorEncontrado.forEach((key, value) {
        newData[key] = value.toString();
      });
      
      setState(() {
        asesorData = newData;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró asesor con ID: $id')),
      );
    }
  } catch (e) {
    // Mensaje más informativo
    String errorMsg = 'Error al buscar asesor';
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
    } else {
      errorMsg = 'Error al buscar asesor: $e';
    }
    
    // Mostrar un diálogo en lugar de un SnackBar
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error de conexión'),
          content: Text(errorMsg),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Aceptar'),
            ),
          ],
        );
      },
    );
    
    setState(() {
      errorMessage = errorMsg;
    });
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}

  // Método para crear las filas de la tabla
  TableRow _buildTableRow(String label, String value, {bool isHeader = false, Color? color}) {
    return TableRow(
      decoration: BoxDecoration(
        color: color ?? (isHeader ? Color(0xFF1A4379) : Color(0xFFCFD5E1)),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.white : Colors.black,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.white : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  bool _puedeAvanzar() {
  // Verificamos si tenemos datos mínimos del cliente y asesor
  return clienteData.isNotEmpty && 
         clienteData.containsKey('NIT CLIENTE') && 
         !clienteData['NIT CLIENTE']!.isEmpty &&
         asesorData.isNotEmpty && 
         asesorData.containsKey('ID') && 
         !asesorData['ID']!.isEmpty;
}

// Método para mostrar alerta si faltan datos
void _mostrarAlertaDatosIncompletos() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Datos incompletos'),
        content: Text(
          'Para continuar, debe ingresar al menos:\n\n'
          '• Información del cliente (NIT)\n'
          '• Información del asesor (ID)\n\n'
          'Por favor, complete estos datos antes de proceder.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Entendido'),
          ),
        ],
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Orden de Pedido', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1A4379),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading 
        ? Center(child: CircularProgressIndicator())
        : errorMessage.isNotEmpty 
          ? Center(child: Text('Error: $errorMessage', style: TextStyle(color: Colors.red)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo y Encabezado
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sección DAP AutoPart's
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
  'assets/images/logo.png',
  width: 150,
  fit: BoxFit.contain,
),
                          SizedBox(height: 10),
                          Text('Distribuciones Autoparts S.A.S', 
                              style: TextStyle(fontSize: 14)),
                          Row(
                            children: [
                              Text('Nit: ', style: TextStyle(fontSize: 14)),
                              Text('901.110.424-1', 
                                  style: TextStyle(fontSize: 14, decoration: TextDecoration.underline)),
                            ],
                          ),
                        ],
                      ),
                      Spacer(),
                      // Sección de Fecha y Número de Orden
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Botón de Productos a Solicitar (reemplazando el recuadro)
                          GestureDetector(
                            onTap: () {
                              if (_puedeAvanzar()) {
                                // Si tenemos datos suficientes, navegamos a la pantalla de productos
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProductosOrden(
                                      clienteData: clienteData,
                                      asesorData: asesorData,
                                      ordenNumero: ordenNumeroController.text,
                                    ),
                                  ),
                                );
                              } else {
                                // Si faltan datos, mostramos la alerta
                                _mostrarAlertaDatosIncompletos();
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white,
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48),
                                  Text('PRODUCTOS A SOLICITAR', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          Text('FECHA: ${obtenerFechaActual()}', 
                               style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          SizedBox(
                            width: 200,
                            child: TextField(
                              controller: ordenNumeroController,
                              readOnly: true, // Hacerlo de solo lectura
                              decoration: InputDecoration(
                                labelText: 'Orden de Pedido #',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                                filled: true,
                                fillColor: Colors.grey[200], // Color de fondo para indicar que es de solo lectura
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 30),
                  
                  // Sección de búsqueda de cliente
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nitController,
                          decoration: InputDecoration(
                            labelText: 'NIT Cliente',
                            border: OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.search),
                              onPressed: () => buscarClientePorNIT(nitController.text),
                            ),
                            hintText: 'Ejemplo: 811004112-7',
                          ),
                          onSubmitted: buscarClientePorNIT,
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Sección de búsqueda de asesor
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: idAsesorController,
                          decoration: InputDecoration(
                            labelText: 'ID Asesor',
                            border: OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.search),
                              onPressed: () => buscarAsesorPorID(idAsesorController.text),
                            ),
                            hintText: 'Ejemplo: 1035428660',
                          ),
                          onSubmitted: buscarAsesorPorID,
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Tabla de información del cliente
                  Table(
                    border: TableBorder.all(color: Colors.white),
                    columnWidths: {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(3),
                    },
                    children: [
                      _buildTableRow('NIT CLIENTE', clienteData['NIT CLIENTE'] ?? '', isHeader: true),
                      _buildTableRow('NOMBRE', clienteData['NOMBRE'] ?? ''),
                      _buildTableRow('ESTABLECIMIENTO', clienteData['ESTABLECIMIENTO'] ?? ''),
                      _buildTableRow('DIRECCIÓN', clienteData['DIRECCION'] ?? ''),
                      _buildTableRow('TELEFONO', clienteData['TELEFONO'] ?? ''),
                      _buildTableRow('DESCUENTO', clienteData['DESCTO'] ?? ''),
                      _buildTableRow('CIUDAD', clienteData['CLI_CIUDAD'] ?? ''),
                      _buildTableRow('CORREO', clienteData['CLI_EMAIL'] ?? ''),
                      _buildTableRow('ID ASESOR', clienteData['ID ASESOR'] ?? asesorData['ID'] ?? '', isHeader: true),
                      _buildTableRow('NOMBRE', asesorData['NOMBRE'] ?? ''),
                      _buildTableRow('ZONA', asesorData['ZONA'] ?? ''),
                      _buildTableRow('TELEFONO', asesorData['CEL'] ?? ''),
                      _buildTableRow('CORREO', asesorData['MAIL'] ?? ''),
                    ],
                  ),
                  
                  // Nota: Se ha eliminado el botón INICIO que estaba aquí anteriormente
                ],
              ),
            ),
    );
  }
}