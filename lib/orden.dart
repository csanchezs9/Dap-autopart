import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'cliente_service_local.dart';
import 'asesor_service_local.dart'; // Cambio aquí - importar el nuevo servicio
import 'productos_orden.dart';
import 'package:shared_preferences/shared_preferences.dart';


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

  @override
  void initState() {
    super.initState();
    // Inicializar la localización antes de usarla
    initializeDateFormatting('es_ES', null);
    // Cargar último número de orden
    _cargarNumeroOrden();
}

  String obtenerFechaActual() {
    final now = DateTime.now();
    final formatter = DateFormat('dd – MMMM – yyyy', 'es_ES');
    String fecha = formatter.format(now).toUpperCase();
    return fecha;
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