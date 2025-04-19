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
      // Intentar obtener el número del servidor
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
          
          // También guardar en SharedPreferences como respaldo
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('ultimoNumeroOrden', numeroOrdenActual);
          
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
      
      // Plan B: Usar SharedPreferences local como respaldo
      try {
        final prefs = await SharedPreferences.getInstance();
        numeroOrdenActual = prefs.getInt('ultimoNumeroOrden') ?? 1;
        // Incrementar para la próxima orden
        numeroOrdenActual++;
        // Guardar el valor actualizado
        await prefs.setInt('ultimoNumeroOrden', numeroOrdenActual);
        
        // Formatear el número para mostrar
        ordenNumeroController.text = 'OP-${numeroOrdenActual.toString().padLeft(5, '0')}';
        
        // Mostrar advertencia
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo conectar al servidor. Usando número de orden local.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      } catch (localError) {
        // Si falla el plan B, usar un valor predeterminado
        setState(() {
          numeroOrdenActual = DateTime.now().millisecondsSinceEpoch % 10000; // Usar timestamp como respaldo final
          ordenNumeroController.text = 'OP-${numeroOrdenActual.toString().padLeft(5, '0')}';
          errorMessage = 'Error al generar número de orden: $e';
        });
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _cargarNumeroOrden() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    numeroOrdenActual = prefs.getInt('ultimoNumeroOrden') ?? 1;
    ordenNumeroController.text = 'OP-${numeroOrdenActual.toString().padLeft(5, '0')}';
  });
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
      setState(() {
        errorMessage = 'Error al buscar cliente: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar cliente: $e')),
      );
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
    setState(() {
      errorMessage = 'Error al buscar asesor: $e';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al buscar asesor: $e')),
    );
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
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
                              children: [
                                TextSpan(
                                  text: 'DAP\n',
                                  style: TextStyle(color: Color(0xFF1A4379)),
                                ),
                                TextSpan(
                                  text: 'AutoPart´s',
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ],
                            ),
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