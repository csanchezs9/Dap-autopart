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
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  //static const String baseUrl = 'http://192.168.1.2:3000'; // Para dispositivo real (cambia la IP)
  // Método principal para generar y mostrar la lista de precios
  //https://dap-autoparts.onrender.com
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
      await _generarPDFDirecto(
        filePath,
        productosDisponibles,
        asesorNombre,
        asesorZona,
        asesorCorreo,
        asesorTelefono // Añadir parámetro de teléfono
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

Future<pw.MemoryImage> getLogo() async {
  final ByteData data = await rootBundle.load('assets/images/logo.png');
  final Uint8List bytes = data.buffer.asUint8List();
  final pw.MemoryImage image = pw.MemoryImage(bytes);
  return image;
}

  // Método para generar PDF directamente a un archivo (ahorra memoria)
  static Future<void> _generarPDFDirecto(
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
    
    // Cargar logo con manejo de errores
    ByteData? logoData;
    Uint8List? logoBytes;
    pw.MemoryImage? logoImage;
    
    try {
      logoData = await rootBundle.load('assets/images/logo.png');
      if (logoData != null) {
        logoBytes = logoData.buffer.asUint8List();
        logoImage = pw.MemoryImage(logoBytes);
      }
    } catch (e) {
      print("Error al cargar logo: $e");
      // Continuar sin logo
    }
    
    // Crear documento PDF con mejor formato
    final pdf = pw.Document(
      compress: true,
      version: PdfVersion.pdf_1_5,
    );
    
    // Aumentar tamaño de fuente para mejor legibilidad
    final fuenteTabla = 8.0;
    final fuenteEncabezado = 9.0;
    
    // Usar A4 vertical para mejor uso del espacio
    final pageFormat = PdfPageFormat.a4.copyWith(
      marginLeft: 20,
      marginTop: 20,
      marginRight: 20,
      marginBottom: 20,
    );
    
    // Función para crear encabezado mejorado
    pw.Widget Function(pw.Context) buildHeader = (pw.Context context) {
      if (context.pageNumber > 1) {
        // Encabezado simplificado para páginas después de la primera
        return pw.Container(
          height: 40,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  if (logoImage != null) 
                    pw.Image(logoImage, width: 30, height: 30),
                  pw.SizedBox(width: 5),
                  pw.Text('LISTA DE PRECIOS',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.blue900, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Text('Pág. ${context.pageNumber}/${context.pagesCount} • $fechaActual',
                style: pw.TextStyle(fontSize: 10)),
            ],
          ),
        );
      }
      
      // Primera página: encabezado mejorado y centrado
      return pw.Container(
        height: 120,
        child: pw.Column(
          children: [
            // Logo centralizado
            if (logoImage != null)
              pw.Center(
                child: pw.Image(logoImage, width: 100, height: 70),
              ),
            
            // Información de la empresa
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text('DISTRIBUCIONES AUTOPART\'S S.A.S.', 
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('CR 50A # 46 - 45 Piso 3 • Itagüí, Antioquia • Tel: (57) 3249950610',
                    style: pw.TextStyle(fontSize: 10)),
                  pw.Text('IMPORTADOR MAYORISTA DE AUTOPARTES',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            
            pw.SizedBox(height: 10),
            
            // Título y fecha
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('LISTA DE PRECIOS NACIONAL',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Fecha: $fechaActual', 
                  style: pw.TextStyle(fontSize: 10)),
              ],
            ),
            
            // Información del asesor en la parte inferior
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Asesor: ${asesorNombre ?? ""}${asesorZona.isNotEmpty ? " | $asesorZona" : ""}${asesorCorreo.isNotEmpty ? " | $asesorCorreo" : ""}${asesorTelefono.isNotEmpty ? " | Tel: $asesorTelefono" : ""}',
                style: pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      );
    };
    
    // Mejorar el pie de página
    pw.Widget Function(pw.Context) buildFooter = (pw.Context context) {
      return pw.Container(
        height: 30,
        child: pw.Column(
          children: [
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Image(logoImage, width: 15, height: 15),
                pw.SizedBox(width: 5),
                pw.Text(
                  'Precios sin IVA • Sujetos a cambio sin previo aviso',
                  style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
                ),
              ],
            ),
          ],
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
              border: pw.TableBorder.all(width: 0.5),
              defaultColumnWidth: pw.FlexColumnWidth(1),
              columnWidths: {
                0: pw.FixedColumnWidth(35), // Ref
                1: pw.FixedColumnWidth(45), // Origen
                2: pw.FlexColumnWidth(3), // Descripción
                3: pw.FlexColumnWidth(2), // Vehículo
                4: pw.FlexColumnWidth(1.5), // Marca
                5: pw.FixedColumnWidth(60), // Precio
                6: pw.FixedColumnWidth(35), // DSCTO
              },
              children: [
                // Encabezado de la tabla
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.blue900),
                  children: [
                    _buildHeaderCell('Ref'),
                    _buildHeaderCell('Origen'),
                    _buildHeaderCell('Descripción'),
                    _buildHeaderCell('Vehículo'),
                    _buildHeaderCell('Marca'),
                    _buildHeaderCell('Precio'),
                    _buildHeaderCell('Dscto'),
                  ],
                ),
                
                // Filas de productos
                ...productos.map((producto) => pw.TableRow(
                  children: [
                    _buildDataCell(producto['REF']?.toString() ?? ''),
                    _buildDataCell(producto['ORIGEN']?.toString() ?? ''),
                    _buildDataCell(producto['DESCRIPCION']?.toString() ?? ''),
                    _buildDataCell(producto['VEHICULO']?.toString() ?? ''),
                    _buildDataCell(producto['MARCA']?.toString() ?? ''),
                    _buildDataCell(_formatMoneda(producto['PRECIO'])),
                    _buildDataCell('${producto['DSCTO'] ?? 0}%'),
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
  } catch (e) {
    print("Error detallado en generación de PDF: $e");
    throw e; // Re-lanzar para que se maneje en el nivel superior
  }
}
  // Métodos auxiliares simplificados para mayor eficiencia
 static pw.Widget _buildHeaderCell(String text) {
  return pw.Padding(
    padding: pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white, 
        fontSize: 9, 
        fontWeight: pw.FontWeight.bold
      ),
      textAlign: pw.TextAlign.center,
    ),
  );
}
  
  static pw.Widget _buildDataCell(String text) {
  return pw.Padding(
    padding: pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8),
      maxLines: 2,
      overflow: pw.TextOverflow.clip,
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