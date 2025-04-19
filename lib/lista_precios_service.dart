import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';

class ListaPreciosService {
  // URL base del servidor
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  //static const String baseUrl = 'http://192.168.1.2:3000'; // Para dispositivo real (cambia la IP)
  // Método principal para generar y mostrar la lista de precios
  static const String baseUrl = 'https://dapautopart.onrender.com'; // URL de producción
  static Future<void> generarListaPrecios(BuildContext context) async {
    try {
      // Mostrar diálogo de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparando productos...')
              ],
            ),
          );
        },
      );

      // Obtener información del asesor logueado
      final prefs = await SharedPreferences.getInstance();
      final asesorId = prefs.getString('asesor_id') ?? '';
      final asesorNombre = prefs.getString('asesor_nombre') ?? '';
      final asesorZona = prefs.getString('asesor_zona') ?? '';
      String asesorCorreo = '';
      
      if (asesorId.isNotEmpty) {
        try {
          final asesorResponse = await http.get(Uri.parse('$baseUrl/asesores/$asesorId'));
          if (asesorResponse.statusCode == 200) {
            final asesorData = json.decode(asesorResponse.body);
            if (asesorData['success'] && asesorData.containsKey('asesor')) {
              final asesor = asesorData['asesor'];
              asesorCorreo = asesor['MAIL'] ?? '';
            }
          }
        } catch (e) {
          print("Error al obtener correo del asesor: $e");
        }
      }

      // Obtener productos del servidor
      final productosResponse = await http.get(Uri.parse('$baseUrl/productos'));
      if (productosResponse.statusCode != 200) {
        Navigator.of(context, rootNavigator: true).pop();
        throw Exception('Error al obtener productos: ${productosResponse.statusCode}');
      }

      final productosData = json.decode(productosResponse.body);
      if (!productosData['success']) {
        Navigator.of(context, rootNavigator: true).pop();
        throw Exception('Error en la respuesta del servidor: ${productosData['message']}');
      }

      final List<dynamic> productosJson = productosData['productos'];
      
      // Filtrar productos que no estén agotados
      final List<Map<String, dynamic>> productosDisponibles = [];
      for (var producto in productosJson) {
        bool agotado = false;
        String estado = producto['ESTADO']?.toString().toUpperCase() ?? '';
        if (estado.contains('AGOTADO')) {
          agotado = true;
        }
        
        if (!agotado) {
          // Simplificar el producto para que ocupe menos memoria
          final productoSimplificado = <String, dynamic>{
            '#': producto['#']?.toString() ?? '',
            'REF': producto['REF']?.toString() ?? '',
            'ORIGEN': producto['ORIGEN']?.toString() ?? '',
            'DESCRIPCION': producto['DESCRIPCION']?.toString() ?? '',
            'VEHICULO': producto['VEHICULO']?.toString() ?? '',
            'MARCA': producto['MARCA']?.toString() ?? '',
            'PRECIO': producto['PRECIO'] ?? producto['VLR ANTES DE IVA'] ?? 0,
            'DSCTO': producto['DSCTO'] ?? 0,
          };
          productosDisponibles.add(productoSimplificado);
        }
      }

      // Actualizar diálogo
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generando PDF (${productosDisponibles.length} productos)...')
              ],
            ),
          );
        },
      );

      // Generar PDF extremadamente compacto
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/lista_precios_completa.pdf';
      
      // Generar el PDF directamente en un archivo para ahorrar memoria
      await _generarPDFDirecto(
        filePath,
        productosDisponibles,
        asesorNombre,
        asesorZona,
        asesorCorreo
      );
      
      // Cerrar diálogo de carga
      Navigator.of(context, rootNavigator: true).pop();
      
      // Mostrar diálogo de éxito
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Lista de Precios'),
            content: Text('La lista completa de precios ha sido generada exitosamente.'),
            actions: [
              TextButton(
                child: Text('Cerrar'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1A4379),
                  foregroundColor: Colors.white,
                ),
                child: Text('Abrir'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _intentarAbrirPDF(context, filePath);
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Cerrar diálogo de carga si hay error
      Navigator.of(context, rootNavigator: true).pop();
      
      // Mostrar error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar lista de precios: $e')),
      );
    }
  }

  // Método para generar PDF directamente a un archivo (ahorra memoria)
  static Future<void> _generarPDFDirecto(
    String filePath,
    List<Map<String, dynamic>> productos,
    String asesorNombre,
    String asesorZona,
    String asesorCorreo
  ) async {
    // Inicializar fecha
    await initializeDateFormatting('es_ES', null);
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy', 'es_ES');
    final fechaActual = formatter.format(now);
    
    // Crear documento PDF minimalista
    final pdf = pw.Document(
      compress: true, // Habilitar compresión para reducir tamaño
      version: PdfVersion.pdf_1_5, // Versión más optimizada
    );
    
    // Configuración ultracompacta
    final fuenteTabla = 4.0; // Fuente extremadamente pequeña
    final fuenteEncabezado = 6.0;
    
    // Usar A4 horizontal con márgenes mínimos
    final pageFormat = PdfPageFormat.a4.landscape.copyWith(
      marginLeft: 5,
      marginTop: 10,
      marginRight: 5,
      marginBottom: 10,
    );
    
    // Función para crear encabezado minimalista
    pw.Widget Function(pw.Context) buildHeader = (pw.Context context) {
      if (context.pageNumber > 1) {
        // Encabezado ultra-minimalista para páginas después de la primera
        return pw.Container(
          height: 12,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('DAP AutoPart\'s - Lista de Precios',
                style: pw.TextStyle(fontSize: 5, color: PdfColors.blue900)),
              pw.Text('Pág. ${context.pageNumber}/${context.pagesCount} • $fechaActual',
                style: pw.TextStyle(fontSize: 5)),
            ],
          ),
        );
      }
      
      // Primera página: encabezado completo pero compacto
      return pw.Container(
        height: 30,
        child: pw.Row(
          children: [
            // Información empresa e introducción
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('DAP AutoPart\'s', 
                    style: pw.TextStyle(
                      fontSize: 10, 
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900
                    )
                  ),
                  pw.Text('LISTA DE PRECIOS',
                    style: pw.TextStyle(
                      fontSize: 8, 
                      fontWeight: pw.FontWeight.bold,
                    )
                  ),
                  pw.Text('PRODUCTOS DISPONIBLES',
                    style: pw.TextStyle(fontSize: 6)
                  ),
                ],
              ),
            ),
            
            // Información fecha y asesor
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Fecha: $fechaActual', 
                    style: pw.TextStyle(fontSize: fuenteEncabezado)),
                  pw.Text('Asesor: $asesorNombre', 
                    style: pw.TextStyle(fontSize: fuenteEncabezado)),
                  pw.Text('$asesorZona | $asesorCorreo', 
                    style: pw.TextStyle(fontSize: fuenteEncabezado-1)),
                ],
              ),
            ),
          ],
        ),
      );
    };
    
    // Minimalista pie de página
    pw.Widget Function(pw.Context) buildFooter = (pw.Context context) {
      return pw.Container(
        height: 10,
        child: pw.Text(
          'DAP AutoPart\'s • Precios sin IVA • Sujetos a cambio',
          style: pw.TextStyle(fontSize: fuenteTabla-1, fontStyle: pw.FontStyle.italic),
          textAlign: pw.TextAlign.center,
        ),
      );
    };

    // Añadir página
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        header: buildHeader,
        footer: buildFooter,
        build: (pw.Context context) {
          return [
            pw.Table(
              border: pw.TableBorder.all(width: 0.1),
              defaultColumnWidth: pw.FlexColumnWidth(1),
              columnWidths: {
                0: pw.FixedColumnWidth(20), // #
                1: pw.FixedColumnWidth(40), // REF
                2: pw.FixedColumnWidth(30), // ORIGEN
                3: pw.FlexColumnWidth(3), // DESCRIPCIÓN
                4: pw.FlexColumnWidth(2), // VEHÍCULO
                5: pw.FlexColumnWidth(1.5), // MARCA
                6: pw.FixedColumnWidth(40), // PRECIO
                7: pw.FixedColumnWidth(25), // DSCTO
              },
              children: [
                // Encabezado de la tabla
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.blue900),
                  children: [
                    _buildHeaderCell('#'),
                    _buildHeaderCell('REF'),
                    _buildHeaderCell('ORIGEN'),
                    _buildHeaderCell('DESCRIPCIÓN'),
                    _buildHeaderCell('VEHÍCULO'),
                    _buildHeaderCell('MARCA'),
                    _buildHeaderCell('PRECIO'),
                    _buildHeaderCell('DSCTO'),
                  ],
                ),
                
                // Filas de productos
                ...productos.map((producto) => pw.TableRow(
                  children: [
                    _buildDataCell(producto['#']?.toString() ?? ''),
                    _buildDataCell(producto['REF']?.toString() ?? ''),
                    _buildDataCell(producto['ORIGEN']?.toString() ?? ''),
                    _buildDataCell(producto['DESCRIPCION']?.toString() ?? ''),
                    _buildDataCell(producto['VEHICULO']?.toString() ?? ''),
                    _buildDataCell(producto['MARCA']?.toString() ?? ''),
                    _buildDataCell(_formatMoneda(producto['PRECIO'])),
                    _buildDataCell('${producto['DSCTO']}%'),
                  ],
                )),
              ],
            ),
          ];
        },
      ),
    );
    
    // Guardar directamente a archivo
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
  }
  
  // Métodos auxiliares simplificados para mayor eficiencia
  static pw.Widget _buildHeaderCell(String text) {
    return pw.Padding(
      padding: pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: PdfColors.white, fontSize: 4, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
  
  static pw.Widget _buildDataCell(String text) {
    return pw.Padding(
      padding: pw.EdgeInsets.all(1),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 4),
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        textAlign: pw.TextAlign.center,
      ),
    );
  }
  
  // Formato moneda simplificado
  static String _formatMoneda(dynamic valor) {
    if (valor == null) return '\$0';
    double monto = 0;
    
    if (valor is num) {
      monto = valor.toDouble();
    } else {
      try {
        final limpio = valor.toString().replaceAll('\$', '').replaceAll(',', '').trim();
        monto = double.tryParse(limpio) ?? 0;
      } catch (_) {}
    }
    
    return '\$${NumberFormat('#,###', 'es_CO').format(monto)}';
  }
  
  // Método para intentar abrir el PDF
  static Future<void> _intentarAbrirPDF(BuildContext context, String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el PDF. Por favor instale un visor de PDF.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir el archivo: $e')),
      );
      
      // Mostrar ubicación del archivo
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('No se pudo abrir el PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('El PDF se encuentra en:'),
                Text(filePath, style: TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
            actions: [
              TextButton(
                child: Text('Entendido'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    }
  }
}