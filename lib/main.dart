import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'orden_de_pedido_main.dart';
import 'package:flutter/services.dart';
import 'asesor_service_local.dart';
import 'package:http/http.dart' as http;

void main() {
  // Aseguramos que Flutter esté inicializado antes de configurar la orientación
  WidgetsFlutterBinding.ensureInitialized();
  
  // Forzar orientación horizontal en toda la aplicación
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    // Una vez configurada la orientación, ejecutamos la app
    runApp(MyApp());
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAP AutoPart\'s',
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
  bool isLoading = false;

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

  void _login() async {
  final emailIngresado = _emailController.text.trim().toLowerCase();
  final password = _passwordController.text.trim();

  if (emailIngresado.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Por favor ingrese su correo electrónico')),
    );
    return;
  }

  setState(() {
    isLoading = true;
  });

  try {
    // Primero verificar conectividad con un ping rápido al servidor
    try {
      final pingResponse = await http.get(
        Uri.parse('${AsesorServiceLocal.baseUrl}/ping'),
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

    // Si llegamos aquí, hay conexión. Seguimos con el proceso normal
    final asesorEncontrado = await AsesorServiceLocal.buscarAsesorPorCorreo(emailIngresado);
    
    if (asesorEncontrado != null) {
      final asesorId = asesorEncontrado['ID']?.toString() ?? '';
      
      String passwordCorrecta = '';
      if (asesorId.length >= 4) {
        passwordCorrecta = asesorId.substring(asesorId.length - 4);
      } else {
        passwordCorrecta = asesorId;
      }
      
      if (password == passwordCorrecta) {
        await _guardarDatos();
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('asesor_id', asesorEncontrado['ID']?.toString() ?? '');
        await prefs.setString('asesor_nombre', asesorEncontrado['NOMBRE']?.toString() ?? '');
        await prefs.setString('asesor_zona', asesorEncontrado['ZONA']?.toString() ?? '');
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => OrdenDePedidoMain()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Correo o contraseña incorrectos')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Correo o contraseña incorrectos')),
      );
    }
  } catch (e) {
    // Mejorar el mensaje de error para mostrar un mensaje más amigable al usuario
    String mensajeError = 'Error al iniciar sesión';
    
    if (e.toString().contains('internet') || 
        e.toString().contains('conectar') ||
        e.toString().contains('conexión') ||
        e.toString().contains('timeout') ||
        e.toString().contains('SocketException')) {
      mensajeError = 'No hay conexión a internet. Por favor verifique su conexión y vuelva a intentarlo.';
    }
    
    // Mostrar un diálogo de error en lugar de solo un SnackBar para mayor visibilidad
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error de conexión'),
          content: Text(mensajeError),
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
    
    print('Error detallado: $e');
  } finally {
    setState(() {
      isLoading = false;
    });
  }
}
  @override
  Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,
    // Añadimos resizeToAvoidBottomInset para que la pantalla no se redimensione con el teclado
    resizeToAvoidBottomInset: false, 
    body: SingleChildScrollView(
      child: Center(
        child: Container(
          // Esto asegura que el contenido tenga al menos la altura de la pantalla
          height: MediaQuery.of(context).size.height,
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
                        onPressed: isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: isLoading 
                          ? SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            )
                          : Text('Ingresar', style: TextStyle(color: Colors.white)),
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
    ),
  ),
    );
  }
}