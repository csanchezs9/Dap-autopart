import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Añadido para inicializar locales
import 'productos_orden.dart';

class OrdenDePedido extends StatefulWidget {
  const OrdenDePedido({super.key});

  @override
  State<OrdenDePedido> createState() => _OrdenDePedidoState();
}

class _OrdenDePedidoState extends State<OrdenDePedido> {
  final TextEditingController nitController = TextEditingController();
  final TextEditingController idAsesorController = TextEditingController();

  Map<String, String> clienteData = {};
  Map<String, String> asesorData = {};

  List<List<dynamic>> clientesCsv = [];
  List<List<dynamic>> asesoresCsv = [];
  
  bool isLoading = true;
  String errorMessage = '';
  String ordenNumero = 'OP-00001';

  @override
  void initState() {
    super.initState();
    // Inicializar la localización antes de usarla
    initializeDateFormatting('es_ES', null).then((_) {
      cargarCSVs();
    });
  }

  String obtenerFechaActual() {
    final now = DateTime.now();
    final formatter = DateFormat('dd – MMMM – yyyy', 'es_ES');
    String fecha = formatter.format(now).toUpperCase();
    return fecha;
  }

  Future<void> cargarCSVs() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });
      
      // Cargar archivo de clientes con Latin-1 encoding
      final clientesBytes = await rootBundle.load('assets/clientes.csv');
      final clientesString = latin1.decode(clientesBytes.buffer.asUint8List());
      final clientesData = const CsvToListConverter().convert(clientesString);
      
      // Cargar archivo de asesores con Latin-1 encoding
      final asesoresBytes = await rootBundle.load('assets/asesores.csv');
      final asesoresString = latin1.decode(asesoresBytes.buffer.asUint8List());
      final asesoresData = const CsvToListConverter().convert(asesoresString);
      
      setState(() {
        clientesCsv = clientesData;
        asesoresCsv = asesoresData;
        isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error al cargar los CSV: $e';
      });
      print("Error al cargar los CSV: $e");
    }
  }

  void buscarClientePorNIT(String nit) {
    if (clientesCsv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Datos de clientes no disponibles')),
      );
      return;
    }
    
    final headers = clientesCsv[0];
    final rows = clientesCsv.skip(1).toList();

    // Resetear datos del cliente
    setState(() {
      clienteData = {};
    });

    // Buscar el NIT exacto ignorando espacios
    for (var row in rows) {
      if (row.isNotEmpty) {
        String rowNit = row[0].toString().trim();
        
        if (rowNit == nit.trim()) {
          try {
            Map<String, String> newData = {};
            for (int i = 0; i < headers.length && i < row.length; i++) {
              newData[headers[i].toString()] = row[i].toString();
            }
            
            setState(() {
              clienteData = newData;
              
              // Si encontramos el cliente, también podemos buscar su asesor automáticamente
              if (clienteData.containsKey('ID ASESOR') && clienteData['ID ASESOR'] != null) {
                String idAsesor = clienteData['ID ASESOR']!;
                idAsesorController.text = idAsesor;
                buscarAsesorPorID(idAsesor);
              }
            });
            return;
          } catch (e) {
            print("Error al procesar datos del cliente: $e");
          }
        }
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se encontró cliente con NIT: $nit')),
    );
  }

  void buscarAsesorPorID(String id) {
    if (asesoresCsv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Datos de asesores no disponibles')),
      );
      return;
    }
    
    final headers = asesoresCsv[0];
    final rows = asesoresCsv.skip(1).toList();

    // Resetear datos del asesor
    setState(() {
      asesorData = {};
    });

    // El ID del asesor está en la columna 1 (índice 1) según tu CSV
    for (var row in rows) {
      if (row.isNotEmpty) {
        String rowId = row[1].toString().trim();
        
        if (rowId == id.trim()) {
          try {
            Map<String, String> newData = {};
            for (int i = 0; i < headers.length && i < row.length; i++) {
              newData[headers[i].toString()] = row[i].toString();
            }
            
            setState(() {
              asesorData = newData;
            });
            return;
          } catch (e) {
            print("Error al procesar datos del asesor: $e");
          }
        }
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se encontró asesor con ID: $id')),
    );
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
        title: Text('Orden de Pedido'),
        backgroundColor: Color(0xFF1A4379),
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
                          // Imagen de productos
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 48),
                                Text('PRODUCTOS A SOLICITAR', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Text('FECHA: ${obtenerFechaActual()}', 
                               style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text('ORDEN DE PEDIDO #: $ordenNumero', 
                               style: TextStyle(fontWeight: FontWeight.bold)),
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
                  
                  SizedBox(height: 30),
                  
                  // Botón de Inicio centrado
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductosOrden(
                              clienteData: clienteData,
                              asesorData: asesorData,
                              ordenNumero: ordenNumero,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        side: BorderSide(color: Colors.grey),
                        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                      child: Text('INICIO'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
