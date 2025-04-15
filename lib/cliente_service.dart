import 'package:http/http.dart' as http;
import 'dart:convert';

class ClienteService {
  static const String apiKey = 'AIzaSyBu51IfYHAXIodwktv8FU0E_TgSSlTNpPI';
  static const String sheetId = '1QrFE-NthFzKxK8tN9ZqjaZnwiLlFWUYkAvbtZTSdHz0';
  static const String sheetName = 'clientes'; // Nombre de la hoja para clientes

  // Método para obtener todos los clientes desde la hoja de Google Sheets
  static Future<List<Map<String, dynamic>>> obtenerClientes() async {
    final url = 'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$sheetName?key=$apiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      print("Respuesta de la API (clientes): ${response.statusCode}");

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

        // Identificar la fila de encabezados buscando la columna "NIT" o "NIT CLIENTE"
        int headerRowIndex = -1;
        for (int i = 0; i < values.length; i++) {
          if (values[i].any((cell) => 
            cell.toString().toUpperCase().contains('NIT'))) {
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

        // Buscar el índice de la columna NIT
        int nitIndex = headers.indexWhere((h) => 
          h.toUpperCase().contains('NIT'));
        if (nitIndex == -1) {
          print("No se encontró columna para NIT");
          nitIndex = 0; // Usamos el índice 0 por defecto para el NIT
        }
        
        print("Índice de la columna NIT: $nitIndex");

        final clientes = <Map<String, dynamic>>[];

        for (int i = headerRowIndex + 1; i < values.length; i++) {
          if (values[i].length <= nitIndex) continue;

          final row = values[i];
          final cliente = <String, dynamic>{};

          for (int j = 0; j < headers.length && j < row.length; j++) {
            cliente[headers[j]] = row[j];
          }

          if (row.length > nitIndex && row[nitIndex].toString().trim().isNotEmpty) {  
            clientes.add(cliente);
          }
        }

        print("Total de clientes cargados: ${clientes.length}");
        return clientes;
      } else {
        print('Error al obtener clientes: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Excepción al obtener clientes: $e');
      return [];
    }
  }

  // Método para buscar un cliente por su NIT
  static Future<Map<String, dynamic>?> buscarClientePorNIT(String nit) async {
    print("Buscando cliente con NIT: $nit");
    try {
      final clientes = await obtenerClientes();
      if (clientes.isEmpty) {
        print("No se cargaron clientes de la hoja");
        return null;
      }
      
      // Normalizar el NIT para la búsqueda (sin espacios)
      final nitNormalizado = nit.trim();
      
      // Mostrar los primeros clientes para depuración
      print("Muestra de clientes disponibles:");
      for (int i = 0; i < min(5, clientes.length); i++) {
        print("Cliente $i: ${clientes[i]}");
      }
      
      // Buscar por NIT
      for (var cliente in clientes) {
        String rowNit = '';
        
        // Probar diferentes claves que podrían contener el NIT del cliente
        if (cliente.containsKey('NIT CLIENTE')) {
          rowNit = cliente['NIT CLIENTE'].toString().trim();
        } else if (cliente.containsKey('NIT')) {
          rowNit = cliente['NIT'].toString().trim();
        } else if (cliente.containsKey('nit')) {
          rowNit = cliente['nit'].toString().trim();
        }
        
        if (rowNit == nitNormalizado) {
          print("¡Cliente encontrado!: $cliente");
          return cliente;
        }
      }
      
      print("No se encontró ningún cliente con NIT: $nit");
      return null;
    } catch (e) {
      print("Error en buscarClientePorNIT: $e");
      return null;
    }
  }
  
  // Método para buscar clientes por nombre (búsqueda parcial)
  static Future<List<Map<String, dynamic>>> buscarClientesPorNombre(String nombre) async {
    print("Buscando clientes con nombre que contiene: $nombre");
    try {
      final clientes = await obtenerClientes();
      if (clientes.isEmpty) {
        print("No se cargaron clientes de la hoja");
        return [];
      }
      
      // Normalizar el nombre para la búsqueda (minúsculas sin espacios extra)
      final nombreNormalizado = nombre.trim().toLowerCase();
      if (nombreNormalizado.isEmpty) {
        return [];
      }
      
      final resultados = <Map<String, dynamic>>[];
      
      // Buscar por nombre (coincidencia parcial)
      for (var cliente in clientes) {
        String rowNombre = '';
        
        // Probar diferentes claves que podrían contener el nombre del cliente
        if (cliente.containsKey('NOMBRE')) {
          rowNombre = cliente['NOMBRE'].toString().toLowerCase();
        } else if (cliente.containsKey('nombre')) {
          rowNombre = cliente['nombre'].toString().toLowerCase();
        } else if (cliente.containsKey('RAZON SOCIAL')) {
          rowNombre = cliente['RAZON SOCIAL'].toString().toLowerCase();
        } else if (cliente.containsKey('ESTABLECIMIENTO')) {
          rowNombre = cliente['ESTABLECIMIENTO'].toString().toLowerCase();
        }
        
        if (rowNombre.contains(nombreNormalizado)) {
          resultados.add(cliente);
        }
      }
      
      print("Se encontraron ${resultados.length} clientes con el nombre: $nombre");
      return resultados;
    } catch (e) {
      print("Error en buscarClientesPorNombre: $e");
      return [];
    }
  }
}

// Función utilitaria min para compatibilidad
int min(int a, int b) {
  return a < b ? a : b;
}