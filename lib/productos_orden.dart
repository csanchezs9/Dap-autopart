import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'producto_service.dart';

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
  bool isParcial = false;
  bool isTotal = false;
  bool isContado = false;
  
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
      final formatter = DateFormat('dd – MMMM – yyyy', 'es_ES');
      String fecha = formatter.format(now).toUpperCase();
      return fecha;
    } catch (e) {
      print("Error al formatear fecha: $e");
      return "${now.day} - ${now.month} - ${now.year}";
    }
  }

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
      
      // Buscar producto por número en Google Sheets
      final productoEncontrado = await ProductoService.buscarProductoPorNumero(numero);
      
      if (productoEncontrado != null) {
        // Verificar si está agotado antes de procesarlo
        bool agotado = false;
        if (productoEncontrado.containsKey('AGOTADO')) {
          agotado = productoEncontrado['AGOTADO'].toString().toUpperCase().contains('AGOTADO');
        } else if (productoEncontrado.containsKey('ESTADO')) {
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
          // Procesar el producto encontrado (que no está agotado)
          String codigo = productoEncontrado['CODIGO']?.toString() ?? '';
print("DEPURACIÓN: Código del producto encontrado: $codigo");
          
          Map<String, dynamic> producto = {
            'CODIGO': codigo,
            'CANT': cantidad,
            '#': numero
            
          };
          
          // Mapeo específico para los campos de tu hoja
         
          producto['UB'] = productoEncontrado['Bod'] ?? '';
          producto['REF'] = productoEncontrado['Ref'] ?? '';
          producto['ORIGEN'] = productoEncontrado['Origen'] ?? '';
          producto['DESCRIPCION'] = productoEncontrado['Descripción'] ?? '';
          producto['VEHICULO'] = productoEncontrado['Vehiculo'] ?? '';
          producto['MARCA'] = productoEncontrado['Marca'] ?? '';
          
          // Procesar precio
          double valorUnidad = 0;
          if (productoEncontrado.containsKey('Precio Antes de Iva')) {
            String precioStr = productoEncontrado['Precio Antes de Iva'].toString()
                .replaceAll('\$', '')
                .replaceAll('.', '')
                .replaceAll(',', '')
                .trim();
            valorUnidad = double.tryParse(precioStr) ?? 0;
          }
          producto['VLR ANTES DE IVA'] = valorUnidad;
          
          // Procesar descuento
          double descuento = 0;
          if (productoEncontrado.containsKey('Dscto')) {
            String dsctoStr = productoEncontrado['Dscto'].toString()
                .replaceAll('%', '')
                .trim();
            descuento = double.tryParse(dsctoStr) ?? 0;
          }
          producto['DSCTO'] = descuento;
          
          // Calcular valor bruto
          double valorBruto = valorUnidad * cantidad * (1 - descuento/100);
          producto['V.BRUTO'] = valorBruto;
          
          setState(() {
          productosAgregados.add(producto);
          numeroController.clear();
          cantidadController.clear();
          calcularTotales();
          
          productoCodigoSeleccionado = codigo;
          print("DEPURACIÓN: Código seleccionado establecido a: $productoCodigoSeleccionado");
          
          _checkImageExistence(codigo);
          });
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
      
      double precioTotal = precio * cantidad;
      double descuentoMonto = precioTotal * (porcentajeDescuento / 100);
      
      vBruto += precioTotal;
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
  print("DEPURACIÓN seleccionarProducto: Seleccionando producto con código: $codigo");
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado: información cliente y opciones
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Información cliente
                      Expanded(
                        flex: 2,
                        child: Table(
                          border: TableBorder.all(color: Colors.white),
                          columnWidths: const {
                            0: FlexColumnWidth(1.5),
                            1: FlexColumnWidth(3),
                          },
                          children: [
                            _buildInfoRow('NIT CLIENTE', widget.clienteData['NIT CLIENTE'] ?? '', isHeader: true),
                            _buildInfoRow('NOMBRE', widget.clienteData['NOMBRE'] ?? ''),
                            _buildInfoRow('ESTABLECIMIENTO', widget.clienteData['ESTABLECIMIENTO'] ?? ''),
                          ],
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
                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text('ORDEN DE PEDIDO #: ${widget.ordenNumero}', 
                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 10),
                            
                            // Checkboxes en filas
                            Row(
                              children: [
                                _buildCheckbox('NORMAL', isNormal, (val) {
                                  setState(() {
                                    isNormal = val!;
                                    if (isNormal) isCondicionado = isParcial = isTotal = false;
                                  });
                                }),
                                _buildCheckbox('CONDICIONADO', isCondicionado, (val) {
                                  setState(() {
                                    isCondicionado = val!;
                                    if (isCondicionado) isNormal = isParcial = isTotal = false;
                                  });
                                }),
                              ],
                            ),
                            Row(
                              children: [
                                _buildCheckbox('PARCIAL', isParcial, (val) {
                                  setState(() {
                                    isParcial = val!;
                                    if (isParcial) isNormal = isCondicionado = isTotal = false;
                                  });
                                }),
                                _buildCheckbox('TOTAL', isTotal, (val) {
                                  setState(() {
                                    isTotal = val!;
                                    if (isTotal) isNormal = isCondicionado = isParcial = false;
                                  });
                                }),
                              ],
                            ),
                            _buildCheckbox('CONTADO', isContado, (val) {
                              setState(() { isContado = val!; });
                            }),
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateColor.resolveWith((_) => const Color(0xFF1A4379)),
                      dataRowHeight: 40,
                      headingRowHeight: 40,
                      columnSpacing: 20,
                      columns: [
                        DataColumn(label: _headerText('#')),
                        DataColumn(label: _headerText('CÓDIGO')),
                        DataColumn(label: _headerText('UB')),
                        DataColumn(label: _headerText('REF')),
                        DataColumn(label: _headerText('ORIGEN')),
                        DataColumn(label: _headerText('DESCRIPCION')),
                        DataColumn(label: _headerText('VEHICULO')),
                        DataColumn(label: _headerText('MARCA')),
                        DataColumn(label: _headerText('VLR ANTES\nDE IVA')),
                        DataColumn(label: _headerText('DSCTO')),
                        DataColumn(label: _headerText('CANT')),
                        DataColumn(label: _headerText('V.BRUTO')),
                      ],
                      rows: productosAgregados.map((producto) {
                        return DataRow(
                          cells: [
                            DataCell(Text(producto['#']?.toString() ?? '')),
                            DataCell(Text(producto['CODIGO']?.toString() ?? '')),
                            DataCell(Text(producto['UB']?.toString() ?? '')),
                            DataCell(Text(producto['REF']?.toString() ?? '')),
                            DataCell(Text(producto['ORIGEN']?.toString() ?? '')),
                            DataCell(Text(producto['DESCRIPCION']?.toString() ?? '')),
                            DataCell(Text(producto['VEHICULO']?.toString() ?? '')),
                            DataCell(Text(producto['MARCA']?.toString() ?? '')),
                            DataCell(Text(formatCurrency(producto['VLR ANTES DE IVA']))),
                            DataCell(Text('${producto['DSCTO']}%')),
                            DataCell(Text(producto['CANT']?.toString() ?? '')),
                            DataCell(Text(formatCurrency(producto['V.BRUTO']))),
                          ],
                          onSelectChanged: (_) {
                            seleccionarProducto(producto);
                          },
                          selected: producto['CODIGO'] == productoCodigoSeleccionado,
                        );
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Sección inferior
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Imagen del producto
                      Container(
                        width: 180,
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _buildImagenProducto(),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Observaciones
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          height: 140,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCFD5E1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('OBSERVACIONES:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              Expanded(
                                child: TextField(
                                  controller: observacionesController,
                                  maxLines: null,
                                  expands: true,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: EdgeInsets.all(8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Totales
                      Container(
                        width: 180,
                        child: Table(
                          border: TableBorder.all(),
                          columnWidths: const {
                            0: FlexColumnWidth(1),
                            1: FlexColumnWidth(1),
                          },
                          children: [
                            _buildTotalRow('V.BRUTO', formatCurrency(valorBrutoTotal)),
                            _buildTotalRow('DSCTO', formatCurrency(descuentoTotal)),
                            _buildTotalRow('SUBTOTAL', formatCurrency(subtotal)),
                            _buildTotalRow('IVA', formatCurrency(iva)),
                            _buildTotalRow('TOTAL', formatCurrency(total), isTotal: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Botón para cancelar orden
                  Center(
                    child: ElevatedButton(
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
                  ),
                ],
              ),
            ),
    );
  }
  
  // Widget para mostrar la imagen del producto, simplificado
  Widget _buildImagenProducto() {
    if (productoCodigoSeleccionado == null) {
      // No hay producto seleccionado
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.image, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Seleccione un producto', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    final codigo = productoCodigoSeleccionado!;
    final bool imagenDisponible = _imagenesDisponibles[codigo] ?? false;
    
    if (!imagenDisponible) {
      // La imagen no existe o no se ha verificado aún
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hide_image, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'No hay imagen para\n$codigo',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    // Mostrar la imagen con el prefijo "m"
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/imagenesProductos/m$codigo.jpg',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Si hay un error al cargar la imagen
            print("Error al cargar imagen: $error");
            _imagenesDisponibles[codigo] = false;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  Text(
                    'Error al cargar imagen\n$codigo',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } catch (e) {
      print("Error general al mostrar imagen: $e");
      _imagenesDisponibles[codigo] = false;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              'Error: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    }
  }

  // Formato para moneda
  String formatCurrency(dynamic value) {
    if (value == null) return '\$0';
    
    double numValue;
    if (value is num) {
      numValue = value.toDouble();
    } else {
      numValue = double.tryParse(value.toString()) ?? 0;
    }
    
    return '\$${NumberFormat('#,###').format(numValue)}';
  }

  // Widgets auxiliares
  TableRow _buildInfoRow(String label, String value, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFF1A4379) : const Color(0xFFCFD5E1),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.white : Colors.black,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.white : Colors.black,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.black,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
      ],
    );
  }

  TableRow _buildTotalRow(String label, String value, {bool isTotal = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isTotal ? const Color(0xFF1A4379) : const Color(0xFFCFD5E1),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.white : Colors.black,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.white : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
        fontSize: 12,
      ),
    );
  }
}