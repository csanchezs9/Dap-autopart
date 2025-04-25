import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';

class ListaPreciosService {
  // URL base del servidor
  static const String baseUrl = 'https://dap-autoparts.onrender.com'; // URL de producción
  
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
                Text('Verificando conexión...')
              ],
            ),
          );
        },
      );

      // Verificar conectividad
      try {
        final pingResponse = await http.get(
          Uri.parse('$baseUrl/ping'),
        ).timeout(
          Duration(seconds: 5),
          onTimeout: () => throw Exception('Sin conexión a internet'),
        );
        
        if (pingResponse.statusCode != 200) {
          throw Exception('El servidor no está disponible');
        }
      } catch (connectionError) {
        // Cerrar diálogo de carga
        Navigator.of(context, rootNavigator: true).pop();
        
        // Mensaje más informativo según el tipo de error
        String errorMsg = 'Error: No se pudo conectar al servidor.';
        
        if (connectionError.toString().contains('internet') || 
            connectionError.toString().contains('conectar') ||
            connectionError.toString().contains('conexión') ||
            connectionError.toString().contains('timeout') ||
            connectionError.toString().contains('SocketException')) {
          errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
        } else {
          errorMsg = 'Error al conectar con el servidor: $connectionError';
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
        return;
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
      String asesorTelefono = '';
      
      if (asesorId.isNotEmpty) {
        try {
          final asesorResponse = await http.get(Uri.parse('$baseUrl/asesores/$asesorId'));
          if (asesorResponse.statusCode == 200) {
            final asesorData = json.decode(asesorResponse.body);
            if (asesorData['success'] && asesorData.containsKey('asesor')) {
              final asesor = asesorData['asesor'];
              asesorCorreo = asesor['MAIL'] ?? '';
              asesorTelefono = asesor['CEL'] ?? '';
            }
          }
        } catch (e) {
          print("Error al obtener datos del asesor: $e");
        }
      }

      // Obtener productos del servidor
      try {
        final productosResponse = await http.get(Uri.parse('$baseUrl/productos')).timeout(
          Duration(seconds: 15),
          onTimeout: () => throw Exception('Tiempo de espera agotado al obtener productos.'),
        );
        
        if (productosResponse.statusCode != 200) {
          throw Exception('Error al obtener productos: ${productosResponse.statusCode}');
        }

        final productosData = json.decode(productosResponse.body);
        if (!productosData['success']) {
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
        await _generarPDFMultipage(
          filePath,
          productosDisponibles,
          asesorNombre,
          asesorZona,
          asesorCorreo,
          asesorTelefono
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
        
        // Mensaje más informativo según el tipo de error
        String errorMsg = 'Error al generar lista de precios';
        
        if (e.toString().contains('internet') || 
            e.toString().contains('conectar') ||
            e.toString().contains('conexión') ||
            e.toString().contains('timeout') ||
            e.toString().contains('SocketException')) {
          errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
        } else {
          errorMsg = 'Error al generar lista de precios: $e';
        }
        
        // Mostrar un diálogo en lugar de un SnackBar
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Error'),
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
      }
    } catch (e) {
      // Mostrar mensaje de error
      String errorMsg = 'Error inesperado';
      
      if (e.toString().contains('internet') || 
          e.toString().contains('conectar') ||
          e.toString().contains('conexión') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
      } else {
        errorMsg = 'Error inesperado: $e';
      }
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Error'),
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
    }
  }
  
  // Función para limpiar texto y evitar problemas con caracteres Unicode
  static String limpiarTextoParaPDF(String texto) {
    if (texto == null || texto.isEmpty) return '';
    
    // Reemplazar caracteres problemáticos con alternativas seguras
    return texto;   // Reemplazar comillas curvas de cierre con comillas rectas
  }
  
  // Método multipage optimizado y simplificado
  static Future<void> _generarPDFMultipage(
  String filePath,
  List<Map<String, dynamic>> productos,
  String asesorNombre,
  String asesorZona,
  String asesorCorreo,
  String asesorTelefono,
) async {
  try {
    // Inicializar fecha
    await initializeDateFormatting('es_ES', null);
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy', 'es_ES');
    final fechaActual = formatter.format(now);
    
    // Cargar logo de forma segura
    Uint8List? logoBytes;
    try {
      final ByteData data = await rootBundle.load('assets/images/logo.png');
      logoBytes = data.buffer.asUint8List();
      print("Logo cargado correctamente: ${logoBytes.length} bytes");
    } catch (e) {
      print("Error al cargar logo: $e");
    }
    
    // Crear un único documento PDF
    final pdf = pw.Document();
    
    // Registrar la fuente Roboto para soporte de caracteres especiales
    final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final ttf = pw.Font.ttf(fontData.buffer.asByteData());
    
    // Tamaño de página optimizado para maximizar espacio
    final pageFormat = PdfPageFormat.a4.copyWith(
      marginLeft: 10.0,
      marginRight: 10.0,
      marginTop: 60.0,    // Mayor margen superior para el encabezado
      marginBottom: 20.0  // Menor margen inferior
    );
    
    // Calcular cuántos productos pueden caber por página
    // Con estos márgenes y tamaño de fuente, podemos poner más productos por página
    final int productosPerPage = 50;  // Aumentado de 40 a 50
    
    // Crear páginas con encabezado repetido
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        maxPages: 200,  // Suficiente para todos los productos
        header: (pw.Context context) {
          // Encabezado compacto para cada página
          return pw.Container(
            margin: pw.EdgeInsets.only(bottom: 8.0),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Logo e información empresa
                pw.Row(
                  children: [
                    if (logoBytes != null)
                      pw.Container(
                        width: 50,  // Reducido para ahorrar espacio
                        height: 35,
                        child: pw.Image(pw.MemoryImage(logoBytes)),
                      ),
                    pw.SizedBox(width: 5),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'DISTRIBUCIONES AUTOPART\'S S.A.S.',
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,  // Reducido para ahorrar espacio
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'LISTA DE PRECIOS NACIONAL',
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800,
                          ),
                        ),
                        pw.Text(
                          'Fecha: $fechaActual',
                          style: pw.TextStyle(font: ttf, fontSize: 7),
                        ),
                      ],
                    ),
                  ],
                ),
                
                // Información asesor y página
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Pág. ${context.pageNumber}',
                      style: pw.TextStyle(font: ttf, fontSize: 7),
                    ),
                    pw.Text(
                      'Asesor: $asesorNombre${asesorZona.isNotEmpty ? " | $asesorZona" : ""}',
                      style: pw.TextStyle(font: ttf, fontSize: 7),
                    ),
                    if (asesorCorreo.isNotEmpty || asesorTelefono.isNotEmpty)
                      pw.Text(
                        '${asesorCorreo.isNotEmpty ? asesorCorreo : ""}${asesorTelefono.isNotEmpty ? " | Tel: $asesorTelefono" : ""}',
                        style: pw.TextStyle(font: ttf, fontSize: 7),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
        // ¡El footer ha sido eliminado! No hay pie de página
        build: (pw.Context context) {
          // Lista de widgets para el documento
          List<pw.Widget> paginasContent = [];
          
          // Estilo para el encabezado de la tabla
          final headerStyle = pw.TextStyle(
            font: ttf,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 6,  // Reducido para ahorrar espacio
          );
          
          // Estilo para celdas de la tabla
          final cellStyle = pw.TextStyle(
            font: ttf,
            fontSize: 6,  // Reducido para ahorrar espacio
          );
          
          // Crear tabla optimizada con todos los productos
          final tablaBig = pw.Table(
            border: pw.TableBorder.all(width: 0.3),  // Borde más delgado
            columnWidths: {
              0: pw.FixedColumnWidth(25),    // # (Número secuencial)
              1: pw.FixedColumnWidth(42),    // Ref
              2: pw.FixedColumnWidth(35),    // Origen
              3: pw.FlexColumnWidth(3.5),    // Descripción
              4: pw.FlexColumnWidth(2.2),    // Vehículo
              5: pw.FlexColumnWidth(1.5),    // Marca
              6: pw.FixedColumnWidth(45),    // Precio
              7: pw.FixedColumnWidth(28),    // DSCTO
            },
            children: [
              // Encabezado
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.blue900),
                repeat: true,  // Se repite en cada página automáticamente
                children: [
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('#', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Ref', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Origen', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Descripcion', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Vehiculo', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Marca', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Precio', style: headerStyle, textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('Dscto', style: headerStyle, textAlign: pw.TextAlign.center)),
                ],
              ),
              
              // Filas de productos
              for (var producto in productos)
                pw.TableRow(
                  children: [
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['#']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['REF']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['ORIGEN']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['DESCRIPCION']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['VEHICULO']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(producto['MARCA']?.toString() ?? '', style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text(_formatoMoneda(producto['PRECIO']), style: cellStyle)),
                    pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('${producto['DSCTO'] ?? 0}%', style: cellStyle)),
                  ],
                ),
            ],
          );
          
          // Añadir la tabla como único widget
          paginasContent.add(tablaBig);
          
          return paginasContent;
        },
      ),
    );
    
    // Guardar el documento a archivo
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    
    print("✅ PDF generado correctamente con ${productos.length} productos");
    
  } catch (e) {
    print("❌ Error detallado en generación de PDF: $e");
    print("Stack trace: ${StackTrace.current}");
    throw e;
  }
}

static String simplificarTexto(String texto) {
  if (texto == null || texto.isEmpty) return '';
  
  // Ya no reemplazamos caracteres especiales, solo eliminamos caracteres potencialmente problemáticos
  // que no se muestran bien en el PDF
  
  // Filtrar solo caracteres realmente problemáticos
  String resultado = texto.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  
  return resultado;
}
  
  // Método optimizado para formatear precios
  static String _formatoMoneda(dynamic valor) {
    if (valor == null) return '\$0';
    
    double monto = 0;
    if (valor is num) {
      monto = valor.toDouble();
    } else {
      try {
        String valorStr = valor.toString()
            .replaceAll('\$', '')
            .replaceAll(',', '')
            .trim();
        monto = double.parse(valorStr);
      } catch (_) {}
    }
    
    // Formato simple para evitar problemas
    try {
      return '\$${NumberFormat('#,###', 'es_CO').format(monto)}';
    } catch (_) {
      return '\$${monto.toInt()}';
    }
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