import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data'; 
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'producto_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';




class ProductosOrden extends StatefulWidget {
  final Map<String, String> clienteData;
  final Map<String, String> asesorData;
  final String ordenNumero;


  const ProductosOrden({
    Key? key, 
    required this.clienteData, 
    required this.asesorData,
    
    required this.ordenNumero,
  }) : super(key: key);

  @override
  State<ProductosOrden> createState() => _ProductosOrdenState();
}

enum TipoPedido { normal, condicionado, contado }

class _ProductosOrdenState extends State<ProductosOrden> with TickerProviderStateMixin {
  List<Map<String, dynamic>> productosAgregados = [];
  final TextEditingController numeroController = TextEditingController();
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionesController = TextEditingController();
   final FocusNode observacionesFocusNode = FocusNode();
  
  late String numeroOrdenActual;
  bool isLoading = false;
  String errorMessage = '';
  
  // Controlador de animación
  late AnimationController _animationController;
  
  // Valores para los checkboxes
  bool isNormal = true;
  bool isCondicionado = false;
  bool isContado = false;

  TipoPedido tipoPedidoSeleccionado = TipoPedido.normal;
  
  // Variables para el total
  double valorBrutoTotal = 0;
  double descuentoTotal = 0;
  double subtotal = 0;
  double iva = 0;
  double total = 0;
  
  // Variable para el producto seleccionado actual
  String? productoCodigoSeleccionado;
  String? productoNumeroSeleccionado;
  
  // Cache de imágenes disponibles
  final Map<String, bool> _imagenesDisponibles = {};
  
  // GlobalKey para capturar la vista previa
  final GlobalKey _vistaPreviewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es_ES', null);
    
    // Inicializar el controlador de animación
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    numeroOrdenActual = widget.ordenNumero;

    observacionesFocusNode.addListener(() {
      print("Cambio de foco en observaciones: ${observacionesFocusNode.hasFocus}");
    });

  }

  void actualizarNumeroOrden(String nuevoNumero) {
    setState(() {
      numeroOrdenActual = nuevoNumero;
    });
  }
  
  @override
  void dispose() {
    observacionesFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _ocultarTeclado() {
    print("Intentando ocultar teclado...");
    
    // Primera estrategia: unfocus en el FocusNode específico
    if (observacionesFocusNode.hasFocus) {
      observacionesFocusNode.unfocus();
    }
    
    // Segunda estrategia: quitar foco de todo el contexto
    FocusScope.of(context).unfocus();
    
    // Tercera estrategia: mover el foco a otro widget
    FocusScope.of(context).requestFocus(FocusNode());
    
    // Cuarta estrategia: forzar ocultar el teclado usando SystemChannels
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  String obtenerFechaActual() {
  final now = DateTime.now();
  try {
    // En lugar de usar caracteres especiales como guiones que pueden causar problemas,
    // usemos un formato más simple y controlado
    final formatter = DateFormat('dd/MM/yyyy', 'es_ES');
    String fecha = formatter.format(now);
    return fecha;
  } catch (e) {
    print("Error al formatear fecha: $e");
    // Formato de respaldo simple en caso de error
    return "${now.day}/${now.month}/${now.year}";
  }
}

  // Ajuste en la clase _ProductosOrdenState para modificar la función buscarProductoPorNumero

 void buscarProductoPorNumero() async {
  String numero = numeroController.text.trim();
  if (numero.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Por favor ingrese un número de producto')),
    );
    return;
  }
  
  // Mostrar indicador de carga
  setState(() {
    isLoading = true;
  });
  
  try {
    // Verificar conectividad con un ping rápido
    try {
      final pingResponse = await http.get(
        Uri.parse('${ProductoService.baseUrl}/ping'),
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
    
    // Obtener cantidad
    int cantidad = 1;
    if (cantidadController.text.isNotEmpty) {
      cantidad = int.tryParse(cantidadController.text.trim()) ?? 1;
    }
    
    // Buscar producto por número en el servidor con un log más detallado
    print("Buscando producto con número: $numero");
    final productoEncontrado = await ProductoService.buscarProductoPorNumero(numero);
    
    if (productoEncontrado != null) {
      // Verificar si el producto encontrado tiene el número correcto
      print("Producto encontrado: #${productoEncontrado['#']} - ${productoEncontrado['CODIGO']}");
      
      // Verificar si está agotado 
      bool agotado = false;
      if (productoEncontrado.containsKey('ESTADO')) {
        agotado = productoEncontrado['ESTADO'].toString().toUpperCase().contains('AGOTADO');
      }
      
      if (agotado) {
        // Mostrar alerta de producto agotado
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Producto Agotado'),
              content: Text('El producto número $numero está agotado y no puede ser añadido a la orden.'),
              actions: [
                TextButton(
                  child: const Text('Aceptar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      } else {
        // Verificamos explícitamente que estamos usando el número correcto
        final numeroProducto = productoEncontrado['#']?.toString() ?? '';
        final codigoProducto = productoEncontrado['CODIGO']?.toString() ?? '';
        
        print("Agregando producto: #$numeroProducto - Código: $codigoProducto");
        
        Map<String, dynamic> producto = {
          '#': numeroProducto,
          'CODIGO': codigoProducto,
          'CANT': cantidad
        };
        
        // Mapeo de campos que vienen del servidor - con validación adicional
        producto['UB'] = productoEncontrado['UB'] ?? '';
        producto['REF'] = productoEncontrado['REF'] ?? '';
        producto['ORIGEN'] = productoEncontrado['ORIGEN'] ?? '';
        producto['DESCRIPCION'] = productoEncontrado['DESCRIPCION'] ?? '';
        producto['VEHICULO'] = productoEncontrado['VEHICULO'] ?? '';
        producto['MARCA'] = productoEncontrado['MARCA'] ?? '';
        
        // Procesar precio - Asegurar que es un número
        double valorUnidad = 0;
        if (productoEncontrado.containsKey('VLR ANTES DE IVA')) {
          if (productoEncontrado['VLR ANTES DE IVA'] is num) {
            valorUnidad = (productoEncontrado['VLR ANTES DE IVA'] as num).toDouble();
          } else {
            valorUnidad = double.tryParse(productoEncontrado['VLR ANTES DE IVA'].toString()) ?? 0;
          }
        }
        
        producto['VLR ANTES DE IVA'] = valorUnidad;
        
        // Procesar descuento - Asegurar que es un número
        double descuentoOriginal = 0;
        if (productoEncontrado.containsKey('DSCTO')) {
          if (productoEncontrado['DSCTO'] is num) {
            descuentoOriginal = (productoEncontrado['DSCTO'] as num).toDouble();
          } else {
            descuentoOriginal = double.tryParse(productoEncontrado['DSCTO'].toString().replaceAll('%', '')) ?? 0;
          }
        }
        
        // Guardar descuento original
        producto['DSCTO_ORIGINAL'] = descuentoOriginal;
        
        // Aplicar descuento según modo actual
        if (isCondicionado) {
          producto['DSCTO'] = 0.0;
        } else if (isContado) {
          // Solo aumentar 2% si el descuento original es exactamente 15% o 20%
          if (descuentoOriginal == 15.0 || descuentoOriginal == 20.0) {
            producto['DSCTO'] = descuentoOriginal + 2.0; // Aumentar 2% en modo CONTADO
          } else {
            producto['DSCTO'] = descuentoOriginal; // Mantener el descuento original para otros valores
          }
        } else {
          producto['DSCTO'] = descuentoOriginal;
        }
        
        double valorBruto = valorUnidad * cantidad;
        producto['V.BRUTO'] = valorBruto;
        
        // Verificación final antes de agregar
        print("Agregando producto a la lista:");
        productoEncontrado.forEach((key, value) {
          print("  $key: $value");
        });
        
        setState(() {
          // Verificar si ya existe este producto en la lista
          final productoExistente = productosAgregados.firstWhere(
            (p) => p['#'] == numeroProducto,
            orElse: () => <String, dynamic>{},
          );
          
          if (productoExistente.isNotEmpty) {
            // Producto ya existe, preguntar si desea actualizar la cantidad
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text('Producto ya en lista'),
                  content: Text('El producto #$numeroProducto ya está en la lista. ¿Desea aumentar la cantidad?'),
                  actions: [
                    TextButton(
                      child: Text('Cancelar'),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1A4379),
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Aumentar'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Actualizar la cantidad
                        setState(() {
                          productoExistente['CANT'] = (productoExistente['CANT'] as int) + cantidad;
                          // Recalcular V.BRUTO
                          productoExistente['V.BRUTO'] = productoExistente['VLR ANTES DE IVA'] * productoExistente['CANT'];
                          calcularTotales();
                        });
                      },
                    ),
                  ],
                );
              },
            );
          } else {
            // Producto nuevo, agregarlo a la lista
            productosAgregados.add(producto);
            calcularTotales();
            
            productoCodigoSeleccionado = codigoProducto;
            _checkImageExistence(codigoProducto);
          }
          
          // Limpiar campos de entrada
          numeroController.clear();
          cantidadController.clear();
        });
      }
    } else {
      // Si no se encuentra, mostrar mensaje
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró producto con número: $numero')),
      );
    }
  } catch (e) {
    // Mensaje más informativo según el tipo de error
    String errorMsg = 'Error al buscar producto';
    
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
    } else {
      errorMsg = 'Error al procesar el producto: $e';
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
    
    print("Error al buscar producto: $e");
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}



String _formatMoneda(dynamic valor) {
  if (valor == null) return '\$0';
  
  double numValor;
  if (valor is num) {
    numValor = valor.toDouble();
  } else {
    try {
      numValor = double.parse(valor.toString().replaceAll('\$', '').replaceAll(',', '').trim());
    } catch (e) {
      return '\$0';
    }
  }
  
  // Imprimir para depuración
  print("Formateando valor monetario: $numValor");
  
  // Usar NumberFormat para formato colombiano sin decimales
  final formatter = NumberFormat("#,###", "es_CO");
  return '\$${formatter.format(numValor)}';
}

 
Widget _buildCompactInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

// Función para construir filas de información compactas en el PDF
pw.Widget _buildPDFCompactInfoRow(String label, String value) {
  return pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 7)),
        ),
      ],
    ),
  );
}


Future<Uint8List?> _generarPDFMejorado() async {
   try {
    // Crear un documento PDF con mejor manejo de textos largos
    final pdf = pw.Document();
    final ByteData logoData = await rootBundle.load('assets/images/logo.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final logoImage = pw.MemoryImage(logoBytes);
    
    // Registrar la fuente Roboto para soporte de caracteres especiales
    final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final ttf = pw.Font.ttf(fontData.buffer.asByteData());
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(30),
        // Construir el PDF con flujo de contenido automático
        header: (pw.Context context) {
          // Solo mostrar encabezado completo en la primera página
          if (context.pageNumber == 1) {
            return pw.Column(
              children: [
                // Encabezado con logo DAP
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo
                    pw.Row(
      children: [
        pw.Image(logoImage, width: 90, height: 60),
        pw.SizedBox(width: 10),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Distribuciones Autoparts S.A.S'),
            pw.Text('Nit: 901.110.424-1'),
          ],
        ),
      ],
    ),
                    
                    // Información de la orden
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('FECHA: ${obtenerFechaActual()}', 
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('ORDEN DE PEDIDO #: ${numeroOrdenActual}', 
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 20),
                
                // Información del cliente
               pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Información del cliente
                      pw.Expanded(
                        child: pw.Container(
                          margin: pw.EdgeInsets.only(right: 8),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Container(
                                color: PdfColors.blue900,
                                padding: pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                width: double.infinity,
                                child: pw.Text(
                                  'INFORMACIÓN DEL CLIENTE',
                                  style: pw.TextStyle(
                                    color: PdfColors.white,
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: pw.EdgeInsets.all(5),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    _buildPDFCompactInfoRow('NIT:', widget.clienteData['NIT CLIENTE'] ?? ''),
                                    _buildPDFCompactInfoRow('NOMBRE:', widget.clienteData['NOMBRE'] ?? ''),
                                    _buildPDFCompactInfoRow('ESTABLECIMIENTO:', widget.clienteData['ESTABLECIMIENTO'] ?? ''),
                                    _buildPDFCompactInfoRow('DIRECCIÓN:', widget.clienteData['DIRECCION'] ?? ''),
                                    _buildPDFCompactInfoRow('TELÉFONO:', widget.clienteData['TELEFONO'] ?? ''),
                                    _buildPDFCompactInfoRow('DESCUENTO:', widget.clienteData['DESCTO'] ?? ''),
                                    _buildPDFCompactInfoRow('CIUDAD:', widget.clienteData['CLI_CIUDAD'] ?? ''),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Información del asesor
                      pw.Expanded(
                        child: pw.Container(
                          margin: pw.EdgeInsets.only(left: 8),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Container(
                                color: PdfColors.blue900,
                                padding: pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                width: double.infinity,
                                child: pw.Text(
                                  'INFORMACIÓN DEL ASESOR',
                                  style: pw.TextStyle(
                                    color: PdfColors.white,
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: pw.EdgeInsets.all(5),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    _buildPDFCompactInfoRow('ID:', widget.asesorData['ID'] ?? ''),
                                    _buildPDFCompactInfoRow('NOMBRE:', widget.asesorData['NOMBRE'] ?? ''),
                                    _buildPDFCompactInfoRow('ZONA:', widget.asesorData['ZONA'] ?? ''),
                                    _buildPDFCompactInfoRow('TELÉFONO:', widget.asesorData['CEL'] ?? ''),
                                    _buildPDFCompactInfoRow('CORREO:', widget.asesorData['MAIL'] ?? ''),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                
                pw.SizedBox(height: 20),
              ],
            );
          } else {
            // Para las páginas siguientes, mostrar un encabezado simple
            return pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'DAP AutoPart\'s',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.Text(
                      'ORDEN DE PEDIDO #: ${numeroOrdenActual} - Página ${context.pageNumber}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
              ],
            );
          }
        },
        footer: (pw.Context context) {
          return pw.Center(
            child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}'),
          );
        },
        build: (pw.Context context) {
          return [
            // Encabezado de Productos
            pw.Container(
              color: PdfColors.blue900,
              padding: pw.EdgeInsets.all(8),
              width: double.infinity,
              child: pw.Text(
                'PRODUCTOS',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            
            // Tabla de productos completa
            pw.Table(
  border: pw.TableBorder.all(width: 0.5), // Borde más delgado
  columnWidths: {
    0: pw.FixedColumnWidth(18),  // # - más compacto
    1: pw.FixedColumnWidth(40),  // CÓDIGO
    2: pw.FixedColumnWidth(25),  // UB - más compacto
    3: pw.FixedColumnWidth(45),  // REF
    4: pw.FixedColumnWidth(40),  // ORIGEN - ajustado
    5: pw.FlexColumnWidth(5.0),  // DESCRIPCIÓN
    6: pw.FlexColumnWidth(4.0),  // VEHÍCULO
    7: pw.FixedColumnWidth(35),  // MARCA - más compacto
    8: pw.FixedColumnWidth(45),  // ANTES IVA - ajustado al contenido
    9: pw.FixedColumnWidth(30),  // DSCTO - más compacto
    10: pw.FixedColumnWidth(25), // CANT - más compacto
    11: pw.FixedColumnWidth(45), // V.BRUTO - ajustado al contenido
  },
  children: [
    // Encabezado
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColors.blue900),
      children: [
        _buildPDFHeaderCell('#'),
        _buildPDFHeaderCell('CÓDIGO'),
        _buildPDFHeaderCell('UB'),
        _buildPDFHeaderCell('REF'),
        _buildPDFHeaderCell('ORIGEN'),
        _buildPDFHeaderCell('DESCRIPCIÓN'),
        _buildPDFHeaderCell('VEHÍCULO'),
        _buildPDFHeaderCell('MARCA'),
        _buildPDFHeaderCell('V. ANTES IVA'),
        _buildPDFHeaderCell('DSCTO'),
        _buildPDFHeaderCell('CANT'),
        _buildPDFHeaderCell('V.BRUTO'),
      ],
    ),
    
    // Filas de productos
    ...productosAgregados.map((producto) => pw.TableRow(
  children: [
    _buildPDFDataCell(producto['#']?.toString() ?? '', columnIndex: 0),
    _buildPDFDataCell(producto['CODIGO']?.toString() ?? '', columnIndex: 1),
    _buildPDFDataCell(producto['UB']?.toString() ?? '', columnIndex: 2),
    _buildPDFDataCell(producto['REF']?.toString() ?? '', columnIndex: 3),
    _buildPDFDataCell(producto['ORIGEN']?.toString() ?? '', columnIndex: 4),
    _buildPDFDataCell(producto['DESCRIPCION']?.toString() ?? '', 
                     style: pw.TextStyle(fontSize: 6, font: ttf), columnIndex: 5),
    _buildPDFDataCell(producto['VEHICULO']?.toString() ?? '', 
                     style: pw.TextStyle(fontSize: 6, font: ttf), columnIndex: 6),
    _buildPDFDataCell(producto['MARCA']?.toString() ?? '', columnIndex: 7),
    _buildPDFDataCell(formatCurrency(producto['VLR ANTES DE IVA']),
                     style: pw.TextStyle(fontSize: 6), columnIndex: 8),
    _buildPDFDataCell(formatearPorcentaje(producto['DSCTO']), columnIndex: 9),
    _buildPDFDataCell(producto['CANT']?.toString() ?? '', columnIndex: 10),
    _buildPDFDataCell(formatCurrency(producto['V.BRUTO']),
                     style: pw.TextStyle(fontSize: 6), columnIndex: 11),
  ],
)).toList(),
  ],
),

            
            pw.SizedBox(height: 20),
            
            // Sección inferior: Observaciones y Totales
            pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    // Observaciones - Con altura ajustable según el contenido
    pw.Expanded(
      flex: 3,
      child: pw.Container(
        // Altura ajustable según el contenido (eliminar height fija)
        decoration: pw.BoxDecoration(
          border: pw.Border.all(),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min, // Hace que se ajuste al contenido
          children: [
            pw.Container(
              color: PdfColors.blue900,
              padding: pw.EdgeInsets.all(5),
              width: double.infinity,
              child: pw.Text(
                'OBSERVACIONES',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
            ),
            pw.Container(
              padding: pw.EdgeInsets.all(5),
              // Contenido ajustable a un mínimo y máximo
              constraints: pw.BoxConstraints(
                minHeight: 20, // Altura mínima para cuando hay poco texto
                maxHeight: 80, // Altura máxima para cuando hay mucho texto
              ),
              child: pw.Text(
                observacionesController.text.isEmpty ? 
                'Sin observaciones' : observacionesController.text,
                style: pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    ),
    
    pw.SizedBox(width: 15),
    
    // Totales - Mantener la estructura actual
    pw.Container(
      width: 140,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(),
            ),
            child: pw.Padding(
              padding: pw.EdgeInsets.all(4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('V.BRUTO', style: pw.TextStyle(fontSize: 8)),
                  pw.Text(formatCurrency(valorBrutoTotal), style: pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
          ),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(),
                            right: pw.BorderSide(),
                            bottom: pw.BorderSide(),
                          ),
                        ),
                        child: pw.Padding(
                          padding: pw.EdgeInsets.all(4), // Reducido de 8
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('DSCTO', style: pw.TextStyle(fontSize: 8)),
                              pw.Text(formatCurrency(descuentoTotal), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                      ),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(),
                            right: pw.BorderSide(),
                            bottom: pw.BorderSide(),
                          ),
                        ),
                        child: pw.Padding(
                          padding: pw.EdgeInsets.all(4), // Reducido de 8
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('SUBTOTAL', style: pw.TextStyle(fontSize: 8)),
                              pw.Text(formatCurrency(subtotal), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                      ),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(),
                            right: pw.BorderSide(),
                            bottom: pw.BorderSide(),
                          ),
                        ),
                        child: pw.Padding(
                          padding: pw.EdgeInsets.all(4), // Reducido de 8
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('IVA', style: pw.TextStyle(fontSize: 8)),
                              pw.Text(formatCurrency(iva), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                      ),
                      pw.Container(
                        color: PdfColors.blue900,
                        padding: pw.EdgeInsets.all(4), // Reducido de 8
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('TOTAL', 
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8)),
                            pw.Text(formatCurrency(total), 
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          ];
        },
      ),
    );
    
    return pdf.save();
  } catch (e) {
    print("Error al generar PDF mejorado: $e");
    return null;
  }
}

String formatearPorcentaje(dynamic valor) {
  if (valor == null) return '0%';
  
  double porcentaje;
  if (valor is num) {
    porcentaje = valor.toDouble();
  } else {
    try {
      porcentaje = double.parse(valor.toString().replaceAll('%', '').trim());
    } catch (e) {
      return '0%';
    }
  }
  
  // Verificar si es entero
  if (porcentaje == porcentaje.roundToDouble()) {
    // Si es entero, mostrar sin decimales
    return '${porcentaje.toInt()}%';
  } else {
    // Si tiene decimales, mostrar con un decimal
    return '${porcentaje.toStringAsFixed(1)}%';
  }
}


  pw.Widget _buildPDFHeaderCell(String text) {
  return pw.Padding(
    padding: pw.EdgeInsets.all(2), // Reducir padding
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 7, // Reducir tamaño de fuente
      ),
      textAlign: pw.TextAlign.center,
    ),
  );
}
pw.Widget _buildPDFDataCell(String text, {pw.TextStyle? style, int? columnIndex}) {
  // Definir alineación basada en el índice de columna
  pw.TextAlign alignment;
  
  switch (columnIndex) {
    case 5: // DESCRIPCIÓN
    case 6: // VEHÍCULO
      alignment = pw.TextAlign.left; // Solo estas columnas van alineadas a la izquierda
      break;
    default:
      alignment = pw.TextAlign.center; // TODO lo demás centrado (incluye VALORES MONETARIOS)
      break;
  }
  
  // Determinar si es texto que puede requerir múltiples líneas
  bool needsMultiLine = (columnIndex == 5 || columnIndex == 6);
  
  return pw.Padding(
    padding: pw.EdgeInsets.all(1),
    child: pw.Text(
      text,
      style: style ?? pw.TextStyle(fontSize: 6),
      textAlign: alignment,
      maxLines: needsMultiLine ? null : 1,
      overflow: needsMultiLine ? pw.TextOverflow.visible : pw.TextOverflow.clip,
    ),
  );
}

  void calcularTotales() {
  double vBruto = 0;
  double dscto = 0;
  
  for (var producto in productosAgregados) {
    // Asegurarse que los valores sean numéricos
    double precio = 0;
    if (producto['VLR ANTES DE IVA'] is num) {
      precio = producto['VLR ANTES DE IVA'];
    } else {
      precio = double.tryParse(producto['VLR ANTES DE IVA'].toString()) ?? 0;
    }
    
    double porcentajeDescuento = 0;
    if (producto['DSCTO'] is num) {
      porcentajeDescuento = producto['DSCTO'];
    } else {
      porcentajeDescuento = double.tryParse(producto['DSCTO'].toString()) ?? 0;
    }
    
    int cantidad = 0;
    if (producto['CANT'] is int) {
      cantidad = producto['CANT'];
    } else {
      cantidad = int.tryParse(producto['CANT'].toString()) ?? 0;
    }
    
    // Precio total: precio unitario * cantidad
    double precioTotal = precio * cantidad;
    
    // En lugar de calcular el valor bruto con descuento, usamos directamente el precio total
    vBruto += precioTotal;
    
    // Calculamos el descuento por separado para los totales
    double descuentoMonto = precioTotal * (porcentajeDescuento / 100);
    dscto += descuentoMonto;
  }
  
  setState(() {
    valorBrutoTotal = vBruto;
    descuentoTotal = dscto;
    subtotal = vBruto - dscto;
    iva = subtotal * 0.19; // 19% IVA
    total = subtotal + iva;
  });
}
  
  // Método para seleccionar un producto de la tabla
  void seleccionarProducto(Map<String, dynamic> producto) {
  final codigo = producto['CODIGO']?.toString() ?? '';
  final numero = producto['#']?.toString() ?? '';
  
  print("Seleccionando producto #$numero - código: $codigo");
  
  setState(() {
    productoCodigoSeleccionado = codigo;
    productoNumeroSeleccionado = numero; // Agregar esta variable de clase si no existe
    
    // Verificar si la imagen existe cuando seleccionamos un producto
    _checkImageExistence(codigo);
  });
}
  
  // Verificar si la imagen existe y cachear el resultado
  Future<void> _checkImageExistence(String codigo) async {
  if (_imagenesDisponibles.containsKey(codigo)) {
    return; // Ya verificamos esta imagen
  }
  
  try {
    // Construir la URL de la imagen en el servidor
    // Ajusta esta URL base según la estructura de tu servidor Render
    final imageUrl = '${ProductoService.baseUrl}/api/productos/imagenes/$codigo.jpg';
    
    // Intentar verificar si la imagen existe mediante una solicitud HEAD
    final response = await http.head(Uri.parse(imageUrl)).timeout(
      Duration(seconds: 5),
      onTimeout: () => http.Response('Timeout', 408),
    );
    
    // Si la respuesta es exitosa (código 200), la imagen existe
    if (response.statusCode == 200) {
      _imagenesDisponibles[codigo] = true;
      print("Imagen encontrada en servidor: $imageUrl");
    } else {
      // Intentar con variaciones del nombre
      final urlUpper = '${ProductoService.baseUrl}/api/productos/imagenes/${codigo.toUpperCase()}.jpg';
      final responseBkp = await http.head(Uri.parse(urlUpper)).timeout(
        Duration(seconds: 3),
        onTimeout: () => http.Response('Timeout', 408),
      );
      
      if (responseBkp.statusCode == 200) {
        _imagenesDisponibles[codigo] = true;
        print("Imagen encontrada en servidor (versión mayúscula): $urlUpper");
      } else {
        _imagenesDisponibles[codigo] = false;
        print("Imagen no encontrada para $codigo");
      }
    }
  } catch (e) {
    print("Error al verificar imagen para $codigo: $e");
    _imagenesDisponibles[codigo] = false;
  }
  
  // Forzar reconstrucción del widget para mostrar la imagen o el placeholder
  if (mounted) {
    setState(() {});
  }
}
  
  // Método para mostrar la vista previa
  void mostrarVistaPrevia() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Solo un botón para cerrar sin AppBar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              // Contenido de la vista previa (scrollable)
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: RepaintBoundary(
                    key: _vistaPreviewKey,
                    child: Container(
                      color: Colors.white,
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Encabezado
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Logo
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Image.asset(
                                    'assets/images/logo.png',
                                    width: 120,
                                    height: 60,
                                    fit: BoxFit.contain,
                                  ),
                                  SizedBox(height: 5),
                                  Text('Distribuciones Autoparts S.A.S'),
                                  Text('Nit: 901.110.424-1', style: TextStyle(decoration: TextDecoration.underline)),
                                ],
                              ),
                              Spacer(),
                              // Información de la orden
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('FECHA: ${obtenerFechaActual()}', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('ORDEN DE PEDIDO #: ${numeroOrdenActual}', style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(height: 10),
                                ],
                              ),
                            ],
                          ),
                          
                          SizedBox(height: 20),
                          
                          // Tablas de cliente y asesor lado a lado
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Información del cliente
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                        color: Color(0xFF1A4379),
                                        width: double.infinity,
                                        child: Text(
                                          'INFORMACIÓN DEL CLIENTE',
                                          style: TextStyle(
                                            color: Colors.white, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildCompactInfoRow('NIT:', widget.clienteData['NIT CLIENTE'] ?? ''),
                                            _buildCompactInfoRow('NOMBRE:', widget.clienteData['NOMBRE'] ?? ''),
                                            _buildCompactInfoRow('ESTABLECIMIENTO:', widget.clienteData['ESTABLECIMIENTO'] ?? ''),
                                            _buildCompactInfoRow('DIRECCIÓN:', widget.clienteData['DIRECCION'] ?? ''),
                                            _buildCompactInfoRow('TELÉFONO:', widget.clienteData['TELEFONO'] ?? ''),
                                            _buildCompactInfoRow('DESCUENTO:', widget.clienteData['DESCTO'] ?? ''),
                                            _buildCompactInfoRow('CIUDAD:', widget.clienteData['CLI_CIUDAD'] ?? ''),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              // Información del asesor
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                        color: Color(0xFF1A4379),
                                        width: double.infinity,
                                        child: Text(
                                          'INFORMACIÓN DEL ASESOR',
                                          style: TextStyle(
                                            color: Colors.white, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildCompactInfoRow('ID:', widget.asesorData['ID'] ?? ''),
                                            _buildCompactInfoRow('NOMBRE:', widget.asesorData['NOMBRE'] ?? ''),
                                            _buildCompactInfoRow('ZONA:', widget.asesorData['ZONA'] ?? ''),
                                            _buildCompactInfoRow('TELÉFONO:', widget.asesorData['CEL'] ?? ''),
                                            _buildCompactInfoRow('CORREO:', widget.asesorData['MAIL'] ?? ''),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          SizedBox(height: 20),
                          
                          // Encabezado de Productos
                          Container(
                            width: double.infinity,
                            color: Color(0xFF1A4379),
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            child: Text(
                              'PRODUCTOS',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),

                          // Tabla de productos mejorada con columnas fijas y formato similar al PDF
                          Container(
  width: double.infinity,
  decoration: BoxDecoration(
    border: Border.all(color: Colors.grey.shade300),
  ),
  child: Column(
    children: [
      // Tabla header
      Table(
  border: TableBorder.all(color: const Color(0xFF1A4379)),
  columnWidths: const {
    0: FixedColumnWidth(35),    // #
    1: FixedColumnWidth(50),    // CÓDIGO
    2: FixedColumnWidth(30),    // UB
    3: FixedColumnWidth(60),    // REF - aumentado
    4: FixedColumnWidth(45),    // ORIGEN
    5: FlexColumnWidth(3.5),    // DESCRIPCIÓN
    6: FlexColumnWidth(3.0),    // VEHÍCULO
    7: FixedColumnWidth(45),    // MARCA
    8: FixedColumnWidth(60),    // V. ANTES IVA
    9: FixedColumnWidth(40),    // DSCTO
    10: FixedColumnWidth(30),   // CANT
    11: FixedColumnWidth(60),   // V.BRUTO
  }, 
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: const Color(0xFF1A4379),
            ),
            children: [
              _buildPreviewHeaderCell('#'),
              _buildPreviewHeaderCell('CÓDIGO'),
              _buildPreviewHeaderCell('UB'),
              _buildPreviewHeaderCell('REF'),
              _buildPreviewHeaderCell('ORIGEN'),
              _buildPreviewHeaderCell('DESCRIPCIÓN'),
              _buildPreviewHeaderCell('VEHÍCULO'),
              _buildPreviewHeaderCell('MARCA'),
              _buildPreviewHeaderCell('V. ANTES IVA'),
              _buildPreviewHeaderCell('DSCTO'),
              _buildPreviewHeaderCell('CANT'),
              _buildPreviewHeaderCell('V.BRUTO'),
            ],
          ),
        ],
      ),
      
      // Tabla body con scroll vertical
      Container(
        height: 250, // Altura fija para área scrollable
        child: SingleChildScrollView(
          child: Table(
  border: TableBorder.all(color: Colors.grey.shade300),
  columnWidths: const {
    0: FixedColumnWidth(35),    // # - AMPLIADO para mostrar números largos
    1: FixedColumnWidth(50),    // CÓDIGO
    2: FixedColumnWidth(30),    // UB
    3: FixedColumnWidth(55),    // REF
    4: FixedColumnWidth(45),    // ORIGEN
    5: FlexColumnWidth(3.5),    // DESCRIPCIÓN
    6: FlexColumnWidth(3.0),    // VEHÍCULO
    7: FixedColumnWidth(45),    // MARCA
    8: FixedColumnWidth(60),    // V. ANTES IVA
    9: FixedColumnWidth(40),    // DSCTO
    10: FixedColumnWidth(30),   // CANT
    11: FixedColumnWidth(60),   // V.BRUTO
  },
            children: productosAgregados.map((producto) {
              return TableRow(
                children: [
                  _buildPreviewDataCell(producto['#']?.toString() ?? '', columnIndex: 0),
                  _buildPreviewDataCell(producto['CODIGO']?.toString() ?? '', columnIndex: 1),
                  _buildPreviewDataCell(producto['UB']?.toString() ?? '', columnIndex: 2),
                  _buildPreviewDataCell(producto['REF']?.toString() ?? '', columnIndex: 3),
                  _buildPreviewDataCell(producto['ORIGEN']?.toString() ?? '', columnIndex: 4),
                  _buildPreviewDataCell(producto['DESCRIPCION']?.toString() ?? '', columnIndex: 5, maxLines: 3),
                  _buildPreviewDataCell(producto['VEHICULO']?.toString() ?? '', columnIndex: 6, maxLines: 3),
                  _buildPreviewDataCell(producto['MARCA']?.toString() ?? '', columnIndex: 7),
                  _buildPreviewDataCell(_formatMoneda(producto['VLR ANTES DE IVA']), columnIndex: 8),
                  _buildPreviewDataCell(formatearPorcentaje(producto['DSCTO']), columnIndex: 9),
                  _buildPreviewDataCell(producto['CANT']?.toString() ?? '', columnIndex: 10),
                  _buildPreviewDataCell(_formatMoneda(producto['V.BRUTO']), columnIndex: 11),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ],
  ),
),
                          
                          SizedBox(height: 20),
                          
                          // Observaciones y totales
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Observaciones
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCFD5E1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('OBSERVACIONES:', 
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                                      const SizedBox(height: 2), 
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(color: Colors.grey.shade400, width: 0.5),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            observacionesController.text.isEmpty ? 
                                                'Sin observaciones' : observacionesController.text,
                                            style: TextStyle(fontSize: 10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),    
                              SizedBox(width: 20),
                              
                              // Totales
                              Expanded(
                                flex: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildTotalRow('V.BRUTO', formatCurrency(valorBrutoTotal)),
                                      _buildTotalRow('DSCTO', formatCurrency(descuentoTotal)),
                                      _buildTotalRow('SUBTOTAL', formatCurrency(subtotal)),
                                      _buildTotalRow('IVA', formatCurrency(iva)),
                                      Container(
                                        color: Color(0xFF1A4379),
                                        padding: EdgeInsets.all(8),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                            Text(formatCurrency(total), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
// Función para construir la tabla principal de productos
Widget _buildProductsTable() {
  return Container(
    width: MediaQuery.of(context).size.width,
    child: Column(
      children: [
        // Encabezado de la tabla
        Table(
          border: TableBorder.all(color: const Color(0xFF1A4379)),
          columnWidths: const {
            0: FixedColumnWidth(35),    // #
            1: FixedColumnWidth(50),    // CÓDIGO
            2: FixedColumnWidth(30),    // UB - sin cambios
            3: FixedColumnWidth(60),    // REF - aumentado para mostrar más texto
            4: FixedColumnWidth(45),    // ORIGEN
            5: FlexColumnWidth(3.5),    // DESCRIPCIÓN
            6: FlexColumnWidth(3.0),    // VEHÍCULO
            7: FixedColumnWidth(45),    // MARCA
            8: FixedColumnWidth(60),    // V. ANTES IVA
            9: FixedColumnWidth(40),    // DSCTO
            10: FixedColumnWidth(30),   // CANT
            11: FixedColumnWidth(60),   // V.BRUTO
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: const Color(0xFF1A4379),
              ),
              children: [
                _buildHeaderCell('#'),
                _buildHeaderCell('CÓDIGO'),
                _buildHeaderCell('UB'),
                _buildHeaderCell('REF'),
                _buildHeaderCell('ORIGEN'),
                _buildHeaderCell('DESCRIPCIÓN'),
                _buildHeaderCell('VEHÍCULO'),
                _buildHeaderCell('MARCA'),
                _buildHeaderCell('V. ANTES IVA'),
                _buildHeaderCell('DSCTO'),
                _buildHeaderCell('CANT'),
                _buildHeaderCell('V.BRUTO'),
              ],
            ),
          ],
        ),
        
        // Cuerpo de la tabla con scroll
        Container(
          constraints: BoxConstraints(
            minHeight: 100,
            maxHeight: MediaQuery.of(context).size.height * 0.33,
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {
                0: FixedColumnWidth(35),    // #
                1: FixedColumnWidth(50),    // CÓDIGO
                2: FixedColumnWidth(30),    // UB
                3: FixedColumnWidth(60),    // REF - aumentado
                4: FixedColumnWidth(45),    // ORIGEN
                5: FlexColumnWidth(3.5),    // DESCRIPCIÓN
                6: FlexColumnWidth(3.0),    // VEHÍCULO
                7: FixedColumnWidth(45),    // MARCA
                8: FixedColumnWidth(60),    // V. ANTES IVA
                9: FixedColumnWidth(40),    // DSCTO
                10: FixedColumnWidth(30),   // CANT
                11: FixedColumnWidth(60),   // V.BRUTO
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: productosAgregados.map((producto) {
                bool isSelected = producto['CODIGO'] == productoCodigoSeleccionado;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  ),
                  children: [
                    _buildDataCell(producto['#']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['CODIGO']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['UB']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['REF']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['ORIGEN']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['DESCRIPCION']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['VEHICULO']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(producto['MARCA']?.toString() ?? '', producto: producto, enforceFull: true),
                    _buildDataCell(_formatMoneda(producto['VLR ANTES DE IVA']), producto: producto),
                    _buildDataCell(formatearPorcentaje(producto['DSCTO']), producto: producto),
                    _buildDataCell(producto['CANT']?.toString() ?? '', producto: producto),
                    _buildDataCell(_formatMoneda(producto['V.BRUTO']), producto: producto),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildPreviewHeaderCell(String text) {
  return Container(
    padding: EdgeInsets.all(2),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 7, // Reducido para mejor ajuste
      ),
      textAlign: TextAlign.center,
    ),
  );
}
Widget _buildPreviewDataCell(String text, {int columnIndex = 0, int? maxLines}) {
  // Definir alineación basada en el índice de columna
  TextAlign alignment;
  
  switch (columnIndex) {
    case 5: // DESCRIPCIÓN
    case 6: // VEHÍCULO
      alignment = TextAlign.left;
      break;
    case 8: // V. ANTES IVA
    case 11: // V.BRUTO
      alignment = TextAlign.right;
      break;
    default:
      alignment = TextAlign.center;
      break;
  }
  
  return Container(
    padding: EdgeInsets.all(2),
    child: Text(
      text,
      style: TextStyle(fontSize: 7), // Reducido para evitar truncamiento
      textAlign: alignment,
      maxLines: null, // Sin límite de líneas
      overflow: TextOverflow.visible, // Mostrar todo el texto
      softWrap: true, // Permitir wrap para ajustar el texto
    ),
  );
}

 Future<void> _enviarCorreoPorServidor() async {
    setState(() {
      isLoading = true;
    });

    try {
      // IMPORTANTE: Primero confirmar el número de orden para incrementar el contador
      // ANTES de cualquier operación de envío
      print("Confirmando número de orden ${numeroOrdenActual} antes del envío...");
      try {
        final confirmarResponse = await http.post(
          Uri.parse('${ProductoService.baseUrl}/confirmar-orden'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'numeroOrden': numeroOrdenActual,
          }),
        ).timeout(
          Duration(seconds: 10),
          onTimeout: () => throw Exception('Tiempo de espera agotado al confirmar número'),
        );
        
        if (confirmarResponse.statusCode == 200) {
          final data = json.decode(confirmarResponse.body);
          if (data['success']) {
            print("✅ Número de orden confirmado e incrementado correctamente");
          } else {
            print("⚠️ Error al confirmar número: ${data['message']}");
            // Continuar a pesar del error, no bloquear proceso
          }
        } else {
          print("⚠️ Error HTTP al confirmar número: ${confirmarResponse.statusCode}");
        }
      } catch (e) {
        print("⚠️ Excepción al confirmar número: $e");
        // Continuar a pesar del error, no bloquear proceso
      }

      // Verificar conectividad con un ping rápido
      try {
        final pingResponse = await http.get(
          Uri.parse('${ProductoService.baseUrl}/ping'),
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
      
      print("Generando PDF...");
      final pdf = await _generarPDFMejorado();
      print("PDF generado correctamente: ${pdf?.length ?? 0} bytes");
      
      if (pdf == null) {
        throw Exception("No se pudo generar el PDF");
      }
      
      // Guardar PDF en almacenamiento temporal
      final dir = await getTemporaryDirectory();
      final fileName = 'orden_${numeroOrdenActual}.pdf';
      final pdfFile = File('${dir.path}/$fileName');
      await pdfFile.writeAsBytes(pdf);
      
      // Buscar el correo del cliente
      String emailCliente = '';
      
      // Buscar en todas las posibles claves
      final posiblesClaves = ['CLI_EMAIL', 'EMAIL', 'CORREO', 'MAIL'];
      for (var clave in posiblesClaves) {
        if (widget.clienteData.containsKey(clave) && 
            widget.clienteData[clave]!.isNotEmpty) {
          emailCliente = widget.clienteData[clave]!;
          break;
        }
      }
      
      // Si no se encuentra, solicitar manualmente
      if (emailCliente.isEmpty) {
        final TextEditingController emailController = TextEditingController();
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: Text('Correo electrónico'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Por favor ingrese el correo del cliente:'),
                  SizedBox(height: 10),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'correo@ejemplo.com',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Aceptar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1A4379),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
        
        emailCliente = emailController.text.trim();
        if (emailCliente.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se proporcionó un correo electrónico')),
          );
          setState(() {
            isLoading = false;
          });
          return;
        }
      }
      
      // Crear solicitud al servidor
      print("Preparando solicitud al servidor...");
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ProductoService.baseUrl}/send-email'),    
      );
      
      final nombreCliente = widget.clienteData['NOMBRE'] ?? '';
      // Agregar los campos
      request.fields['clienteEmail'] = emailCliente;
      request.fields['asesorEmail'] = widget.asesorData['MAIL'] ?? '';
      request.fields['clienteNombre'] = nombreCliente; // Nombre del cliente
      request.fields['ordenNumero'] = numeroOrdenActual; // Número de orden actualizado
      
      // Formato original del asunto (el servidor lo reformateará)
      request.fields['cuerpo'] = '''Cordial saludo.

Se adjunta orden de pedido #${numeroOrdenActual} del cliente ${nombreCliente}.

Por su colaboración mil gracias.

Cordialmente,

${widget.asesorData['NOMBRE'] ?? 'Su asesor'}
Asesor comercial 
Distribuciones AutoPart's SAS
''';
      
      // Agregar el archivo PDF
      print("Adjuntando archivo PDF...");
      request.files.add(
        await http.MultipartFile.fromPath(
          'pdf',
          pdfFile.path,
          filename: fileName,
        ),
      );
      
      // Enviar la solicitud
      print("Enviando solicitud al servidor...");
      final streamedResponse = await request.send().timeout(
        Duration(seconds: 30),
        onTimeout: () => throw Exception('Tiempo de espera agotado al enviar el correo. Verifique su conexión.'),
      );
      
      print("Respuesta del servidor recibida: ${streamedResponse.statusCode}");
      final response = await http.Response.fromStream(streamedResponse);
      print("Cuerpo de la respuesta: ${response.body}");
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        if (jsonResponse['success']) {
          // Ya no necesitamos llamar a confirmar-orden aquí, porque lo hicimos al inicio
          
          // NUEVO: Solicitar el siguiente número para actualizar localmente
          try {
            final nextNumResponse = await http.get(
              Uri.parse('${ProductoService.baseUrl}/siguiente-orden'),
            ).timeout(
              Duration(seconds: 5),
              onTimeout: () => throw Exception('Tiempo de espera agotado'),
            );
            
            if (nextNumResponse.statusCode == 200) {
              final nextNumData = json.decode(nextNumResponse.body);
              if (nextNumData['success'] && nextNumData.containsKey('numeroOrden')) {
                // Guardar este nuevo número en SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('ultimo_numero_orden', nextNumData['numeroOrden']);
                print("Nuevo número de orden guardado localmente: ${nextNumData['numeroOrden']}");
              }
            }
          } catch (e) {
            print("Error al obtener siguiente número de orden: $e");
            // No detener el flujo por este error
          }
          
          // Obtener listas de destinatarios (a las que el servidor envió el correo)
          List<String> destinatariosPrincipales = [];
          List<String> destinatariosCC = [];

          if (jsonResponse.containsKey('destinatarios') && jsonResponse['destinatarios'] != null) {
            // Si el servidor devuelve esta información como lista
            try {
              destinatariosPrincipales = List<String>.from(jsonResponse['destinatarios']);
              print("Destinatarios principales recibidos del servidor: $destinatariosPrincipales");
            } catch (e) {
              print("Error al procesar destinatarios principales: $e");
              // En caso de error, usar al menos el correo del asesor
              if (widget.asesorData['MAIL'] != null && widget.asesorData['MAIL']!.isNotEmpty) {
                destinatariosPrincipales.add(widget.asesorData['MAIL']!);
              }
            }
          } else {
            // Si el servidor no proporciona esta información
            print("No se recibieron destinatarios principales del servidor");
            // Incluir al menos el correo del asesor como destinatario principal
            if (widget.asesorData['MAIL'] != null && widget.asesorData['MAIL']!.isNotEmpty) {
              destinatariosPrincipales.add(widget.asesorData['MAIL']!);
            }
          }

          if (jsonResponse.containsKey('cc') && jsonResponse['cc'] != null) {
            // Si el servidor devuelve esta información como lista
            try {
              destinatariosCC = List<String>.from(jsonResponse['cc']);
              print("Destinatarios CC recibidos del servidor: $destinatariosCC");
            } catch (e) {
              print("Error al procesar destinatarios CC: $e");
              // En caso de error, usar al menos el correo del cliente
              if (emailCliente.isNotEmpty) {
                destinatariosCC.add(emailCliente);
              }
            }
          } else {
            // Si el servidor no proporciona esta información
            print("No se recibieron destinatarios CC del servidor");
            // Incluir el correo del cliente en copia
            if (emailCliente.isNotEmpty) {
              destinatariosCC.add(emailCliente);
            }
          }

          // Imprimir diagnóstico
          print("Total destinatarios principales a mostrar: ${destinatariosPrincipales.length}");
          print("Total destinatarios CC a mostrar: ${destinatariosCC.length}");
          
          // Mostrar diálogo de éxito mejorado
          showDialog(
            context: context,
            barrierDismissible: false, // No permitir cerrar tocando fuera
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Correo enviado'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Icon(Icons.check_circle, color: Colors.green, size: 48),
                      ),
                      SizedBox(height: 16),
                      Center(
                        child: Text('La orden ha sido enviada correctamente'),
                      ),
                      SizedBox(height: 16),
                      
                      // Sección de destinatarios principales
                      if (destinatariosPrincipales.isNotEmpty) ...[
                        Text('Destinatarios principales:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: destinatariosPrincipales.map((email) => 
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 2),
                                child: Text(email),
                              )
                            ).toList(),
                          ),
                        ),
                        SizedBox(height: 12),
                      ],
                      
                      // Sección de destinatarios en copia (CC)
                      if (destinatariosCC.isNotEmpty) ...[
                        Text('Con copia a:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: destinatariosCC.map((email) => 
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 2),
                                child: Text(email),
                              )
                            ).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: Text('Aceptar'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      
                      // CAMBIO PRINCIPAL: Después de cerrar el diálogo, volver a la pantalla principal
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ],
              );
            },
          );
        } else {
          throw Exception("Error del servidor: ${jsonResponse['message']}");
        }
      } else if (response.statusCode == 409) {
        // Código especial para número duplicado
        try {
          final jsonResponse = json.decode(response.body);
          final nuevoNumero = jsonResponse['nuevoNumero'];
          
          // MODIFICACIÓN: Guardar el nuevo número en vez de perderlo
          showDialog(
  context: context,
  barrierDismissible: false,
  builder: (BuildContext context) {
    // Obtener el tamaño de la pantalla para hacer el diálogo adaptable
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 400;
    
    return AlertDialog(
      // Reducir el padding general para pantallas pequeñas
      contentPadding: isSmallScreen 
        ? EdgeInsets.fromLTRB(16, 16, 16, 0)  // Padding reducido para móviles
        : EdgeInsets.fromLTRB(24, 20, 24, 0), // Padding normal
      
      title: Text(
        'Número de orden duplicado',
        style: TextStyle(
          fontSize: isSmallScreen ? 18 : 20, // Reducir tamaño del título
        ),
      ),
      
      content: SingleChildScrollView( // Usar SingleChildScrollView para permitir scroll
        child: Container(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Importante para que se adapte al contenido
            children: [
              Icon(Icons.warning, color: Colors.orange, size: isSmallScreen ? 40 : 48),
              SizedBox(height: 12), // Reducido de 16 a 12 para móviles
              
              Text(
                'El número de orden ${numeroOrdenActual} ya ha sido utilizado.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
              ),
              
              Text(
                'Se ha generado un nuevo número: $nuevoNumero',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
              ),
              
              SizedBox(height: 12), // Reducido de 16 a 12 para móviles
              
              Text(
                '¿Desea continuar con el nuevo número de orden?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
              ),
            ],
          ),
        ),
      ),
      
      // Botones en columna para pantallas pequeñas
      actions: [
        isSmallScreen
          // Para pantallas pequeñas, botones uno debajo del otro
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: Text('Cancelar', style: TextStyle(fontSize: 13)),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1A4379),
                    foregroundColor: Colors.white,
                    minimumSize: Size(double.infinity, 36), // Botón a ancho completo
                  ),
                  child: Text('Continuar con nuevo número', style: TextStyle(fontSize: 13)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      numeroOrdenActual = nuevoNumero;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Número de orden actualizado a: $nuevoNumero'))
                    );
                    _enviarCorreoPorServidor();
                  },
                ),
                SizedBox(height: 8), // Espacio inferior para compensar el padding reducido
              ],
            )
          // Para pantallas normales, botones uno al lado del otro
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  child: Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1A4379),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Continuar con nuevo número'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      numeroOrdenActual = nuevoNumero;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Número de orden actualizado a: $nuevoNumero'))
                    );
                    _enviarCorreoPorServidor();
                  },
                ),
              ],
            ),
      ],
      // Asegurar que el diálogo tenga borde redondeado
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  },
);
        } catch (e) {
          throw Exception("Error con número duplicado: ${response.body}");
        }
      } else {
        throw Exception("Error de conexión: ${response.statusCode}");
      }
    } catch (e) {
      print("Error detallado: ${e.toString()}");
      
      // Mensaje más informativo según el tipo de error
      String errorMsg = 'Error al enviar el correo: $e';
      
      if (e.toString().contains('internet') || 
          e.toString().contains('conectar') ||
          e.toString().contains('conexión') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
      } else if (e.toString().contains('timed out')) {
        errorMsg = 'No se pudo conectar al servidor (tiempo de espera agotado). Verifica que el servidor esté funcionando y que la IP sea correcta.';
      } else if (e.toString().contains('connection refused')) {
        errorMsg = 'Conexión rechazada. Verifica que el servidor esté funcionando en el puerto correcto.';
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
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }


@override
Widget build(BuildContext context) {
  return GestureDetector(
    // Al tocar en cualquier parte de la pantalla, ocultar el teclado
    onTap: _ocultarTeclado,
    // Necesario para que el detector capte gestos en áreas "vacías"
    behavior: HitTestBehavior.opaque,
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Productos a Solicitar', style: TextStyle(color: Colors.white),),
        backgroundColor: const Color(0xFF1A4379),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo animado para carga
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _animationController.value * 2 * 3.14159,
                      child: Container(
                        width: 80,
                        height: 80,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue[900]!, width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('DAP', style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('Auto', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text('Cargando...', style: TextStyle(fontSize: 16)),
              ],
            ),
          )
        : errorMessage.isNotEmpty 
          ? Center(child: Text('Error: $errorMessage', style: const TextStyle(color: Colors.red)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado: información cliente y opciones - Versión reducida
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Información cliente (reducida en un 20%)
                      Expanded(
                        flex: 2,
                        child: Container(
                          // Reducir altura con un transform scale de manera más moderada
                          transform: Matrix4.diagonal3Values(1.0, 0.8, 1.0), // Reducción del 20% en altura
                          transformAlignment: Alignment.topLeft, // Alinear desde la esquina superior izquierda
                          child: Table(
                            border: TableBorder.all(color: Colors.white),
                            columnWidths: const {
                              0: FlexColumnWidth(1.5),
                              1: FlexColumnWidth(3),
                            },
                            children: [
                              _buildInfoRow2Balanced('NIT CLIENTE', widget.clienteData['NIT CLIENTE'] ?? '', isHeader: true),
                              _buildInfoRow2Balanced('NOMBRE', widget.clienteData['NOMBRE'] ?? ''),
                              _buildInfoRow2Balanced('ESTABLECIMIENTO', widget.clienteData['ESTABLECIMIENTO'] ?? ''),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Información orden y opciones
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FECHA: ${obtenerFechaActual()}', 
                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            Text('ORDEN DE PEDIDO #: ${numeroOrdenActual}', 
                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 10),

                            // Radio buttons con tamaño moderado
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Radio button NORMAL
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Radio<TipoPedido>(
                                        value: TipoPedido.normal,
                                        groupValue: tipoPedidoSeleccionado,
                                        onChanged: (TipoPedido? value) {
                                          setState(() {
                                            tipoPedidoSeleccionado = value!;
                                            isNormal = true;
                                            isCondicionado = false;
                                            isContado = false;
                                            actualizarDescuentosSegunModo();
                                          });
                                        },
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text('NORMAL', style: TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                  // Radio button CONDICIONADO
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Radio<TipoPedido>(
                                        value: TipoPedido.condicionado,
                                        groupValue: tipoPedidoSeleccionado,
                                        onChanged: (TipoPedido? value) {
                                          setState(() {
                                            tipoPedidoSeleccionado = value!;
                                            isNormal = false;
                                            isCondicionado = true;
                                            isContado = false;
                                            actualizarDescuentosSegunModo();
                                          });
                                        },
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text('COND.', style: TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                  // NUEVO Radio button CONTADO
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Radio<TipoPedido>(
                                        value: TipoPedido.contado,
                                        groupValue: tipoPedidoSeleccionado,
                                        onChanged: (TipoPedido? value) {
                                          setState(() {
                                            tipoPedidoSeleccionado = value!;
                                            isNormal = false;
                                            isCondicionado = false;
                                            isContado = true;
                                            actualizarDescuentosSegunModo();
                                          });
                                        },
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text('CONT.', style: TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Buscador de productos
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: numeroController,
                          decoration: const InputDecoration(
                            labelText: '# Producto',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: cantidadController,
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: buscarProductoPorNumero,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A4379),
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                        ),
                        child: const Text('Agregar', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Tabla de productos
                  _buildProductsTable(),
                  
                  // AÑADIDO: Espacio adicional entre tabla y sección de observaciones
                  const SizedBox(height: 16),
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Imagen del producto
                      Container(
                        width: 110,
                        height: 90,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _buildImagenProducto(),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Observaciones
                      Expanded(
                        flex: 3,
                        child: GestureDetector(
                          onTap: _ocultarTeclado,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            height: 90,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCFD5E1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('OBSERVACIONES:', 
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                                const SizedBox(height: 2), 
                                Expanded(
                                  child: TextField(
                                    controller: observacionesController,
                                    focusNode: observacionesFocusNode,
                                    maxLines: null,
                                    expands: true,
                                    style: TextStyle(fontSize: 10),
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: const InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.all(4),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(4)),
                                        borderSide: BorderSide(width: 0.5),
                                      ),
                                      isDense: true,
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Totales
                      Container(
                        width: 150,
                        child: Table(
                          border: TableBorder.all(width: 0.5),
                          columnWidths: const {
                            0: FlexColumnWidth(1),
                            1: FlexColumnWidth(1),
                          },
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            _buildTotalRowLarge('V.BRUTO', formatCurrency(valorBrutoTotal)),
                            _buildTotalRowLarge('DSCTO', formatCurrency(descuentoTotal)),
                            _buildTotalRowLarge('SUBTOTAL', formatCurrency(subtotal)),
                            _buildTotalRowLarge('IVA', formatCurrency(iva)),
                            _buildTotalRowLarge('TOTAL', formatCurrency(total), isTotal: true),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // MODIFICADO: Reducido drásticamente el espacio entre observaciones y botones de acción
                  const SizedBox(height: 2),
                  
                  // Botones de Editar y Eliminar, centrados
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Botón Editar
                        ElevatedButton.icon(
                          onPressed: productoCodigoSeleccionado != null ? 
                            () {
                              // Buscar el producto seleccionado
                              final producto = productosAgregados.firstWhere(
                                (p) => p['CODIGO'] == productoCodigoSeleccionado,
                                orElse: () => <String, dynamic>{},
                              );
                              if (producto.isNotEmpty) {
                                _editarCantidad(producto);
                              }
                            } : null,
                          icon: Icon(Icons.edit, color: Colors.white),
                          label: Text('Editar', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 20),
                        
                        // Botón Eliminar
                        ElevatedButton.icon(
                          onPressed: productoCodigoSeleccionado != null ? 
                            () {
                              // Buscar el producto seleccionado
                              final producto = productosAgregados.firstWhere(
                                (p) => p['CODIGO'] == productoCodigoSeleccionado,
                                orElse: () => <String, dynamic>{},
                              );
                              if (producto.isNotEmpty) {
                                _eliminarProducto(producto);
                              }
                            } : null,
                          icon: Icon(Icons.delete, color: Colors.white),
                          label: Text('Eliminar', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // MODIFICADO: Reducido el espacio entre botones de acción y botones principales
                  const SizedBox(height: 5),
                  
                  // Botones principales
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Botón Vista Previa
                        ElevatedButton(
                          onPressed: () {
                            mostrarVistaPrevia();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF1A4379),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.grey),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                          ),
                          child: const Text('VISTA PREVIA'),
                        ),
                        SizedBox(width: 20),
                        // Botón Enviar
                        ElevatedButton(
                          onPressed: () {
                            _enviarCorreoPorServidor();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.grey),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                          ),
                          child: const Text('ENVIAR'),
                        ),  
                        SizedBox(width: 20),
                        // Botón Cancelar Orden
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.grey),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                          ),
                          child: const Text('CANCELAR ORDEN'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildBotonesAccion() {
  // Solo mostrar botones si hay un producto seleccionado
  if (productoCodigoSeleccionado == null) {
    return SizedBox.shrink(); // Widget vacío
  }
  
  // Buscar el producto seleccionado en la lista
  final productoSeleccionado = productosAgregados.firstWhere(
    (p) => p['CODIGO'] == productoCodigoSeleccionado,
    orElse: () => <String, dynamic>{},
  );
  
  if (productoSeleccionado.isEmpty) {
    return SizedBox.shrink(); // Widget vacío
  }
  
  // Construir los botones
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Botón de Editar
      ElevatedButton.icon(
        onPressed: () => _editarCantidad(productoSeleccionado),
        icon: Icon(Icons.edit, size: 18),
        label: Text('Editar'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      
      SizedBox(width: 15),
      
      // Botón de Eliminar
      ElevatedButton.icon(
        onPressed: () => _eliminarProducto(productoSeleccionado),
        icon: Icon(Icons.delete, size: 18),
        label: Text('Eliminar'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
    ],
  );
}
  
  // Widget para mostrar la imagen del producto
  // Modifica la función _buildImagenProducto en lib/productos_orden.dart
// para mejorar el diseño y eliminar el hueco alrededor de la imagen

Widget _buildImagenProducto() {
  if (productoCodigoSeleccionado == null) {
    // No hay producto seleccionado
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey.shade100,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.image, size: 40, color: Colors.grey),
            SizedBox(height: 4),
            Text(
              'Seleccione producto',
              style: TextStyle(color: Colors.grey, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  final codigo = productoCodigoSeleccionado!;
  final bool imagenDisponible = _imagenesDisponibles[codigo] ?? false;
  
  // Solo mostrar la imagen si está disponible
  if (imagenDisponible) {
    final imageUrl = '${ProductoService.baseUrl}/api/productos/imagenes/$codigo.jpg';
    
    return GestureDetector(
      onTap: () => _mostrarImagenGrande(codigo),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand, // Hacer que el Stack ocupe todo el espacio disponible
            children: [
              // Fondo blanco
              Container(color: Colors.white),
              
              // Indicador de carga
              Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue.shade200,
                ),
              ),
              
              // Imagen desde la red con ajuste para llenar el contenedor
              Image.network(
                imageUrl,
                fit: BoxFit.contain, // Ajusta la imagen para que se vea completa
                width: double.infinity, // Ocupa todo el ancho disponible
                height: double.infinity, // Ocupa todo el alto disponible
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / 
                            loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  print("Error al mostrar imagen: $error");
                  // Intentar con versión en mayúsculas
                  final urlUpper = '${ProductoService.baseUrl}/api/productos/imagenes/${codigo.toUpperCase()}.jpg';
                  return Image.network(
                    urlUpper,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      _imagenesDisponibles[codigo] = false;
                      setState(() {});
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, size: 30, color: Colors.red.shade300),
                            Text(
                              'Error',
                              style: TextStyle(color: Colors.red.shade300, fontSize: 9),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  } else {
    // No hay imagen disponible
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey.shade100,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.refresh, size: 30, color: Colors.blue),
              onPressed: () {
                // Recargar y volver a verificar la imagen
                _imagenesDisponibles.remove(codigo);
                _checkImageExistence(codigo);
              },
            ),
            const SizedBox(height: 4),
            Text(
              'No hay imagen\npara $codigo',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              'Toque para recargar',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blue, fontSize: 8),
            ),
          ],
        ),
      ),
    );
  }
}



void _eliminarProducto(Map<String, dynamic> producto) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de eliminar este producto?'),
        actions: [
          TextButton(
            child: Text('Cancelar'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Eliminar'),
            onPressed: () {
              setState(() {
                productosAgregados.removeWhere((p) => 
                  p['CODIGO'] == producto['CODIGO'] && 
                  p['#'] == producto['#']
                );
                // Recalcular totales después de eliminar
                calcularTotales();
                // Limpiar selección actual si era este producto
                if (productoCodigoSeleccionado == producto['CODIGO']) {
                  productoCodigoSeleccionado = null;
                }
              });
              Navigator.of(context).pop();
              // Mostrar confirmación
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Producto eliminado correctamente'))
              );
            },
          ),
        ],
      );
    },
  );
}


void  _editarCantidad(Map<String, dynamic> producto) {
  String cantidadActual = producto['CANT']?.toString() ?? '1';
  final TextEditingController cantController = TextEditingController(text: cantidadActual);
  
  // Abrir un diálogo simple para ingresar el número, pero con mejor manejo de espacio
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return SingleChildScrollView(
        child: AlertDialog(
          // Título más pequeño para ahorrar espacio
          title: Text('Editar Cantidad', style: TextStyle(fontSize: 18)),
          
          // Contenido con más espacio
          content: Container(
            width: 200, // Ancho mayor para evitar que se apriete el contenido
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Subtítulo para indicar el producto
                Text(
                  producto['DESCRIPCION'] ?? 'Producto',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 15),
                
                // Campo de texto con más espacio y mejor formato
                TextField(
                  controller: cantController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '0',
                    contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
          ),
          
          // Acciones en la parte inferior
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              child: Text('Guardar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF1A4379),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Cerrar primero el diálogo
                Navigator.of(dialogContext).pop();
                
                // Validar y actualizar después de cerrar el diálogo
                String nuevaCantidad = cantController.text.trim();
                if (nuevaCantidad.isNotEmpty) {
                  int? num = int.tryParse(nuevaCantidad);
                  if (num != null && num > 0) {
                    // Actualizar en el siguiente frame para evitar problemas de estado
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
  // Actualizar la cantidad
  producto['CANT'] = num;
  
  // Recalcular V.BRUTO basado en la nueva cantidad
  if (producto.containsKey('VLR ANTES DE IVA')) {
    double valorUnidad = 0;
    if (producto['VLR ANTES DE IVA'] is double || producto['VLR ANTES DE IVA'] is int) {
    valorUnidad = producto['VLR ANTES DE IVA'];
} else {
      valorUnidad = double.tryParse(producto['VLR ANTES DE IVA'].toString()) ?? 0;
    }
    
    // Actualizar V.BRUTO = Valor unitario * cantidad
    producto['V.BRUTO'] = valorUnidad * num;
    
    // Mostrar información de depuración en consola
    print("Recalculando V.BRUTO para ${producto['CODIGO']}:");
    print("  - Valor unitario: $valorUnidad");
    print("  - Nueva cantidad: $num");
    print("  - Nuevo V.BRUTO: ${producto['V.BRUTO']}");
  } else {
    print("ADVERTENCIA: No se encontró 'VLR ANTES DE IVA' para el producto");
  }
  
  // Recalcular todos los totales para la orden
  calcularTotales();
});
                      
                      // Mostrar mensaje de confirmación
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cantidad actualizada correctamente'))
                      );
                    });
                  } else {
                    // Mostrar mensaje de error si la cantidad no es válida
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Por favor ingrese una cantidad válida mayor a cero'))
                    );
                  }
                }
              },
            ),
          ],
          
          // Aplicar padding para ajustar con el teclado
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          
          // Forma redondeada para mejor apariencia
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    },
  );
}

  //funcion para aplicar descuentos según el modo seleccionado
 void actualizarDescuentosSegunModo() {
    if (productosAgregados.isEmpty) return;
    
    setState(() {
      for (var producto in productosAgregados) {
        // Aseguramos que cada producto tenga un descuento original guardado
        if (!producto.containsKey('DSCTO_ORIGINAL')) {
          producto['DSCTO_ORIGINAL'] = producto['DSCTO'];
        }
        
        if (isCondicionado) {
          // En modo CONDICIONADO, todos los descuentos se establecen en 0%
          producto['DSCTO'] = 0.0;
        } else if (isContado) {
          // En modo CONTADO, aumentamos el descuento en 2% solo si es 15% o 20%
          double descuentoOriginal = 0.0;
          if (producto['DSCTO_ORIGINAL'] is num) {
            descuentoOriginal = producto['DSCTO_ORIGINAL'];
          } else {
            descuentoOriginal = double.tryParse(producto['DSCTO_ORIGINAL'].toString()) ?? 0.0;
          }
          
          // Solo aumentar 2% si el descuento original es exactamente 15% o 20%
          if (descuentoOriginal == 15.0 || descuentoOriginal == 20.0) {
            producto['DSCTO'] = descuentoOriginal + 2.0;
          } else {
            producto['DSCTO'] = descuentoOriginal;
          }
        } else {
          // En modo NORMAL, recuperamos el descuento original
          producto['DSCTO'] = producto['DSCTO_ORIGINAL'];
        }
      }
      // Recalcular totales después de cambiar los descuentos
      calcularTotales();
    });
  }

  // Método para mostrar la imagen en tamaño grande
  void _mostrarImagenGrande(String codigo) {
  final imageUrl = '${ProductoService.baseUrl}/api/productos/imagenes/$codigo.jpg';
  
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.7,
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                spreadRadius: 5,
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand, // Ocupar todo el espacio disponible
            children: [
              // Fondo blanco interior
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(color: Colors.white),
              ),
              
              // Indicador de carga
              Center(child: CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 3,
              )),
              
              // Imagen con manejo mejorado de errores
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / 
                              loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // Intentar con versión en mayúsculas
                    final urlUpper = '${ProductoService.baseUrl}/api/productos/imagenes/${codigo.toUpperCase()}.jpg';
                    return Image.network(
                      urlUpper,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                'Error al cargar la imagen\n$codigo',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              
              // Botón para cerrar
              Positioned(
                right: 10,
                top: 10,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              
              // Información del producto
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Código: $codigo',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  // Formato para moneda
  // Reemplaza la función formatCurrency en la clase _ProductosOrdenState
String formatCurrency(dynamic value) {
  if (value == null) return '\$0';
  
  double numValue;
  if (value is num) {
    numValue = value.toDouble();
  } else {
    try {
      String cleanValue = value.toString()
          .replaceAll('\$', '')
          .replaceAll(',', '')
          .trim();
      numValue = double.tryParse(cleanValue) ?? 0;
    } catch (e) {
      numValue = 0;
    }
  }
  
  // Usar un formato más compacto sin decimales
  try {
    final formatter = NumberFormat('#,###', 'es_CO');
    return '\$${formatter.format(numValue)}';
  } catch (e) {
    // Formato simple en caso de error
    return '\$${numValue.toStringAsFixed(0)}';
  }
}




  // Widgets auxiliares
  TableRow _buildInfoRow2Balanced(String label, String value, {bool isHeader = false}) {
  return TableRow(
    decoration: BoxDecoration(
      color: isHeader ? const Color(0xFF1A4379) : const Color(0xFFCFD5E1),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), // Reducido moderadamente
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.white : Colors.black,
            fontSize: 11, // Reducido de 13 a 11
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Text(
          value,
          style: TextStyle(
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? Colors.white : Colors.black,
            fontSize: 11, // Reducido de 13 a 11
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ],
  );
}

 

  TableRow _buildTotalRowLarge(String label, String value, {bool isTotal = false}) {
  return TableRow(
    decoration: BoxDecoration(
      color: isTotal ? const Color(0xFF1A4379) : const Color(0xFFCFD5E1),
    ),
    children: [
      Padding(
        padding: EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isTotal ? Colors.white : Colors.black,
            fontSize: 10, // Aumentado de 8 a 10 (25% más grande)
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Text(
          value,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.white : Colors.black,
            fontSize: 10, // Aumentado de 8 a 10
          ),
        ),
      ),
    ],
  );
}

  
  // Widget para fila de totales en vista previa
  Widget _buildTotalRow(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
 
  
Widget _buildHeaderCell(String text) {
  return Container(
    padding: const EdgeInsets.all(2), // Reducido para maximizar espacio
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 7, // Reducido aún más
      ),
      textAlign: TextAlign.center,
    ),
  );
}


Widget _buildDataCell(String text, {Map<String, dynamic>? producto, bool enforceFull = false}) {
  bool isSelected = producto != null && producto['CODIGO'] == productoCodigoSeleccionado;
  
  // Determinar alineación según tipo de columna
  TextAlign alignment = TextAlign.center; // Default: centrado
  
  // Descripción y vehículo alineados a la izquierda
  if (producto != null) {
    if (text == producto['DESCRIPCION'] || text == producto['VEHICULO']) {
      alignment = TextAlign.left;
    } 
    // Valores monetarios alineados a la derecha
    else if (text.startsWith('\$')) {
      alignment = TextAlign.right;
    }
  }
  
  return GestureDetector(
    onTap: () {
      if (producto != null) {
        seleccionarProducto(producto);
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2), // Reducido para maximizar espacio
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 7), // Reducido aún más el tamaño
        overflow: TextOverflow.visible, // Siempre visible
        softWrap: true, // Permitir wrap
        maxLines: null, // Sin límite de líneas
        textAlign: alignment,
      ),
    ),
  );
}

TextAlign _getTextAlignmentForColumn(String text, Map<String, dynamic>? producto) {
  // Default to center for most columns
  if (producto == null) return TextAlign.center;
  
  // Align numeric values right (price columns)
  if (text.startsWith('\$')) return TextAlign.right;
  
  // Align descriptions and vehicle info left
  if (text == producto['DESCRIPCION'] || text == producto['VEHICULO']) {
    return TextAlign.left;
  }
  
  // Center everything else
  return TextAlign.center;
}
  
}