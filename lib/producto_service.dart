import 'package:http/http.dart' as http;
import 'dart:convert';

class ProductoService {
  // URL base del servidor - Usar la misma configuración que en CatalogoService
  static const String baseUrl = 'http://10.0.2.2:3000'; // Para emulador Android
  // static const String baseUrl = 'http://localhost:3000'; // Para web
  // static const String baseUrl = 'http://192.168.1.X:3000'; // Para dispositivo real (cambia la IP)

  static Future<List<Map<String, dynamic>>> obtenerProductos() async {
    final url = '$baseUrl/productos';
    
    try {
      final response = await http.get(Uri.parse(url));
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
      return [];
    }
  }

  static Future<Map<String, dynamic>?> buscarProductoPorNumero(String numero) async {
    print("Buscando producto con número: $numero");
    try {
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
      return null;
    }
  }
  
  // Método para normalizar un producto del formato del servidor al formato de la app
  static Map<String, dynamic>? normalizarProducto(Map<String, dynamic> productoOriginal, int indice) {
    if (productoOriginal.isEmpty) return null;
    
    // Verificar si está agotado
    bool agotado = false;
    if (productoOriginal.containsKey('ESTADO') && 
        productoOriginal['ESTADO'].toString().toUpperCase().contains('AGOTADO')) {
      agotado = true;
    }
    
    // Producto normalizado
    final producto = <String, dynamic>{};
    
    // Número secuencial
    if (productoOriginal.containsKey('#') && productoOriginal['#'] != null && 
        productoOriginal['#'].toString().trim().isNotEmpty) {
      producto['#'] = productoOriginal['#'].toString().trim();
    } else {
      producto['#'] = (indice + 1).toString();
    }
    
    // Código
    if (productoOriginal.containsKey('CODIGO') && productoOriginal['CODIGO'].toString().trim().isNotEmpty) {
      producto['CODIGO'] = productoOriginal['CODIGO'].toString().trim();
    } else {
      return null; // Sin código válido no procesamos
    }
    
    // Descripción - Procesamiento mejorado
    if (productoOriginal.containsKey('DESCRIPCION') && productoOriginal['DESCRIPCION'] != null) {
      String descripcion = productoOriginal['DESCRIPCION'].toString().trim();
      if (descripcion.isNotEmpty) {
        producto['DESCRIPCION'] = descripcion;
      } else {
        // Intentar inferir descripción del código si está disponible
        String codigo = producto['CODIGO'].toString();
        if (codigo.isNotEmpty) {
          // Mapeo de algunos códigos comunes para mostrar descripción si está vacía
          switch (codigo) {
            case 'H1245': producto['DESCRIPCION'] = 'ABRAZADERA BUJE PUÑO'; break;
            case 'H4211': producto['DESCRIPCION'] = 'BOMBA AGUA'; break;
            case 'R0197': producto['DESCRIPCION'] = 'ABRAZADERA CAJA DIR'; break;
            case 'K0182': producto['DESCRIPCION'] = 'BIELETA SUSPENSION DEL RH'; break;
            default: producto['DESCRIPCION'] = 'Producto ${codigo}';
          }
        } else {
          producto['DESCRIPCION'] = 'Producto #${producto['#']}';
        }
      }
    } else {
      // Si no hay campo de descripción, usar el código como descripción
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
    if (productoOriginal.containsKey('PRECIO') && productoOriginal['PRECIO'] != null) {
      precio = extractNumericValue(productoOriginal['PRECIO']);
    }
    producto['VLR ANTES DE IVA'] = precio;
    
    // Descuento
    double descuento = 0;
    if (productoOriginal.containsKey('DSCTO') && productoOriginal['DSCTO'] != null) {
      descuento = extractNumericValue(productoOriginal['DSCTO']);
    }
    producto['DSCTO'] = descuento;
    
    // Estado de agotado
    producto['ESTADO'] = agotado ? 'AGOTADO' : '';
    
    // Si está agotado y decidimos no incluir productos agotados, retornar null
    // O podemos incluirlos todos y manejar el filtrado en la UI
    return producto;
  }
  
  // Método utilitario para extraer valor numérico, manejando diferentes formatos
  static double extractNumericValue(dynamic value) {
    if (value == null) return 0;
    
    if (value is num) return value.toDouble();
    
    String valueStr = value.toString().trim();
    
    try {
      // Intentar conversión directa primero
      return double.parse(valueStr);
    } catch (_) {
      // Si falla, intentar limpiar el valor
      try {
        valueStr = valueStr.replaceAll(RegExp(r'[^0-9\.,]'), ''); // Eliminar todo excepto números, puntos y comas
        
        if (valueStr.isEmpty) return 0;
        
        // Manejar diferentes formatos de números
        if (valueStr.contains(',') && valueStr.contains('.')) {
          // Si contiene ambos, determinar cuál es el separador decimal
          if (valueStr.lastIndexOf(',') > valueStr.lastIndexOf('.')) {
            // La coma es el separador decimal (formato europeo)
            valueStr = valueStr.replaceAll('.', '').replaceAll(',', '.');
          } else {
            // El punto es el separador decimal (formato americano)
            valueStr = valueStr.replaceAll(',', '');
          }
        } else if (valueStr.contains(',')) {
          // Solo contiene comas, asumir como separador decimal
          valueStr = valueStr.replaceAll(',', '.');
        }
        
        return double.parse(valueStr);
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