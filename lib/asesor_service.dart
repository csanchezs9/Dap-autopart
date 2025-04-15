import 'package:http/http.dart' as http;
import 'dart:convert';

class AsesorService {
  static const String apiKey = 'AIzaSyBu51IfYHAXIodwktv8FU0E_TgSSlTNpPI';
  static const String sheetId = '1QrFE-NthFzKxK8tN9ZqjaZnwiLlFWUYkAvbtZTSdHz0';
  static const String sheetName = 'asesores'; // Nombre de la hoja para asesores

  // Método para obtener todos los asesores desde la hoja de Google Sheets
  static Future<List<Map<String, dynamic>>> obtenerAsesores() async {
    final url = 'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$sheetName?key=$apiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      print("Respuesta de la API (asesores): ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!data.containsKey('values')) {
          print("No se encontró la clave 'values' en la respuesta");
          return [];
        }

        final values = data['values'] as List;
        if (values.isEmpty) {
          print("La hoja está vacía");
          return [];
        }

        // Identificar la fila de encabezados buscando la columna "NOMBRE" o "ID"
        int headerRowIndex = -1;
        for (int i = 0; i < values.length; i++) {
          if (values[i].any((cell) => 
            cell.toString().toUpperCase().contains('NOMBRE') || 
            cell.toString().toUpperCase() == 'ID')) {
            headerRowIndex = i;
            print("Encabezados encontrados en la fila $i: ${values[i]}");
            break;
          }
        }

        if (headerRowIndex == -1) {
          print("No se encontraron encabezados en la hoja");
          return [];
        }

        final headers = List<String>.from(values[headerRowIndex].map((e) => e.toString().trim()));
        print("Encabezados procesados: $headers");

        // Buscar el índice de la columna ID
        int idIndex = headers.indexWhere((h) => h.toUpperCase() == 'ID');
        if (idIndex == -1) {
          print("No se encontró columna para ID");
          idIndex = 1; // Usamos el índice 1 por defecto como en el CSV original
        }
        
        print("Índice de la columna ID: $idIndex");

        final asesores = <Map<String, dynamic>>[];

        for (int i = headerRowIndex + 1; i < values.length; i++) {
          if (values[i].length <= idIndex) continue;

          final row = values[i];
          final asesor = <String, dynamic>{};

          for (int j = 0; j < headers.length && j < row.length; j++) {
            asesor[headers[j]] = row[j];
          }

          if (row.length > idIndex) {  
            asesores.add(asesor);
          }
        }

        print("Total de asesores cargados: ${asesores.length}");
        return asesores;
      } else {
        print('Error al obtener asesores: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Excepción al obtener asesores: $e');
      return [];
    }
  }

  // Método para buscar un asesor por su ID
  static Future<Map<String, dynamic>?> buscarAsesorPorID(String id) async {
    print("Buscando asesor con ID: $id");
    try {
      final asesores = await obtenerAsesores();
      if (asesores.isEmpty) {
        print("No se cargaron asesores de la hoja");
        return null;
      }
      
      // Mostrar los primeros asesores para depuración
      print("Muestra de asesores disponibles:");
      for (int i = 0; i < min(5, asesores.length); i++) {
        print("Asesor $i: ${asesores[i]}");
      }
      
      // Buscar por ID
      for (var asesor in asesores) {
        String rowId = '';
        
        // Probar diferentes claves que podrían contener el ID del asesor
        if (asesor.containsKey('ID')) {
          rowId = asesor['ID'].toString().trim();
        } else if (asesor.containsKey('id')) {
          rowId = asesor['id'].toString().trim();
        } else if (asesor.containsKey('Id')) {
          rowId = asesor['Id'].toString().trim();
        }
        
        if (rowId == id.trim()) {
          print("¡Asesor encontrado!: $asesor");
          return asesor;
        }
      }
      
      print("No se encontró ningún asesor con ID: $id");
      return null;
    } catch (e) {
      print("Error en buscarAsesorPorID: $e");
      return null;
    }
  }
  
  // Método para buscar un asesor por su correo
  static Future<Map<String, dynamic>?> buscarAsesorPorCorreo(String correo) async {
    print("Buscando asesor con correo: $correo");
    try {
      final asesores = await obtenerAsesores();
      if (asesores.isEmpty) {
        print("No se cargaron asesores de la hoja");
        return null;
      }
      
      // Normalizar el correo para la búsqueda (minúsculas y sin espacios)
      final correoNormalizado = correo.trim().toLowerCase();
      
      // Buscar por correo MAIL
      for (var asesor in asesores) {
        String rowCorreo = '';
        
        // Probar diferentes claves que podrían contener el correo del asesor
        if (asesor.containsKey('MAIL')) {
          rowCorreo = asesor['MAIL'].toString().trim().toLowerCase();
        } else if (asesor.containsKey('EMAIL')) {
          rowCorreo = asesor['EMAIL'].toString().trim().toLowerCase();
        } else if (asesor.containsKey('CORREO')) {
          rowCorreo = asesor['CORREO'].toString().trim().toLowerCase();
        } else if (asesor.containsKey('mail')) {
          rowCorreo = asesor['mail'].toString().trim().toLowerCase();
        } else if (asesor.containsKey('email')) {
          rowCorreo = asesor['email'].toString().trim().toLowerCase();
        }
        
        if (rowCorreo == correoNormalizado) {
          print("¡Asesor encontrado por correo!: $asesor");
          return asesor;
        }
      }
      
      print("No se encontró ningún asesor con correo: $correo");
      return null;
    } catch (e) {
      print("Error en buscarAsesorPorCorreo: $e");
      return null;
    }
  }
}

// Función utilitaria min para compatibilidad
int min(int a, int b) {
  return a < b ? a : b;
}