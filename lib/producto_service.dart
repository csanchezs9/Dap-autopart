import 'package:http/http.dart' as http;
import 'dart:convert';

class ProductoService {
  // URL base del servidor - Usar la misma configuración que en CatalogoService
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  // static const String baseUrl = 'http://localhost:3000'; // Para web
  static const String baseUrl = 'https://dapautopart.onrender.com'; // URL de producción

  static Future<List<Map<String, dynamic>>> obtenerProductos() async {
  final url = '$baseUrl/productos';
  
  try {
    final response = await http.get(Uri.parse(url)).timeout(
      Duration(seconds: 15),
      onTimeout: () => throw Exception('Tiempo de espera agotado. Verifique su conexión a internet.'),
    );
    
    print("Respuesta de la API: ${response.statusCode}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (!data.containsKey('success') || !data['success']) {
        print("Respuesta no exitosa: ${data['message'] ?? 'Error desconocido'}");
        return [];
      }

      if (!data.containsKey('productos') || data['productos'].isEmpty) {
        print("No se encontraron productos en la respuesta");
        return [];
      }

      final productos = <Map<String, dynamic>>[];
      final productosData = data['productos'] as List;

      // Debugging
      if (productosData.isNotEmpty) {
        print("Muestra de estructura de producto recibido: ${productosData.first}");
      }

      // Procesar cada producto del servidor
      for (int i = 0; i < productosData.length; i++) {
        final productoOriginal = Map<String, dynamic>.from(productosData[i]);
        
        // Normalizar el producto para nuestra aplicación
        final producto = normalizarProducto(productoOriginal, i);
        
        if (producto != null) {
          productos.add(producto);
        }
      }

      print("Total de productos procesados correctamente: ${productos.length}");
      return productos;
    } else {
      print('Error al obtener productos: ${response.statusCode} - ${response.body}');
      return [];
    }
  } catch (e) {
    print('Excepción al obtener productos: $e');
    throw Exception('Error de conexión: $e');
  }
}

  static Future<Map<String, dynamic>?> buscarProductoPorNumero(String numero) async {
  print("Buscando producto con número: $numero");
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
    
    // Primero intentamos buscar el producto directamente en el servidor
    final url = '$baseUrl/productos/$numero';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] && data.containsKey('producto')) {
        final productoOriginal = Map<String, dynamic>.from(data['producto']);
        print("Producto encontrado en servidor (raw): $productoOriginal");
        
        // Convertir a nuestro formato normalizado
        final producto = normalizarProducto(productoOriginal, 0);
        
        if (producto != null) {
          print("¡Producto encontrado por servidor y normalizado!: $producto");
          return producto;
        } else {
          print("Producto encontrado pero con formato inválido o agotado");
        }
      }
    }
    
    // Como alternativa, si el servidor no encuentra el producto,
    // o no está disponible, cargamos todos los productos y buscamos localmente
    final productos = await obtenerProductos();
    if (productos.isEmpty) {
      print("No se cargaron productos del servidor");
      return null;
    }
    
    // Depuración: mostrar algunas filas para ver estructura
    print("Primeros 3 productos disponibles:");
    for (int i = 0; i < min(3, productos.length); i++) {
      print("Índice $i: #=${productos[i]['#']}, CODIGO=${productos[i]['CODIGO']}");
    }
    
    // Buscar primero por número exacto
    var producto = productos.firstWhere(
      (p) => p['#'].toString().trim() == numero.trim(),
      orElse: () => <String, dynamic>{},
    );
    
    if (producto.isNotEmpty) {
      print("¡Producto encontrado por número exacto!: $producto");
      return producto;
    }
    
    // Si no se encuentra por número exacto, intentar interpretar como índice
    int numeroInt = int.tryParse(numero) ?? 0;
    if (numeroInt > 0 && numeroInt <= productos.length) {
      int indice = numeroInt - 1;
      print("Buscando producto en el índice: $indice");
      producto = productos[indice];
      print("¡Producto encontrado por índice!: $producto");
      return producto;
    }
    
    print("No se encontró ningún producto con número/índice: $numero");
    return null;
  } catch (e) {
    print("Error en buscarProductoPorNumero: $e");
    throw Exception('Error al buscar producto: $e');
  }
}
  
  // Método para normalizar un producto del formato del servidor al formato de la app
    static Map<String, dynamic>? normalizarProducto(Map<String, dynamic> productoOriginal, int indice) {
  if (productoOriginal.isEmpty) return null;
  
  // Producto normalizado
  final producto = <String, dynamic>{};
  
  // Verificar si está agotado
  bool agotado = false;
  if (productoOriginal.containsKey('ESTADO') && 
      productoOriginal['ESTADO'].toString().toUpperCase().contains('AGOTADO')) {
    agotado = true;
  }
  
  // Número secuencial
  if (productoOriginal.containsKey('#') && productoOriginal['#'] != null && 
      productoOriginal['#'].toString().trim().isNotEmpty) {
    producto['#'] = productoOriginal['#'].toString().trim();
  } else {
    producto['#'] = (indice + 1).toString();
  }
  
  // Código - Requerido
  if (productoOriginal.containsKey('CODIGO') && productoOriginal['CODIGO'].toString().trim().isNotEmpty) {
    producto['CODIGO'] = productoOriginal['CODIGO'].toString().trim();
  } else {
    return null; // Sin código válido no procesamos
  }
  
  // Descripción - Usar la del servidor si existe
  if (productoOriginal.containsKey('DESCRIPCION') && 
      productoOriginal['DESCRIPCION'] != null && 
      productoOriginal['DESCRIPCION'].toString().trim().isNotEmpty) {
    producto['DESCRIPCION'] = productoOriginal['DESCRIPCION'].toString().trim();
  } else {
    producto['DESCRIPCION'] = 'Producto ${producto['CODIGO']}';
  }
  
  // Ubicación / Bodega
  if (productoOriginal.containsKey('UB') && productoOriginal['UB'].toString().trim().isNotEmpty) {
    producto['UB'] = productoOriginal['UB'].toString().trim();
  } else if (productoOriginal.containsKey('BOD') && productoOriginal['BOD'].toString().trim().isNotEmpty) {
    producto['UB'] = productoOriginal['BOD'].toString().trim();
  } else {
    producto['UB'] = '';
  }
  
  // Referencia
  if (productoOriginal.containsKey('REF') && productoOriginal['REF'].toString().trim().isNotEmpty) {
    producto['REF'] = productoOriginal['REF'].toString().trim();
  } else {
    producto['REF'] = '';
  }
  
  // Origen
  if (productoOriginal.containsKey('ORIGEN') && productoOriginal['ORIGEN'].toString().trim().isNotEmpty) {
    producto['ORIGEN'] = productoOriginal['ORIGEN'].toString().trim();
  } else {
    producto['ORIGEN'] = '';
  }
  
  // Vehículo
  if (productoOriginal.containsKey('VEHICULO') && productoOriginal['VEHICULO'].toString().trim().isNotEmpty) {
    producto['VEHICULO'] = productoOriginal['VEHICULO'].toString().trim();
  } else {
    producto['VEHICULO'] = '';
  }
  
  // Marca
  if (productoOriginal.containsKey('MARCA') && productoOriginal['MARCA'].toString().trim().isNotEmpty) {
    producto['MARCA'] = productoOriginal['MARCA'].toString().trim();
  } else {
    producto['MARCA'] = '';
  }
  
  // Precio antes de IVA
  double precio = 0;
if (productoOriginal.containsKey('PRECIO')) {
  if (productoOriginal['PRECIO'] is num) {
    precio = (productoOriginal['PRECIO'] as num).toDouble();
  } else {
    precio = extractNumericValue(productoOriginal['PRECIO']);
  }
  
  // Log para depuración
  print("Precio original para ${producto['CODIGO']}: ${productoOriginal['PRECIO']} -> $precio");
}

// Guardar el precio real, sin dividir entre 1000
// La aplicación ya sabe que el formato debe ser en miles (ej. $4,530 representa 4530 pesos)
producto['VLR ANTES DE IVA'] = precio;
print("VLR ANTES DE IVA guardado como: ${producto['VLR ANTES DE IVA']}");
  
  // Descuento
  double descuento = 0;
  if (productoOriginal.containsKey('DSCTO')) {
    if (productoOriginal['DSCTO'] is num) {
      descuento = (productoOriginal['DSCTO'] as num).toDouble();
    } else {
      descuento = extractNumericValue(productoOriginal['DSCTO']);
    }
    
    // Asegurar que el descuento está en porcentaje (0-100)
    if (descuento > 100) descuento = 100;
    if (descuento < 0) descuento = 0;
    
    // Log para depuración
    print("Descuento original para ${producto['CODIGO']}: ${productoOriginal['DSCTO']}");
    print("Descuento procesado para ${producto['CODIGO']}: $descuento");
  }
  producto['DSCTO'] = descuento;
  
  // Estado de agotado
  producto['ESTADO'] = agotado ? 'AGOTADO' : '';
  
  return producto;
}

  
  
  // Método utilitario para extraer valor numérico, manejando diferentes formatos
    static double extractNumericValue(dynamic value) {
  if (value == null) return 0;
  
  if (value is num) return value.toDouble();
  
  String valueStr = value.toString().trim();
  
  // Log para depuración
  print("Extrayendo valor numérico de: '$valueStr'");
  
  try {
    // Intentar conversión directa primero
    return double.parse(valueStr);
  } catch (_) {
    // Si falla, intentar limpiar el valor
    try {
      valueStr = valueStr.replaceAll(RegExp(r'[^0-9\.,]'), ''); // Eliminar todo excepto números, puntos y comas
      
      if (valueStr.isEmpty) return 0;
      
      // Log después de limpiar
      print("Valor limpio: '$valueStr'");
      
      // Contar comas para determinar si son separadores de miles o decimales
      final commaCount = ','.allMatches(valueStr).length;
      
      if (commaCount > 1) {
        // Múltiples comas indican separadores de miles (4,530,000)
        valueStr = valueStr.replaceAll(',', '');
      } else if (valueStr.contains(',') && valueStr.contains('.')) {
        // Si contiene ambos, determinar cuál es el separador decimal
        if (valueStr.lastIndexOf(',') > valueStr.lastIndexOf('.')) {
          // La coma es el separador decimal (formato europeo)
          valueStr = valueStr.replaceAll('.', '').replaceAll(',', '.');
        } else {
          // El punto es el separador decimal (formato americano)
          valueStr = valueStr.replaceAll(',', '');
        }
      } else if (valueStr.contains(',')) {
        // Solo una coma, asumir como separador de miles en formato colombiano
        valueStr = valueStr.replaceAll(',', '');
      }
      
      // Log después de procesar separadores
      print("Valor procesado: '$valueStr'");
      
      double result = double.parse(valueStr);
      
      // No dividir entre 1000 aquí, mantener el valor real
      return result;
    } catch (e) {
      print("Error procesando valor numérico: '$value' -> '$valueStr' - $e");
      return 0;
    }
  }
}

}

// Función min para compatibilidad
int min(int a, int b) {
  return a < b ? a : b;
}