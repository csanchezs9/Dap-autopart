import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'dart:convert';

class CatalogoService {
  // URL base del servidor - Deberás ajustarla según la ubicación de tu servidor
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  // static const String baseUrl = 'http://localhost:3000'; // Para web
    //static const String baseUrl = 'http://192.168.1.2:3000';// Para dispositivo real (cambia la IP)
static const String baseUrl = 'https://dapautopart.onrender.com'; // URL de producción
  // Método principal para mostrar diálogo de confirmación
  static Future<void> abrirCatalogo(BuildContext context) async {
  // Primero verificamos la conectividad con el servidor
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
    
    final response = await http.get(Uri.parse('$baseUrl/ping')).timeout(
      Duration(seconds: 5),
      onTimeout: () => throw Exception('Sin conexión a internet'),
    );
    
    // Cerrar diálogo de carga
    Navigator.of(context, rootNavigator: true).pop();
    
    print("Respuesta de ping: ${response.statusCode} - ${response.body}");
    
    if (response.statusCode != 200) {
      throw Exception('Servidor respondió con error: ${response.statusCode}');
    }
    
    // Verificar si el catálogo existe
    final catalogoInfo = await http.get(Uri.parse('$baseUrl/catalogo-info'));
    print("Respuesta de info catálogo: ${catalogoInfo.statusCode} - ${catalogoInfo.body}");
    
    if (catalogoInfo.statusCode != 200) {
      throw Exception('Error al verificar el catálogo: ${catalogoInfo.statusCode}');
    }
    
    // Decodificamos la respuesta para ver si existe el catálogo
    final catalogoData = catalogoInfo.body.isNotEmpty ? 
        await jsonDecode(catalogoInfo.body) : {'success': false};
    
    if (!catalogoData['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('El catálogo no está disponible. Por favor contacte a soporte.')),
      );
      return;
    }
    
  } catch (e) {
    // Cerrar diálogo de carga si está abierto
    Navigator.of(context, rootNavigator: true).pop();
    
    print("Error al verificar conectividad: $e");
    
    // Mensaje más informativo según el tipo de error
    String errorMsg = 'Error: No se pudo conectar al servidor.';
    
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
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

  // Mostrar diálogo de confirmación
  bool? descargar = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Catálogo de Productos'),
        content: Text('¿Desea descargar el catálogo de productos?'),
        actions: [
          TextButton(
            child: Text('Cancelar'),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF1A4379),
              foregroundColor: Colors.white,
            ),
            child: Text('Descargar'),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      );
    },
  );

  if (descargar == true) {
    await _descargarYAbrirCatalogo(context);
  }
}

  // Método para descargar y abrir el catálogo
  static Future<void> _descargarYAbrirCatalogo(BuildContext context) async {
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
                Text('Descargando catálogo...')
              ],
            ),
          );
        },
      );

      try {
        // Verificar si tenemos el endpoint correcto para el catalogo
        print("Intentando descargar el PDF desde: $baseUrl/catalogo");
        
        // Realizar la solicitud HTTP para descargar el PDF
        final response = await http.get(Uri.parse('$baseUrl/catalogo'));
        print("Respuesta de descarga: ${response.statusCode} (Tamaño: ${response.bodyBytes.length} bytes)");
        
        // Cerrar el diálogo de carga
        Navigator.of(context, rootNavigator: true).pop();
        
        if (response.statusCode == 200) {
          // Guardar en el directorio de cache, que no requiere permisos especiales
          final directory = await getTemporaryDirectory();
          final filePath = '${directory.path}/catalogo_dap.pdf';
          
          print("Guardando archivo en: $filePath");
          
          // Escribir el archivo PDF descargado
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);
          
          print("Archivo guardado correctamente (${response.bodyBytes.length} bytes)");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Catálogo descargado correctamente')),
          );
          
          // Mostrar diálogo con opciones para el usuario
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Catálogo Descargado'),
                content: Text('El catálogo se ha descargado correctamente. ¿Qué desea hacer?'),
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
        } else if (response.statusCode == 404) {
          // Catálogo no encontrado
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('El catálogo no está disponible actualmente')),
          );
        } else {
          // Otro error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al descargar el catálogo (${response.statusCode})')),
          );
        }
      } catch (e) {
        // Cerrar el diálogo de carga en caso de error
        Navigator.of(context, rootNavigator: true).pop();
        
        print("Error en la descarga: $e");
        // Mostrar mensaje de error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar con el servidor: $e')),
        );
      }
    } catch (e) {
      print("Error general: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error inesperado: $e')),
      );
    }
  }
  
  // Método para intentar abrir el PDF con manejo de errores mejorado
  static Future<void> _intentarAbrirPDF(BuildContext context, String filePath) async {
    try {
      print("Intentando abrir el PDF: $filePath");
      final result = await OpenFile.open(filePath);
      
      if (result.type != ResultType.done) {
        print("Error al abrir PDF: ${result.message}");
        // Si falló al abrir, mostrar mensaje de error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el catálogo. Por favor, instale un lector de PDF.')),
        );
        
        // Ofrecemos descargar un lector de PDF
        _mostrarDialogoInstaladorPDF(context);
      }
    } catch (e) {
      print("Excepción al abrir PDF: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir el archivo: $e')),
      );
      
      // Como alternativa, informamos dónde está guardado el archivo
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('No se pudo abrir el PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('El catálogo se ha descargado pero no se puede abrir automáticamente.'),
                SizedBox(height: 12),
                Text('Ubicación del archivo:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(filePath, style: TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
            actions: [
              TextButton(
                child: Text('Entendido'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }
  
  // Método para mostrar diálogo sugiriendo instalar un lector de PDF
  static void _mostrarDialogoInstaladorPDF(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Lector de PDF necesario'),
          content: Text(
            'Para visualizar el catálogo necesita una aplicación que permita '
            'abrir archivos PDF. ¿Desea instalar una desde la tienda de aplicaciones?'
          ),
          actions: [
            TextButton(
              child: Text('No, gracias'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF1A4379),
                foregroundColor: Colors.white,
              ),
              child: Text('Instalar'),
              onPressed: () {
                Navigator.of(context).pop();
                // Aquí podríamos abrir la URL de la Play Store para instalar Adobe Reader u otro visor
                // Pero por ahora solo cerramos el diálogo
              },
            ),
          ],
        );
      },
    );
  }
}
