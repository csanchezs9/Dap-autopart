import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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

class _ProductosOrdenState extends State<ProductosOrden> {
  List<Map<String, dynamic>> productosAgregados = [];
  final TextEditingController codigoController = TextEditingController();
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionesController = TextEditingController();
  
  bool isLoading = false;
  String errorMessage = '';
  
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

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es_ES', null);
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

  void buscarProductoPorCodigo() async {
    String codigo = codigoController.text.trim();
    if (codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingrese un código de producto')),
      );
      return;
    }
    
    setState(() {
      isLoading = true;
    });
    
    try {
      // Obtener cantidad
      int cantidad = 1;
      if (cantidadController.text.isNotEmpty) {
        cantidad = int.tryParse(cantidadController.text.trim()) ?? 1;
      }
      
      // Buscar producto en Google Sheets
      final productoEncontrado = await ProductoService.buscarProductoPorCodigo(codigo);
      
      if (productoEncontrado != null) {
        // Procesar el producto encontrado
        Map<String, dynamic> producto = {
          '#': (productosAgregados.length + 1).toString(),
          'CODIGO': codigo,
          'CANT': cantidad
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
        
        // Verificar si está agotado
        bool agotado = false;
        if (productoEncontrado.containsKey('AGOTADO')) {
          agotado = productoEncontrado['AGOTADO'].toString().toUpperCase().contains('AGOTADO');
        }
        
        if (agotado) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ADVERTENCIA: El producto está AGOTADO')),
          );
        }
        
        // Calcular valor bruto
        double valorBruto = valorUnidad * cantidad * (1 - descuento/100);
        producto['V.BRUTO'] = valorBruto;
        
        setState(() {
          productosAgregados.add(producto);
          codigoController.clear();
          cantidadController.clear();
          calcularTotales();
        });
      } else {
        // Si no se encuentra, crear producto genérico
        Map<String, dynamic> productoGenerico = {
          '#': (productosAgregados.length + 1).toString(),
          'CODIGO': codigo,
          'UB': '',
          'REF': '',
          'ORIGEN': '',
          'DESCRIPCION': 'Producto con código $codigo',
          'VEHICULO': '',
          'MARCA': '',
          'VLR ANTES DE IVA': 0,
          'DSCTO': 0,
          'CANT': cantidad,
          'V.BRUTO': 0
        };
        
        setState(() {
          productosAgregados.add(productoGenerico);
          codigoController.clear();
          cantidadController.clear();
          calcularTotales();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se encontró producto con código: $codigo')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos a Solicitar'),
        backgroundColor: const Color(0xFF1A4379),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
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
                          controller: codigoController,
                          decoration: const InputDecoration(
                            labelText: 'Código Producto',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
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
                        onPressed: buscarProductoPorCodigo,
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
                        return DataRow(cells: [
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
                        ]);
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Sección inferior
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Imagen (placeholder)
                      Container(
                        width: 180,
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.cable, size: 48, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Imagen de Producto', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
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