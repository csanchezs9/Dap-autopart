import 'package:http/http.dart' as http;
import 'dart:convert';

class ClienteServiceLocal {
  // URL base del servidor - Deberás ajustarla según la ubicación de tu servidor
  static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  // static const String baseUrl = 'http://localhost:3000'; // Para web
  // static const String baseUrl = 'http://192.168.1.X:3000'; // Para dispositivo real (cambia la IP)

  // Método para obtener todos los clientes desde el servidor
  static Future<List<Map<String, dynamic>>> obtenerClientes() async {
    final url = '$baseUrl/clientes';
    
    try {
      final response = await http.get(Uri.parse(url));
      print("Respuesta de la API (clientes): ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (!data.containsKey('success') || !data['success']) {
          print("Respuesta no exitosa: ${data['message'] ?? 'Error desconocido'}");
          return [];
        }

        if (!data.containsKey('clientes') || data['clientes'].isEmpty) {
          print("No se encontraron clientes en la respuesta");
          return [];
        }

        final clientesData = data['clientes'] as List;
        final clientes = clientesData.map((cliente) => Map<String, dynamic>.from(cliente)).toList();
        
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
      // Primero intentamos buscar el cliente directamente del servidor
      final url = '$baseUrl/clientes/$nit';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data.containsKey('cliente')) {
          final cliente = Map<String, dynamic>.from(data['cliente']);
          print("¡Cliente encontrado!: $cliente");
          return cliente;
        }
      }
      
      // Si no se encuentra por endpoint específico, buscar en la lista completa
      final clientes = await obtenerClientes();
      if (clientes.isEmpty) {
        print("No se cargaron clientes del servidor");
        return null;
      }
      
      // Normalizar el NIT para la búsqueda (sin espacios)
      final nitNormalizado = nit.trim();
      
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
      // Normalizar el nombre para la búsqueda (minúsculas sin espacios extra)
      final nombreNormalizado = nombre.trim().toLowerCase();
      if (nombreNormalizado.isEmpty) {
        return [];
      }
      
      // Obtener todos los clientes
      final clientes = await obtenerClientes();
      if (clientes.isEmpty) {
        print("No se cargaron clientes del servidor");
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