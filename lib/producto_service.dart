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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!data.containsKey('values')) return [];

        final values = data['values'] as List;
        if (values.isEmpty) return [];

        int headerRowIndex = -1;
        for (int i = 0; i < values.length; i++) {
          if (values[i].any((cell) => 
            cell.toString().toUpperCase().contains('CODIGO') || 
            cell.toString() == '#')) {
            headerRowIndex = i;
            break;
          }
        }

        if (headerRowIndex == -1) return [];

        final headers = List<String>.from(values[headerRowIndex].map((e) => e.toString().trim()));

        int codigoIndex = headers.indexWhere((h) => 
          h.toUpperCase().contains('CODIGO') || h == '#');
        if (codigoIndex == -1) codigoIndex = 1;

        final productos = <Map<String, dynamic>>[];

        for (int i = headerRowIndex + 1; i < values.length; i++) {
          if (values[i].length <= codigoIndex) continue;

          final row = values[i];
          final producto = <String, dynamic>{};

          for (int j = 0; j < headers.length && j < row.length; j++) {
            producto[headers[j]] = row[j];
          }

          if (row.length > codigoIndex) {
            producto['CODIGO'] = row[codigoIndex].toString().trim();
            productos.add(producto);
          }
        }

        return productos;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> buscarProductoPorCodigo(String codigo) async {
    final productos = await obtenerProductos();
    if (productos.isEmpty) return null;

    for (var producto in productos) {
      if (producto['CODIGO']?.toString().trim() == codigo.trim()) {
        return producto;
      }
    }

    return null;
  }
}
