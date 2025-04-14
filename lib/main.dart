import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'orden_de_pedido_main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login App',
      home: LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool recordarDatos = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosGuardados();
  }

  Future<void> _cargarDatosGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recordarDatos = prefs.getBool('recordar') ?? false;
      if (recordarDatos) {
        _emailController.text = prefs.getString('correo') ?? '';
        _passwordController.text = prefs.getString('password') ?? '';
      }
    });
  }

  Future<void> _guardarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    if (recordarDatos) {
      await prefs.setString('correo', _emailController.text);
      await prefs.setString('password', _passwordController.text);
    }
    await prefs.setBool('recordar', recordarDatos);
  }

  Future<List<String>> cargarCorreosDesdeCSV() async {
    final rawData = await rootBundle.loadString('assets/asesores.csv');
    final List<List<dynamic>> lista = const CsvToListConverter().convert(rawData);
    return lista.skip(1).map((fila) => fila[3].toString().trim().toLowerCase()).toList();
  }

  void _login() async {
    final emailIngresado = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    final listaCorreos = await cargarCorreosDesdeCSV();

    if (listaCorreos.contains(emailIngresado) && password == "1234") {
      await _guardarDatos();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => OrdenDePedidoMain()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Correo o contraseña incorrectos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Parte izquierda: Login
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Usuario"),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.blue[800],
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text("Contraseña"),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.blue[800],
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: recordarDatos,
                          onChanged: (value) {
                            setState(() {
                              recordarDatos = value!;
                            });
                          },
                          activeColor: Colors.black,
                        ),
                        Text('Recordar mis datos'),
                      ],
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Ingresar', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Parte derecha: Logo / Marca
            Expanded(
              flex: 2,
              child: Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: 'DAP\n',
                        style: TextStyle(color: Colors.blue[900]),
                      ),
                      TextSpan(
                        text: 'AutoPart´s',
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
