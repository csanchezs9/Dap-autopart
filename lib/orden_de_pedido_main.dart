import 'package:flutter/material.dart';
import 'orden.dart';
import 'main.dart';
import 'catalogo_service.dart'; // Importamos el servicio de catálogo
import 'lista_precios_service.dart'; // Importamos el nuevo servicio

class OrdenDePedidoMain extends StatelessWidget {
  const OrdenDePedidoMain({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Botón de cerrar sesión
          Positioned(
            top: 40,
            right: 20,
            child: Column(
              children: [
                IconButton(
                  icon: Icon(Icons.power_settings_new, color: Colors.cyan, size: 36),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => LoginScreen()),
                    );
                  },
                ),
                Text(
                  'CERRAR CESION',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          // Contenido centrado horizontal con botón y logo alineados
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Botón ORDEN DE PEDIDO
                ElevatedButton.icon(
                  icon: Icon(Icons.shopping_cart_checkout_rounded, size: 24),
                  label: Text(
                    'ORDEN DE PEDIDO',
                    style: TextStyle(fontSize: 16),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => OrdenDePedido()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue[800],
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                // Logo DAP AutoPart's
                Image.asset(
  'assets/images/logo.png',
  width: 180,
  fit: BoxFit.contain,
),
              ],
            ),
          ),

          // Botones inferiores: CATÁLOGO y LISTA DE PRECIOS
          Positioned(
            bottom: 30,
            right: 20,
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.menu_book),
                  label: Text("CATÁLOGO"),
                  onPressed: () {
                    // Llamamos al método para mostrar el diálogo de confirmación
                    // y luego descargar/abrir el catálogo si el usuario acepta
                    CatalogoService.abrirCatalogo(context);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: Icon(Icons.price_change),
                  label: Text("LISTA DE\nPRECIOS", textAlign: TextAlign.center),
                  onPressed: () {
                    // Generar y mostrar la lista de precios
                    ListaPreciosService.generarListaPrecios(context);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}