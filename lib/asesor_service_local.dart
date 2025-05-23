import 'package:http/http.dart' as http;
import 'dart:convert';

class AsesorServiceLocal {
  // URL base del servidor - Deberás ajustarla según la ubicación de tu servidor
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  // static const String baseUrl = 'http://localhost:3000'; // Para web
  //static const String baseUrl = 'http://192.168.1.2:3000'; // Para dispositivo real (cambia la IP)
  //https://dap-autoparts.onrender.com
  static const String baseUrl = 'https://dap-autoparts.onrender.com'; // URL de producción
  // Método para obtener todos los asesores desde el servidor
  static Future<List<Map<String, dynamic>>> obtenerAsesores() async {
  final url = '$baseUrl/asesores';
  
  try {
    final response = await http.get(Uri.parse(url)).timeout(
      Duration(seconds: 10),
      onTimeout: () => throw Exception('Tiempo de espera agotado. Verifique su conexión a internet.'),
    );
    
    print("Respuesta de la API (asesores): ${response.statusCode}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      
      if (!data.containsKey('success') || !data['success']) {
        print("Respuesta no exitosa: ${data['message'] ?? 'Error desconocido'}");
        return [];
      }

      if (!data.containsKey('asesores') || data['asesores'].isEmpty) {
        print("No se encontraron asesores en la respuesta");
        return [];
      }

      final asesoresData = data['asesores'] as List;
      final asesores = asesoresData.map((asesor) => Map<String, dynamic>.from(asesor)).toList();
      
      print("Total de asesores cargados: ${asesores.length}");
      return asesores;
    } else {
      print('Error al obtener asesores: ${response.statusCode} - ${response.body}');
      return [];
    }
  } catch (e) {
    print('Excepción al obtener asesores: $e');
    // Relanzar la excepción para que pueda ser manejada por quien llama a este método
    throw Exception('Error de conexión: $e');
  }
}


  // Método para buscar un asesor por su ID
  static Future<Map<String, dynamic>?> buscarAsesorPorID(String id) async {
  print("Buscando asesor con ID: $id");
  try {
    // Verificar conectividad con un ping rápido
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
      throw Exception('No se puede conectar al servidor. Verifique su conexión a internet.');
    }
    
    // Primero intentamos buscar el asesor directamente del servidor
    final url = '$baseUrl/asesores/$id';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] && data.containsKey('asesor')) {
        final asesor = Map<String, dynamic>.from(data['asesor']);
        print("¡Asesor encontrado!: $asesor");
        return asesor;
      }
    }
    
    // Si no se encuentra por endpoint específico, buscar en la lista completa
    final asesores = await obtenerAsesores();
    if (asesores.isEmpty) {
      print("No se cargaron asesores del servidor");
      return null;
    }
    
    // Buscar por ID normalizado
    final idNormalizado = id.trim();
    final asesorEncontrado = asesores.firstWhere(
      (asesor) => asesor['ID'].toString().trim() == idNormalizado,
      orElse: () => <String, dynamic>{},
    );
    
    if (asesorEncontrado.isNotEmpty) {
      print("¡Asesor encontrado en la lista!: $asesorEncontrado");
      return asesorEncontrado;
    }
    
    print("No se encontró ningún asesor con ID: $id");
    return null;
  } catch (e) {
    print("Error en buscarAsesorPorID: $e");
    throw Exception('Error al buscar asesor: $e');
  }
}

  
  // Método para buscar un asesor por su correo
  static Future<Map<String, dynamic>?> buscarAsesorPorCorreo(String correo) async {
  print("Buscando asesor con correo: $correo");
  try {
    // Verificar conectividad con un ping rápido
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
      throw Exception('No se puede conectar al servidor. Verifique su conexión a internet.');
    }
    
    // Primero intentamos buscar el asesor directamente del servidor
    final correoNormalizado = correo.trim().toLowerCase();
    final url = '$baseUrl/asesores/correo/${Uri.encodeComponent(correoNormalizado)}';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] && data.containsKey('asesor')) {
        final asesor = Map<String, dynamic>.from(data['asesor']);
        print("¡Asesor encontrado por correo!: $asesor");
        return asesor;
      }
    }
    
    // Si no se encuentra por endpoint específico, buscar en la lista completa
    final asesores = await obtenerAsesores();
    if (asesores.isEmpty) {
      print("No se cargaron asesores del servidor");
      return null;
    }
    
    // Buscar por correo normalizado
    final asesorEncontrado = asesores.firstWhere(
      (asesor) => asesor['MAIL'].toString().trim().toLowerCase() == correoNormalizado,
      orElse: () => <String, dynamic>{},
    );
    
    if (asesorEncontrado.isNotEmpty) {
      print("¡Asesor encontrado en la lista por correo!: $asesorEncontrado");
      return asesorEncontrado;
    }
    
    print("No se encontró ningún asesor con correo: $correo");
    return null;
  } catch (e) {
    print("Error en buscarAsesorPorCorreo: $e");
    throw Exception('Error al buscar asesor: $e');
  }
}
}