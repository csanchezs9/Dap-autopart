import 'package:http/http.dart' as http;
import 'dart:convert';

class ProductoService {
  static const String apiKey = 'AIzaSyBu51IfYHAXIodwktv8FU0E_TgSSlTNpPI';
  static const String sheetId = '1QrFE-NthFzKxK8tN9ZqjaZnwiLlFWUYkAvbtZTSdHz0';
  static const String sheetName = 'productos';

  static Future<List<Map<String, dynamic>>> obtenerProductos() async {
    final url = 'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$sheetName?key=$apiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      print("Respuesta de la API: ${response.statusCode}");

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

        int headerRowIndex = -1;
        for (int i = 0; i < values.length; i++) {
          if (values[i].any((cell) => 
            cell.toString().toUpperCase().contains('CODIGO') || 
            cell.toString() == '#')) {
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

        int codigoIndex = headers.indexWhere((h) => 
          h.toUpperCase().contains('CODIGO') || h == '#');
        if (codigoIndex == -1) {
          print("No se encontró columna para CÓDIGO");
          codigoIndex = 1;
        }
        
        print("Índice de la columna CODIGO: $codigoIndex");

        final productos = <Map<String, dynamic>>[];

        for (int i = headerRowIndex + 1; i < values.length; i++) {
          if (values[i].length <= codigoIndex) continue;

          final row = values[i];
          final producto = <String, dynamic>{};

          for (int j = 0; j < headers.length && j < row.length; j++) {
            producto[headers[j]] = row[j];
          }

          // Añadimos un índice basado en la posición en la hoja (fila)
          producto['INDICE'] = (i - headerRowIndex).toString();

          if (row.length > codigoIndex) {
            producto['CODIGO'] = row[codigoIndex].toString().trim();
            print("Producto procesado - CODIGO: ${producto['CODIGO']}, INDICE: ${producto['INDICE']}");
            productos.add(producto);
          }
        }

        print("Total de productos cargados: ${productos.length}");
        return productos;
      } else {
        print('Error al obtener productos: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Excepción al obtener productos: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> buscarProductoPorCodigo(String codigo) async {
    print("Buscando producto con código: $codigo");
    try {
      final productos = await obtenerProductos();
      if (productos.isEmpty) {
        print("No se cargaron productos de la hoja");
        return null;
      }
      
      for (var producto in productos) {
        if (producto['CODIGO']?.toString().trim() == codigo.trim()) {
          print("¡Producto encontrado!: $producto");
          return producto;
        }
      }
      
      print("No se encontró ningún producto con código: $codigo");
      return null;
    } catch (e) {
      print("Error en buscarProductoPorCodigo: $e");
      return null;
    }
  }

  // Nueva función para buscar por número de producto (índice)
  static Future<Map<String, dynamic>?> buscarProductoPorNumero(String numero) async {
    print("Buscando producto con número: $numero");
    try {
      final productos = await obtenerProductos();
      if (productos.isEmpty) {
        print("No se cargaron productos de la hoja");
        return null;
      }
      
      // Mostrar los primeros productos para depuración
      print("Muestra de productos disponibles:");
      for (int i = 0; i < min(5, productos.length); i++) {
        print("Producto $i: INDICE=${productos[i]['INDICE']}, CODIGO=${productos[i]['CODIGO']}");
      }
      
      // Buscar por el índice exacto
      for (var producto in productos) {
        if (producto['INDICE']?.toString().trim() == numero.trim()) {
          print("¡Producto encontrado por índice!: $producto");
          return producto;
        }
      }
      
      // Si no se encuentra por índice, intentar buscar por posición en la lista
      int numeroInt = int.tryParse(numero) ?? 0;
      if (numeroInt > 0 && numeroInt <= productos.length) {
        print("¡Producto encontrado por posición!: ${productos[numeroInt - 1]}");
        return productos[numeroInt - 1];
      }
      
      print("No se encontró ningún producto con número: $numero");
      return null;
    } catch (e) {
      print("Error en buscarProductoPorNumero: $e");
      return null;
    }
  }
}

// Función min para compatibilidad
int min(int a, int b) {
  return a < b ? a : b;
}