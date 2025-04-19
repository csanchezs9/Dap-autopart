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
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
      // Obtener cantidad
      int cantidad = 1;
      if (cantidadController.text.isNotEmpty) {
        cantidad = int.tryParse(cantidadController.text.trim()) ?? 1;
      }
      
      // Buscar producto por número en el servidor
      final productoEncontrado = await ProductoService.buscarProductoPorNumero(numero);
      
      if (productoEncontrado != null) {
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
          // Procesar el producto encontrado
          String codigo = productoEncontrado['CODIGO']?.toString() ?? '';
          
          Map<String, dynamic> producto = {
            'CODIGO': codigo,
            'CANT': cantidad,
            '#': numero
          };
          
          // Mapeo de campos que vienen del servidor
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

          // Imprimir para depuración
          print("Valor antes de IVA para ${codigo}: $valorUnidad");

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

          // Establecer V.BRUTO igual a VLR ANTES DE IVA (sin aplicar descuento)
          double valorBruto = valorUnidad;

          // Imprimir para depuración
          print("Valor bruto establecido igual al valor antes de IVA: $valorBruto");

          producto['V.BRUTO'] = valorBruto;
          
          setState(() {
            productosAgregados.add(producto);
            numeroController.clear();
            cantidadController.clear();
            calcularTotales();
            
            productoCodigoSeleccionado = codigo;
            _checkImageExistence(codigo);
          });

          // Depuración: mostrar detalles del producto agregado
          print("⭐ PRODUCTO AGREGADO A LA LISTA: $producto");
        }
      } else {
        // Si no se encuentra, mostrar mensaje
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se encontró producto con número: $numero')),
        );
      }
    } catch (e) {
      print("Error al buscar producto: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar el producto: $e')),
      );
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
      numValor = double.parse(valor.toString());
    } catch (e) {
      return '\$0';
    }
  }
  
  // Imprimir para depuración
  print("Formateando valor monetario: $numValor");
  
  // ¡NO multiplicar por 1000! El valor ya viene correcto desde el servidor
  
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
    // Crear un documento PDF
    final pdf = pw.Document();
    
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
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'DAP',
                          style: pw.TextStyle(
                            fontSize: 30,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Text(
                          'AutoPart\'s',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red700,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text('Distribuciones Autoparts S.A.S'),
                        pw.Text('Nit: 901.110.424-1'),
                      ],
                    ),
                    
                    // Información de la orden
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('FECHA: ${obtenerFechaActual()}', 
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('ORDEN DE PEDIDO #: ${widget.ordenNumero}', 
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
                      'ORDEN DE PEDIDO #: ${widget.ordenNumero} - Página ${context.pageNumber}',
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
              border: pw.TableBorder.all(),
              columnWidths: {
                0: pw.FixedColumnWidth(25), // #
                1: pw.FixedColumnWidth(50), // CÓDIGO
                2: pw.FixedColumnWidth(30), // UB
                3: pw.FixedColumnWidth(60), // REF
                4: pw.FixedColumnWidth(50), // ORIGEN
                5: pw.FixedColumnWidth(100), // DESCRIPCIÓN
                6: pw.FixedColumnWidth(110), // VEHÍCULO
                7: pw.FixedColumnWidth(50), // MARCA
                8: pw.FixedColumnWidth(50), // ANTES IVA
                9: pw.FixedColumnWidth(40), // DSCTO
                10: pw.FixedColumnWidth(30), // CANT
                11: pw.FixedColumnWidth(50), // V.BRUTO
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
                    _buildPDFHeaderCell('ANTES IVA'),
                    _buildPDFHeaderCell('DSCTO'),
                    _buildPDFHeaderCell('CANT'),
                    _buildPDFHeaderCell('V.BRUTO'),
                  ],
                ),
                
                // Filas de productos
                ...productosAgregados.map((producto) => pw.TableRow(
                  children: [
                    _buildPDFDataCell(producto['#']?.toString() ?? ''),
                    _buildPDFDataCell(producto['CODIGO']?.toString() ?? ''),
                    _buildPDFDataCell(producto['UB']?.toString() ?? ''),
                    _buildPDFDataCell(producto['REF']?.toString() ?? ''),
                    _buildPDFDataCell(producto['ORIGEN']?.toString() ?? ''),
                    _buildPDFDataCell(producto['DESCRIPCION']?.toString() ?? ''),
                    _buildPDFDataCell(producto['VEHICULO']?.toString() ?? ''),
                    _buildPDFDataCell(producto['MARCA']?.toString() ?? ''),
                    _buildPDFDataCell(formatCurrency(producto['VLR ANTES DE IVA'])),
                    _buildPDFDataCell('${producto['DSCTO']}%'),
                    _buildPDFDataCell(producto['CANT']?.toString() ?? ''),
                    _buildPDFDataCell(formatCurrency(producto['V.BRUTO'])),
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


  pw.Widget _buildPDFHeaderCell(String text, {pw.TextStyle? style}) {
  return pw.Padding(
    padding: pw.EdgeInsets.all(3),
    child: pw.Text(
      text,
      style: style ?? pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8,
      ),
      textAlign: pw.TextAlign.center,
    ),
  );
}
  pw.Widget _buildPDFDataCell(String text, {pw.TextStyle? style}) {
  return pw.Padding(
    padding: pw.EdgeInsets.all(3),
    child: pw.Text(
      text,
      style: style ?? pw.TextStyle(fontSize: 8),
      textAlign: pw.TextAlign.center,
      maxLines: 2,
      overflow: pw.TextOverflow.clip,
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
    setState(() {
      productoCodigoSeleccionado = codigo;
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
      // Añadimos la 'm' al principio del código, según el formato mencionado
      final assetPath = 'assets/imagenesProductos/m$codigo.jpg';
      await rootBundle.load(assetPath);
      _imagenesDisponibles[codigo] = true;
    } catch (e) {
      print("Imagen no encontrada para $codigo: $e");
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
                                  RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                                      children: [
                                        TextSpan(
                                          text: 'DAP\n',
                                          style: TextStyle(color: Color(0xFF1A4379)),
                                        ),
                                        TextSpan(
                                          text: 'AutoPart´s',
                                          style: TextStyle(color: Colors.red[700]),
                                        ),
                                      ],
                                    ),
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
                                  Text('ORDEN DE PEDIDO #: ${widget.ordenNumero}', style: TextStyle(fontWeight: FontWeight.bold)),
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

                          // Tabla de productos - VERSIÓN CORREGIDA
                          Container(
                      width: MediaQuery.of(context).size.width,
                      child: Column(
                        children: [
                          // Cabecera de la tabla
                          Table(
                            border: TableBorder.all(color: const Color(0xFF1A4379)),
                            columnWidths: const {
                              0: FractionColumnWidth(0.05), // #
                              1: FractionColumnWidth(0.09), // CÓDIGO
                              2: FractionColumnWidth(0.05), // UB
                              3: FractionColumnWidth(0.09), // REF
                              4: FractionColumnWidth(0.08), // ORIGEN
                              5: FractionColumnWidth(0.15), // DESCRIPCIÓN
                              6: FractionColumnWidth(0.12), // VEHÍCULO
                              7: FractionColumnWidth(0.09), // MARCA
                              8: FractionColumnWidth(0.09), // ANTES IVA
                              9: FractionColumnWidth(0.05), // DSCTO
                              10: FractionColumnWidth(0.05), // CANT
                              11: FractionColumnWidth(0.09), // V.BRUTO
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
                                  _buildHeaderCell('ANTES IVA'),
                                  _buildHeaderCell('DSCTO'),
                                  _buildHeaderCell('CANT'),
                                  _buildHeaderCell('V.BRUTO'),
                                ],
                              ),
                            ],
                          ),

                          // Cuerpo de la tabla con scroll vertical
                          Container(
                            height: MediaQuery.of(context).size.height * 0.3,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Table(
                                border: TableBorder.all(color: Colors.grey.shade300),
                                columnWidths: const {
                                  0: FractionColumnWidth(0.05), // #
                                  1: FractionColumnWidth(0.09), // CÓDIGO
                                  2: FractionColumnWidth(0.05), // UB
                                  3: FractionColumnWidth(0.09), // REF
                                  4: FractionColumnWidth(0.08), // ORIGEN
                                  5: FractionColumnWidth(0.15), // DESCRIPCIÓN
                                  6: FractionColumnWidth(0.12), // VEHÍCULO
                                  7: FractionColumnWidth(0.09), // MARCA
                                  8: FractionColumnWidth(0.09), // ANTES IVA
                                  9: FractionColumnWidth(0.05), // DSCTO
                                  10: FractionColumnWidth(0.05), // CANT
                                  11: FractionColumnWidth(0.09), // V.BRUTO
                                },
                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                children: productosAgregados.map((producto) {
                                  bool isSelected = producto['CODIGO'] == productoCodigoSeleccionado;
                                  return TableRow(
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                                    ),
                                    children: [
                                      _buildDataCell(producto['#']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['CODIGO']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['UB']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['REF']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['ORIGEN']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['DESCRIPCION']?.toString() ?? '', maxLines: 2, producto: producto),
                                      _buildDataCell(producto['VEHICULO']?.toString() ?? '', producto: producto),
                                      _buildDataCell(producto['MARCA']?.toString() ?? '', producto: producto),
                                      _buildDataCell(_formatMoneda(producto['VLR ANTES DE IVA']), producto: producto),
                                      _buildDataCell('${producto['DSCTO']}%', producto: producto),
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
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          color: Color(0xFF1A4379),
          width: double.infinity,
          child: Text(
            'OBSERVACIONES',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          // Contenedor con restricciones para ajustarse al contenido
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 20, // Altura mínima para consistencia visual
              maxHeight: 150, // Altura máxima razonable
            ),
            child: SingleChildScrollView( // Para permitir desplazamiento si hay mucho texto
              child: Text(
                observacionesController.text.isEmpty ? 
                'Sin observaciones' : observacionesController.text
              ),
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

  

 Future<void> _enviarCorreoPorServidor() async {
  setState(() {
    isLoading = true;
  });

  try {
    print("Generando PDF...");
    final pdf = await _generarPDFMejorado();
    print("PDF generado correctamente: ${pdf?.length ?? 0} bytes");
    
    if (pdf == null) {
      throw Exception("No se pudo generar el PDF");
    }
    
    // Guardar PDF en almacenamiento temporal
    final dir = await getTemporaryDirectory();
    final fileName = 'orden_${widget.ordenNumero}.pdf';
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
      Uri.parse('https://dapautopart.onrender.com/send-email'),    
    );
    
    // Agregar los campos
    request.fields['clienteEmail'] = emailCliente;
    request.fields['asesorEmail'] = widget.asesorData['MAIL'] ?? '';
    request.fields['asunto'] = 'Orden de Pedido ${widget.ordenNumero} - DAP AutoPart\'s';
    request.fields['cuerpo'] = '''Estimado cliente ${widget.clienteData['NOMBRE'] ?? ''},
        
Adjunto encontrará su orden de pedido #${widget.ordenNumero}.
  
Gracias por su preferencia,
  
${widget.asesorData['NOMBRE'] ?? 'Su asesor'}
DAP AutoPart's
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
    final streamedResponse = await request.send();
    print("Respuesta del servidor recibida: ${streamedResponse.statusCode}");
    final response = await http.Response.fromStream(streamedResponse);
    print("Cuerpo de la respuesta: ${response.body}");
    
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      
      if (jsonResponse['success']) {
        // ✨ NUEVO: Confirmar el uso del número de orden para sincronizar con otros dispositivos
        try {
          // Enviar confirmación al servidor
          await http.post(
            Uri.parse('https://dapautopart.onrender.com/confirmar-orden'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'numeroOrden': widget.ordenNumero,
            }),
          );
          print("Número de orden confirmado en el servidor");
        } catch (e) {
          print("Error al confirmar número de orden: $e");
          // Continuar aunque falle la confirmación
        }
        
        // Mostrar diálogo de éxito
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Correo enviado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 48),
                  SizedBox(height: 16),
                  Text('La orden ha sido enviada correctamente a:'),
                  SizedBox(height: 8),
                  Text(emailCliente, style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Aceptar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // Volver a la pantalla anterior
                  },
                ),
              ],
            );
          },
        );
      } else {
        throw Exception("Error del servidor: ${jsonResponse['message']}");
      }
    } else {
      throw Exception("Error de conexión: ${response.statusCode}");
    }
    
  } catch (e) {
    print("Error detallado: ${e.toString()}");
    
    // Añadir mensaje más informativo
    String errorMsg = 'Error al enviar el correo: $e';
    if (e.toString().contains('timed out')) {
      errorMsg = 'No se pudo conectar al servidor (tiempo de espera agotado). Verifica que el servidor esté funcionando y que la IP sea correcta.';
    } else if (e.toString().contains('connection refused')) {
      errorMsg = 'Conexión rechazada. Verifica que el servidor esté funcionando en el puerto 3000.';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMsg)),
    );
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  // Encabezado: información cliente y opciones
                  // Encabezado: información cliente y opciones - Versión reducida
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Información cliente (reducida en un 20% en lugar de 38%)
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
          Text('ORDEN DE PEDIDO #: ${widget.ordenNumero}', 
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
                  Container(
                        width: MediaQuery.of(context).size.width,
                        child: Column(
                          children: [
                            // Cabecera de la tabla
                            Table(
                              border: TableBorder.all(color: const Color(0xFF1A4379)),
                              columnWidths: const {
                                0: FractionColumnWidth(0.05), // #
                                1: FractionColumnWidth(0.09), // CÓDIGO
                                2: FractionColumnWidth(0.05), // UB
                                3: FractionColumnWidth(0.09), // REF
                                4: FractionColumnWidth(0.08), // ORIGEN
                                5: FractionColumnWidth(0.15), // DESCRIPCIÓN
                                6: FractionColumnWidth(0.12), // VEHÍCULO
                                7: FractionColumnWidth(0.09), // MARCA
                                8: FractionColumnWidth(0.09), // ANTES IVA
                                9: FractionColumnWidth(0.05), // DSCTO
                                10: FractionColumnWidth(0.05), // CANT
                                11: FractionColumnWidth(0.09), // V.BRUTO
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
                                    _buildHeaderCell('ANTES IVA'),
                                    _buildHeaderCell('DSCTO'),
                                    _buildHeaderCell('CANT'),
                                    _buildHeaderCell('V.BRUTO'),
                                  ],
                                ),
                              ],
                            ),

                            // Cuerpo de la tabla con altura adaptativa
                            Container(
                              // Altura mínima para siempre mostrar algo
                              constraints: BoxConstraints(
                                minHeight: 100,
                                // Altura máxima que sea aproximadamente 1/3 de la pantalla
                                maxHeight: MediaQuery.of(context).size.height * 0.33,
                              ),
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Table(
                                  border: TableBorder.all(color: Colors.grey.shade300),
                                  columnWidths: const {
                                    0: FractionColumnWidth(0.05), // #
                                    1: FractionColumnWidth(0.09), // CÓDIGO
                                    2: FractionColumnWidth(0.05), // UB
                                    3: FractionColumnWidth(0.09), // REF
                                    4: FractionColumnWidth(0.08), // ORIGEN
                                    5: FractionColumnWidth(0.15), // DESCRIPCIÓN
                                    6: FractionColumnWidth(0.12), // VEHÍCULO
                                    7: FractionColumnWidth(0.09), // MARCA
                                    8: FractionColumnWidth(0.09), // ANTES IVA
                                    9: FractionColumnWidth(0.05), // DSCTO
                                    10: FractionColumnWidth(0.05), // CANT
                                    11: FractionColumnWidth(0.09), // V.BRUTO
                                  },
                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                  children: productosAgregados.map((producto) {
                                    bool isSelected = producto['CODIGO'] == productoCodigoSeleccionado;
                                    return TableRow(
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                                      ),
                                      children: [
                                        _buildDataCell(producto['#']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['CODIGO']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['UB']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['REF']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['ORIGEN']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['DESCRIPCION']?.toString() ?? '', maxLines: 2, producto: producto),
                                        _buildDataCell(producto['VEHICULO']?.toString() ?? '', producto: producto),
                                        _buildDataCell(producto['MARCA']?.toString() ?? '', producto: producto),
                                        _buildDataCell(_formatMoneda(producto['VLR ANTES DE IVA']), producto: producto),
                                        _buildDataCell('${producto['DSCTO']}%', producto: producto),
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
                      ),
                  
                  Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Imagen del producto (30% más grande)
    Container(
      width: 110, // Aumentado de 85 a 110 (aproximadamente 30% más)
      height: 90, // Aumentado de 70 a 90 (aproximadamente 30% más)
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildImagenProducto(),
    ),
    
    const SizedBox(width: 8),
    
    // Observaciones (expansible)
    Expanded(
      flex: 3,
      child: Container(
        padding: const EdgeInsets.all(4),
        height: 90, // Aumentado de 70 a 90 para mantener proporción con la imagen
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
                maxLines: null,
                expands: true,
                style: TextStyle(fontSize: 10), // Ligeramente más grande de 9 a 10
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
    
    const SizedBox(width: 8),
    
    // Totales (20% más grande)
    Container(
      width: 150, // Aumentado de 125 a 150 (20% más)
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

                  
                  const SizedBox(height: 10),
                  
                  // Botones
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
                          ),
                          child: const Text('VISTA PREVIA'),
                        ),
                        SizedBox(width: 20),
                        // Botón Enviar
                        ElevatedButton(
                          onPressed: () {
                            _enviarCorreoPorServidor(); // Cambio aquí
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.grey),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
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
                          ),
                          child: const Text('CANCELAR ORDEN'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  // Widget para mostrar la imagen del producto
  Widget _buildImagenProducto() {
  if (productoCodigoSeleccionado == null) {
    // No hay producto seleccionado - interfaz ajustada al nuevo tamaño
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.image, size: 40, color: Colors.grey), // Aumentado de 30 a 40
          SizedBox(height: 4), // Aumentado de 2 a 4
          Text(
            'Seleccione producto',
            style: TextStyle(color: Colors.grey, fontSize: 10), // Aumentado de 8 a 10
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  final codigo = productoCodigoSeleccionado!;
  final bool imagenDisponible = _imagenesDisponibles[codigo] ?? false;
  
  if (!imagenDisponible) {
    // La imagen no existe - versión ajustada al nuevo tamaño
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hide_image, size: 40, color: Colors.grey), // Aumentado de 30 a 40
          const SizedBox(height: 4), // Aumentado de 2 a 4
          Text(
            'No hay imagen\npara $codigo',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 10), // Aumentado de 8 a 10
          ),
        ],
      ),
    );
  }
  
  // Mostrar la imagen con el prefijo "m" y hacerla presionable
  return GestureDetector(
    onTap: () {
      _mostrarImagenGrande(codigo);
    },
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/imagenesProductos/m$codigo.jpg',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          _imagenesDisponibles[codigo] = false;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, size: 40, color: Colors.red), // Aumentado de 30 a 40
                const SizedBox(height: 4), // Aumentado de 2 a 4
                Text(
                  'Error al cargar imagen\n$codigo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 10), // Aumentado de 8 a 10
                ),
              ],
            ),
          );
        },
      ),
    ),
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              // Contenedor con la imagen
              Container(
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/imagenesProductos/m$codigo.jpg',
                    fit: BoxFit.contain,
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
                  ),
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
            ],
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
      // Limpia el valor de cualquier formato no numérico
      String cleanValue = value.toString()
          .replaceAll('\$', '')
          .replaceAll(',', '')
          .trim();
      numValue = double.tryParse(cleanValue) ?? 0;
    } catch (e) {
      numValue = 0;
    }
  }
  
  // Imprimir para depuración
  print("Formateando para PDF: $numValue");
  
  // ¡NO multiplicar por 1000! El valor ya viene correcto desde el servidor
  
  try {
    // Formatear con miles de separación y sin decimales para pesos colombianos
    final formatter = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 0, // Sin decimales para pesos colombianos
      locale: 'es_CO',
    );
    return formatter.format(numValue);
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
    padding: const EdgeInsets.all(4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 9, // Texto más pequeño para caber
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

_buildDataCell(String text, {int maxLines = 1, Map<String, dynamic>? producto}) {
  // Para valores de descuento, asegurarse de mostrar el símbolo %
  if (text.endsWith('%')) {
    return GestureDetector(
      onTap: () {
        if (producto != null) {
          seleccionarProducto(producto);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9),
          overflow: TextOverflow.ellipsis,
          maxLines: maxLines,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  
  // Para otros valores
  return GestureDetector(
    onTap: () {
      if (producto != null) {
        seleccionarProducto(producto);
      }
    },
    child: Container(
      padding: const EdgeInsets.all(4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9),
        overflow: TextOverflow.ellipsis,
        maxLines: maxLines,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
  
}