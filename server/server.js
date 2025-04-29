const express = require('express');
const multer = require('multer');
const nodemailer = require('nodemailer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const bodyParser = require('body-parser');
const csv = require('csv-parser'); // Para CSV estándar
const { parse } = require('csv-parse/sync'); // Para control manual del parsing
const session = require('express-session');
const crypto = require('crypto');

const app = express();
let ultimoNumeroOrden = 1;
const UPLOAD_FILE_SIZE_LIMIT = 300 * 1024 * 1024; // 300MB - aumentar si necesitas más
const UPLOAD_TIMEOUT = 3600000; // 1 hora en milisegundos 


const isProduction = process.env.NODE_ENV === 'production';
const baseStoragePath = isProduction 
  ? '/opt/render/project/src/data' // Ruta del disco persistente en Render
  : path.join(__dirname); // Ruta local para desarrollo


  if (!fs.existsSync(baseStoragePath)) {
    try {
      fs.mkdirSync(baseStoragePath, { recursive: true });
      console.log(`Carpeta base de almacenamiento creada: ${baseStoragePath}`);
    } catch (error) {
      console.error(`Error al crear carpeta base de almacenamiento: ${error.message}`);
    }
  }


const sessionConfig = {
  secret: process.env.SESSION_SECRET || 'dap-autoparts-secret-key',
  resave: true,                // Cambiado a true para forzar guardado de sesión
  saveUninitialized: true,     // Cambiado a true para asegurar que se guarde
  cookie: { 
    secure: false,             // Cambiado a false (incluso en producción)
    maxAge: 24 * 60 * 60 * 1000 // Aumentar a 24 horas
  }
};


const ADMIN_USERNAME = process.env.ADMIN_USERNAME
// Contraseña: dap2024
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD


// Crear carpeta de archivos si no existe
const uploadDir = path.join(baseStoragePath, 'uploads');
const catDirPath = path.join(baseStoragePath, 'catalogos');
const tempDir = path.join(baseStoragePath, 'temp');
const productosDirPath = path.join(baseStoragePath, 'productos');
const asesoresDirPath = path.join(baseStoragePath, 'asesores');
const clientesDirPath = path.join(baseStoragePath, 'clientes');
const correosDirPath = path.join(baseStoragePath, 'correos');
const ordenesPath = path.join(baseStoragePath, 'ordenes');
const imagenesDir = path.join(baseStoragePath, 'imagenesProductos');

if (!fs.existsSync(ordenesPath)) {
  fs.mkdirSync(ordenesPath, { recursive: true });
}

if (!fs.existsSync(imagenesDir)) {
  fs.mkdirSync(imagenesDir, { recursive: true });
}

if (fs.existsSync(baseStoragePath)) {
  [uploadDir, catDirPath, tempDir, productosDirPath, asesoresDirPath, 
   clientesDirPath, correosDirPath, ordenesPath, imagenesDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      try {
        fs.mkdirSync(dir, { recursive: true });
        console.log(`Carpeta creada: ${dir}`);
      } catch (error) {
        console.error(`Error al crear carpeta ${dir}: ${error.message}`);
      }
    }
  });
}
function limpiarArchivosTemporales() {
  try {
    console.log('Limpiando archivos temporales...');
    
    if (fs.existsSync(tempDir)) {
      const archivos = fs.readdirSync(tempDir);
      let eliminados = 0;
      
      archivos.forEach(archivo => {
        try {
          fs.unlinkSync(path.join(tempDir, archivo));
          eliminados++;
        } catch (err) {
          console.error(`Error al eliminar archivo temporal: ${archivo}`, err);
        }
      });
      
      console.log(`Limpieza completada: ${eliminados} archivos temporales eliminados`);
    }
  } catch (error) {
    console.error('Error al limpiar temporales:', error);
  }
}

// Ejecutar al inicio
limpiarArchivosTemporales();

 console.log('=== Configuración del sistema de archivos ===');
console.log(`Modo: ${isProduction ? 'Producción' : 'Desarrollo'}`);
console.log(`Ruta base de almacenamiento: ${baseStoragePath}`);
console.log(`Carpeta de uploads: ${uploadDir}`);
console.log(`Carpeta de catálogos: ${catDirPath}`);
console.log(`Carpeta de productos: ${productosDirPath}`);
console.log(`Carpeta de asesores: ${asesoresDirPath}`);
console.log(`Carpeta de clientes: ${clientesDirPath}`);
console.log(`Carpeta de correos: ${correosDirPath}`);
console.log(`Carpeta de órdenes: ${ordenesPath}`);
console.log(`Carpeta de imágenes: ${imagenesDir}`);

const imagenesStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    if (canWriteToPath(imagenesDir)) {
      cb(null, imagenesDir);
    } else {
      // Si no podemos escribir, usar /tmp como fallback
      cb(null, tempDir);
    }
  },
  filename: function (req, file, cb) {
    // Mantener el nombre original del archivo
    cb(null, file.originalname);
  }
});

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    if (canWriteToPath(uploadDir)) {
      cb(null, uploadDir);
    } else {
      // Si no podemos escribir, usar /tmp como fallback
      cb(null, tempDir);
    }
  },
  filename: function (req, file, cb) {
    if (file.fieldname === 'catalogo') {
      cb(null, 'catalogo.pdf');
    } else if (file.fieldname === 'productos') {
      cb(null, 'productos.csv');
    } else if (file.fieldname === 'asesores') {
      cb(null, 'asesores.csv');
    } else if (file.fieldname === 'clientes') {
      cb(null, 'clientes.csv');
    } else if (file.fieldname === 'correos') {
      cb(null, 'correos.csv');
    } else {
      cb(null, file.originalname);
    }
  }
});

const catalogoStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    // Asegurarse de que el directorio existe
    if (!fs.existsSync(catDirPath)) {
      fs.mkdirSync(catDirPath, { recursive: true });
      console.log(`Directorio de catálogos creado: ${catDirPath}`);
    }
    
    console.log(`Guardando catálogo en: ${catDirPath}`);
    cb(null, catDirPath);
  },
  filename: function (req, file, cb) {
    // Usar un nombre único basado en timestamp para evitar conflictos
    const tempFilename = `catalogo_temp_${Date.now()}.pdf`;
    console.log(`Nombre temporal para archivo: ${tempFilename}`);
    cb(null, tempFilename);
  }
});
const uploadCatalogo = multer({
  storage: catalogoStorage,
  limits: {
    fileSize: UPLOAD_FILE_SIZE_LIMIT // Límite de 300MB
  }
});

const uploadImagenes = multer({ 
  storage: imagenesStorage,
  fileFilter: function(req, file, cb) {
    if (!file.originalname.match(/\.jpe?g$/i)) {
      return cb(new Error('Solo se permiten archivos JPG/JPEG'), false);
    }
    cb(null, true);
  },
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB por archivo
    files: 100 // Permitir hasta 100 archivos por solicitud
  }
});


// Intentar cargar el contador desde un archivo
if (canWriteToPath(ordenesPath)) {
  try {
    const contadorPath = path.join(ordenesPath, 'contador.json');
    if (fs.existsSync(contadorPath)) {
      const data = fs.readFileSync(contadorPath, 'utf8');
      const contador = JSON.parse(data);
      // Solo asignar el valor, NO incrementar
      ultimoNumeroOrden = contador.ultimoNumero || 1;
      console.log(`Contador de órdenes cargado: ${ultimoNumeroOrden}`);
    } else {
      // Crear el archivo si no existe, con el valor 1 (no incrementado)
      fs.writeFileSync(contadorPath, JSON.stringify({ ultimoNumero: 1, fechaActualizacion: new Date().toISOString() }, null, 2));
      ultimoNumeroOrden = 1;
      console.log(`Archivo de contador creado con valor inicial: 1`);
    }
  } catch (error) {
    console.error('Error al cargar el contador de órdenes:', error);
  }
}

function moveFile(sourcePath, destPath) {
  return new Promise((resolve, reject) => {
    const readStream = fs.createReadStream(sourcePath);
    const writeStream = fs.createWriteStream(destPath);
    
    readStream.on('error', err => {
      reject(err);
    });
    
    writeStream.on('error', err => {
      reject(err);
    });
    
    writeStream.on('finish', () => {
      // Eliminar archivo temporal
      try {
        fs.unlinkSync(sourcePath);
      } catch (err) {
        console.error('Error al eliminar archivo temporal:', err);
      }
      resolve();
    });
    
    readStream.pipe(writeStream);
  });
}


app.use(session(sessionConfig));
app.use('/api/productos/imagenes', express.static(imagenesDir));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Función adaptada para subir archivos PDF grandes
function uploadPdfInChunks() {
  console.log("Iniciando subida de PDF por fragmentos");
  
  const fileInput = document.getElementById('catalogo');
  const file = fileInput.files[0];
  
  if (!file) {
      console.log("No se seleccionó ningún archivo");
      showAlert('alertError', 'Por favor seleccione un archivo PDF.');
      return;
  }

  console.log(`Se seleccionó el archivo: ${file.name}, tamaño: ${formatFileSize(file.size)}`);
  
  // Verificar que sea un PDF
  if (file.type !== 'application/pdf') {
      console.log(`Error: El archivo ${file.name} no es un PDF`);
      showAlert('alertError', `El archivo ${file.name} no es un PDF válido.`);
      return;
  }
  
  // Mostrar alerta inicial
  showAlert('alertInfo', `Preparando subida de archivo grande (${formatFileSize(file.size)})...`, 'info', false);
  document.getElementById('progressContainer').style.display = 'block';
  document.getElementById('progressBar').style.width = '0%';
  document.getElementById('progressText').textContent = '0%';

  // Crear un objeto FormData para la solicitud
  const formData = new FormData();
  formData.append('catalogo', file);
  
  // Subir usando XMLHttpRequest para tener barra de progreso
  const xhr = new XMLHttpRequest();
  
  // Configurar evento de progreso
  xhr.upload.addEventListener('progress', function(event) {
      if (event.lengthComputable) {
          const percentComplete = Math.round((event.loaded / event.total) * 100);
          
          // Actualizar barra de progreso
          document.getElementById('progressBar').style.width = percentComplete + '%';
          document.getElementById('progressText').textContent = percentComplete + '%';
          
          // Actualizar texto de la alerta
          document.getElementById('alertInfo').innerHTML = 
              `Subiendo archivo grande (${formatFileSize(file.size)}), por favor espere... (${percentComplete}%)
              <div id="progressContainer" class="progress-container" style="display: block; margin-top: 10px;">
                  <div id="progressBar" class="progress-bar" style="width: ${percentComplete}%"></div>
                  <div id="progressText" class="progress-text">${percentComplete}%</div>
              </div>
              <div style="margin-top: 8px; font-size: 13px; color: #666;">
                  Esta operación puede tardar varios minutos dependiendo de su conexión.<br>
                  No cierre esta ventana hasta que la subida se complete.
              </div>`;
          
          // Agregar botón de cancelar si no existe
          if (!document.getElementById('cancelUploadBtn')) {
              const cancelButton = document.createElement('button');
              cancelButton.id = 'cancelUploadBtn';
              cancelButton.textContent = 'Cancelar';
              cancelButton.className = 'btn';
              cancelButton.style.marginTop = '10px';
              cancelButton.style.backgroundColor = '#dc3545';
              cancelButton.onclick = function() {
                  xhr.abort();
                  hideAlert('alertInfo');
                  document.getElementById('progressContainer').style.display = 'none';
                  showAlert('alertError', 'Subida cancelada por el usuario');
              };
              document.getElementById('alertInfo').appendChild(document.createElement('br'));
              document.getElementById('alertInfo').appendChild(cancelButton);
          }
          
          console.log(`Progreso: ${percentComplete}%`);
      }
  });
  
  // Configurar evento de finalización
  xhr.addEventListener('load', function() {
      // Limpiar botón de cancelar si existe
      const cancelBtn = document.getElementById('cancelUploadBtn');
      if (cancelBtn) {
          cancelBtn.parentNode.removeChild(cancelBtn);
      }
      
      if (xhr.status >= 200 && xhr.status < 300) {
          try {
              const data = JSON.parse(xhr.responseText);
              console.log(`Respuesta del servidor:`, data);
              
              // Ocultar la alerta de información y la barra de progreso
              hideAlert('alertInfo');
              document.getElementById('progressContainer').style.display = 'none';
              
              if (data.success) {
                  showAlert('alertSuccess', `¡El archivo de catálogo ha sido actualizado correctamente!`);
                  // Actualizar la información del último archivo subido
                  document.getElementById('catalogoNombre').textContent = `Último archivo subido: ${file.name}`;
                  // Resetear el formulario
                  document.getElementById('catalogo').value = '';
              } else {
                  showAlert('alertError', data.message || `Error al actualizar el archivo de catálogo.`);
              }
          } catch (error) {
              console.error('Error al procesar la respuesta:', error);
              hideAlert('alertInfo');
              document.getElementById('progressContainer').style.display = 'none';
              showAlert('alertError', 'Error al procesar la respuesta del servidor.');
          }
      } else {
          console.error('Error en la solicitud:', xhr.status, xhr.statusText);
          hideAlert('alertInfo');
          document.getElementById('progressContainer').style.display = 'none';
          showAlert('alertError', `Error en la solicitud: ${xhr.status} ${xhr.statusText}`);
      }
  });
  
  // Configurar evento de error
  xhr.addEventListener('error', function() {
      console.error('Error de red al enviar la solicitud');
      hideAlert('alertInfo');
      document.getElementById('progressContainer').style.display = 'none';
      showAlert('alertError', 'Error de red al enviar la solicitud. Compruebe su conexión.');
  });
  
  // Configurar evento de timeout
  xhr.addEventListener('timeout', function() {
      console.error('Tiempo de espera agotado');
      hideAlert('alertInfo');
      document.getElementById('progressContainer').style.display = 'none';
      showAlert('alertError', 'Tiempo de espera agotado. El servidor tardó demasiado en responder.');
  });
  
  // Establecer un timeout largo para archivos grandes
  xhr.timeout = 3600000; // 1 hora
  
  // Abrir y enviar la solicitud
  xhr.open('POST', '/upload-catalogo');
  xhr.send(formData);
}


function guardarContador() {
  try {
    const contadorPath = path.join(ordenesPath, 'contador.json');
    console.log(`Guardando contador con valor: ${ultimoNumeroOrden}`);
    
    // Asegurémonos de que la carpeta existe
    if (!fs.existsSync(ordenesPath)) {
      fs.mkdirSync(ordenesPath, { recursive: true });
      console.log(`Creada carpeta ordenesPath: ${ordenesPath}`);
    }
    
    // Guardar con formato más legible
    fs.writeFileSync(contadorPath, JSON.stringify({ 
      ultimoNumero: ultimoNumeroOrden,
      fechaActualizacion: new Date().toISOString() 
    }, null, 2));
    
    // Verificar que se guardó correctamente
    const contenido = fs.readFileSync(contadorPath, 'utf8');
    console.log('Contenido del archivo después de guardar:', contenido);
    
    // Crear un backup por seguridad
    fs.writeFileSync(path.join(ordenesPath, 'contador_backup.json'), contenido);
  } catch (error) {
    console.error('Error al guardar el contador de órdenes:', error);
    console.error('Ruta del contador:', path.join(ordenesPath, 'contador.json'));
  }
}

function canWriteToPath(dirPath) {
  try {
    // Intenta crear un archivo temporal para ver si tenemos permisos de escritura
    const testFile = path.join(dirPath, '.write-test');
    fs.writeFileSync(testFile, 'test');
    fs.unlinkSync(testFile); // Eliminar el archivo de prueba
    return true;
  } catch (err) {
    console.log(`No se puede escribir en ${dirPath}: ${err.message}`);
    return false;
  }
}

function verificarPassword(password) {
  // Comparación directa con la contraseña en texto plano
  return password === process.env.ADMIN_PASSWORD;
}


function requireAuth(req, res, next) {
  console.log("Cookies recibidas:", req.headers.cookie);
  console.log("Sesión completa:", req.session);
  console.log("Verificando autenticación para:", req.path);
  console.log("Estado de autenticación:", req.session.authenticated);
  
  if (req.session && req.session.authenticated === true) {
    console.log("Autenticación exitosa, procediendo");
    return next();
  } else {
    console.log("Autenticación fallida, redirigiendo a login");
    return res.redirect('/login');
  }
}

app.use(session({
  secret: process.env.SESSION_SECRET || 'dap-autoparts-secret-key',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: false, // Cambiar a true si usas HTTPS
    maxAge: 3600000 // 1 hora
  }
}));


app.get('/login', (req, res) => {
  console.log("Acceso a página de login");
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// Procesamiento de login
app.post('/login', (req, res) => {
  const username = req.body.username;
  const password = req.body.password;
  
  console.log("Intento de login para usuario:", username);
  
  if (username === ADMIN_USERNAME && verificarPassword(password)) {
    console.log("Login exitoso");
    req.session.authenticated = true;
    res.redirect('/admin');
  } else {
    console.log("Login fallido");
    res.status(401).send(`
      <html>
        <head>
          <title>Error de autenticación</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 0; padding: 20px; text-align: center; }
            .error { color: red; margin-bottom: 20px; }
            .btn { padding: 10px 20px; background-color: #1A4379; color: white; border: none; border-radius: 5px; cursor: pointer; }
          </style>
        </head>
        <body>
          <h2>Error de autenticación</h2>
          <p class="error">Usuario o contraseña incorrectos</p>
          <a href="/login" class="btn">Volver a intentar</a>
        </body>
      </html>
    `);
  }
});

// Ruta de logout
app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// PROTEGER LAS RUTAS DE ADMINISTRACIÓN - REEMPLAZA LA RUTA ORIGINAL
// Ruta de admin
app.get('/admin', requireAuth, (req, res) => {
  console.log("Acceso exitoso a admin");
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.get('/siguiente-orden', (req, res) => {
  try {
    // Formatear el número que SERÍA el siguiente (pero sin incrementar todavía)
    const numeroFormateado = `OP-${(ultimoNumeroOrden + 1).toString().padStart(5, '0')}`;
    
    console.log(`Consultando próximo número de orden: ${numeroFormateado}`);
    
    // Devolver el número formateado y el valor numérico
    res.json({
      success: true,
      numeroOrden: numeroFormateado,
      valor: ultimoNumeroOrden + 1  // Valor que sería, pero no lo guardamos todavía
    });
  } catch (error) {
    console.error('Error al consultar próximo número de orden:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


app.post('/confirmar-orden', (req, res) => {
  try {
    const { numeroOrden } = req.body;
    
    if (!numeroOrden) {
      return res.status(400).json({ 
        success: false, 
        message: 'Falta el número de orden' 
      });
    }
    
    console.log(`Confirmando uso del número de orden: ${numeroOrden}`);
    
    // Leer el valor actual directamente del disco
    const valorActual = leerContador();
    console.log(`Valor leído del contador antes de incrementar: ${valorActual}`);
    
    // Incrementar el contador
    const nuevoValor = valorActual + 1;
    
    // ❗ IMPORTANTE: Guardar de inmediato para evitar condiciones de carrera
    const guardadoExitoso = guardarContadorDisco(nuevoValor);
    
    if (guardadoExitoso) {
      // Actualizar también la variable en memoria
      ultimoNumeroOrden = nuevoValor;
      
      console.log(`Contador incrementado exitosamente a: ${nuevoValor}`);
      
      // Registrar la operación para tener constancia del incremento
      try {
        const registroPath = path.join(ordenesPath, 'registro_operaciones.json');
        let registro = [];
        
        if (fs.existsSync(registroPath)) {
          const data = fs.readFileSync(registroPath, 'utf8');
          registro = JSON.parse(data);
        }
        
        registro.push({
          operacion: 'confirmar_orden',
          numeroOrden: numeroOrden,
          valorAnterior: valorActual,
          valorNuevo: nuevoValor,
          fecha: new Date().toISOString(),
          ip: req.ip
        });
        
        fs.writeFileSync(registroPath, JSON.stringify(registro, null, 2));
      } catch (e) {
        console.error(`Error al guardar registro: ${e}`);
      }
      
      res.json({
        success: true,
        message: 'Orden confirmada y contador incrementado correctamente',
        valorAnterior: valorActual,
        nuevoValor: nuevoValor
      });
    } else {
      res.status(500).json({
        success: false,
        message: 'No se pudo guardar el nuevo valor del contador',
        valorActual: valorActual
      });
    }
  } catch (error) {
    console.error(`Error en confirmar-orden: ${error}`);
    res.status(500).json({
      success: false,
      message: error.toString()
    });
  }
});

function registrarOrdenEnviada(numeroOrden, clienteNombre, clienteEmail, asesorEmail) {
  try {
    const ordenesRegistroPath = path.join(ordenesPath, 'ordenes_enviadas.json');
    let ordenesEnviadas = [];
    
    // Cargar registro existente si existe
    if (fs.existsSync(ordenesRegistroPath)) {
      try {
        const data = fs.readFileSync(ordenesRegistroPath, 'utf8');
        ordenesEnviadas = JSON.parse(data);
      } catch (e) {
        console.error("Error al leer registro de órdenes enviadas:", e);
        // Continuar con array vacío si hay error
      }
    }
    
    // Agregar la nueva orden al registro
    ordenesEnviadas.push({
      numeroOrden: numeroOrden,
      fecha: new Date().toISOString(),
      cliente: clienteNombre || clienteEmail,
      asesor: asesorEmail
    });
    
    // Guardar el registro actualizado
    fs.writeFileSync(ordenesRegistroPath, JSON.stringify(ordenesEnviadas, null, 2));
    console.log(`✅ Orden ${numeroOrden} registrada exitosamente en historial`);
    return true;
  } catch (error) {
    console.error("❌ Error al registrar orden enviada:", error);
    return false;
  }
}
function verificarOrdenDuplicada(numeroOrden) {
  try {
    const ordenesRegistroPath = path.join(ordenesPath, 'ordenes_enviadas.json');
    
    if (!fs.existsSync(ordenesRegistroPath)) {
      return false; // No hay registro, no puede estar duplicada
    }
    
    const data = fs.readFileSync(ordenesRegistroPath, 'utf8');
    const ordenesEnviadas = JSON.parse(data);
    
    // Verificar si este número ya fue usado
    return ordenesEnviadas.some(o => o.numeroOrden === numeroOrden);
  } catch (error) {
    console.error("Error al verificar orden duplicada:", error);
    return false; // En caso de error, permitir continuar
  }
}

app.post('/upload-imagenes', requireAuth, (req, res) => {
  // Usar el middleware de multer directamente en la ruta
  uploadImagenes.array('imagenes', 100)(req, res, function(err) {
    if (err) {
      console.error('Error en la subida de imágenes:', err);
      if (err instanceof multer.MulterError) {
        if (err.code === 'LIMIT_FILE_COUNT') {
          return res.status(400).json({ 
            success: false, 
            message: 'Demasiados archivos en un solo lote. Máximo 100 por lote.' 
          });
        } else if (err.code === 'LIMIT_UNEXPECTED_FILE') {
          return res.status(400).json({ 
            success: false, 
            message: 'Campo inesperado. Asegúrate de usar "imagenes" como nombre de campo.' 
          });
        }
      }
      return res.status(500).json({ 
        success: false, 
        message: `Error al subir imágenes: ${err.message}` 
      });
    }
    
    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'No se han subido imágenes' 
      });
    }

    console.log(`Directorio de imágenes: ${imagenesDir}`);
    console.log(`¿El directorio existe? ${fs.existsSync(imagenesDir)}`);
    
    // Obtener los nombres de los archivos subidos y sus rutas completas
    const fileInfo = req.files.map(file => ({
      filename: file.originalname,
      path: file.path
    }));
    
    console.log(`Información detallada de archivos subidos:`, fileInfo);

    // Obtener los nombres de los archivos subidos
    const filenames = req.files.map(file => file.originalname);
    
    console.log(`Se han subido ${req.files.length} imágenes: ${filenames.join(', ')}`);
    
    res.json({ 
      success: true, 
      message: 'Imágenes subidas correctamente', 
      count: req.files.length,
      filenames: filenames
    });
  });
});

// Endpoint para obtener información sobre las imágenes disponibles
app.get('/imagenes-info', (req, res) => {
  try {
    // Leer el directorio de imágenes
    const files = fs.readdirSync(imagenesDir).filter(file => 
      file.endsWith('.jpg')
    );
    
    res.json({
      success: true,
      count: files.length,
      filenames: files
    });
  } catch (error) {
    console.error('Error al obtener info de imágenes:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


const upload = multer({ storage: storage });

// Transportador de correo
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS
  }
});

// Función para procesar CSV de correos de área
function procesarCsvCorreos(filePath) {
  try {
    // Leer el archivo completo
    const buffer = fs.readFileSync(filePath);
    // Convertir de Latin1/Windows-1252 a UTF-8
    const fileContent = iconv.decode(buffer, 'win1252');
    
    // Dividir por líneas
    const lines = fileContent.split('\n');
    
    // Buscar la línea de encabezados en las primeras 10 filas
    let headerRowIndex = -1;
    for (let i = 0; i < Math.min(10, lines.length); i++) {
      const line = lines[i].toUpperCase();
      if (line.includes('AREA') && line.includes('MAIL')) {
        headerRowIndex = i;
        break;
      }
    }
    
    // Si no se encuentra, usar la primera fila como predeterminada
    if (headerRowIndex === -1) {
      headerRowIndex = 0;
    }
    
    // Extraer encabezados
    const headerLine = lines[headerRowIndex];
    const headers = dividirCSV(headerLine);
    
    // Buscar posiciones de las columnas
    const AREA_INDEX = encontrarIndice(headers, ['AREA', 'DEPARTAMENTO', 'SECCION']);
    const MAIL_INDEX = encontrarIndice(headers, ['MAIL', 'EMAIL', 'CORREO']);
    
    const correos = [];
    
    // Variable para marcar cuando encontramos la primera fila de asesores
    let encontradoAsesores = false;
    
    for (let i = headerRowIndex + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue; // Saltar líneas vacías
      
      try {
        const campos = dividirCSV(line);
        
        // Saltar si no hay correo
        if (campos.length <= MAIL_INDEX || !campos[MAIL_INDEX].trim()) {
          continue;
        }
        
        const area = (AREA_INDEX >= 0 && AREA_INDEX < campos.length) ? campos[AREA_INDEX].trim().toUpperCase() : '';
        const mail = campos[MAIL_INDEX].trim();
        
        // Si encontramos "ASESOR QUE GENERA EL PEDIDO", marcamos que empiezan los asesores
        if (area === 'ASESOR QUE GENERA EL PEDIDO') {
          encontradoAsesores = true;
          continue; // Saltar esta fila
        }
        
        // Si ya encontramos la sección de asesores, saltamos todas las filas siguientes
        if (encontradoAsesores) {
          continue;
        }
        
        // Solo incluimos filas antes de la sección de asesores
        if (mail) {
          correos.push({
            AREA: area,
            MAIL: mail
          });
        }
      } catch (parseError) {
        console.error(`Error al procesar línea ${i+1}:`, parseError);
      }
    }

    return correos;
  } catch (error) {
    console.error('Error al procesar CSV de correos:', error);
    return [];
  }
}
app.post('/admin/ajustar-contador', requireAuth, (req, res) => {
  try {
    const { valor } = req.body;
    
    if (!valor || isNaN(parseInt(valor))) {
      return res.status(400).json({ success: false, message: 'Se requiere un valor numérico válido' });
    }
    
    ultimoNumeroOrden = parseInt(valor);
    guardarContador();
    
    res.json({ 
      success: true, 
      message: `Contador ajustado a: ${ultimoNumeroOrden}`,
      nuevoContador: ultimoNumeroOrden
    });
  } catch (error) {
    console.error('Error al ajustar contador:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

app.get('/correos-info', (req, res) => {
  try {
    const correosPath = path.join(correosDirPath, 'correos.csv');
    
    if (fs.existsSync(correosPath)) {
      const stats = fs.statSync(correosPath);
      const fileDate = new Date(stats.mtime);
      
      // Obtener metadatos si existen
      const metadata = leerMetadatosArchivo('correos');
      const nombreOriginal = metadata ? metadata.nombreOriginal : 'correos.csv';
      
      res.json({
        success: true,
        filename: nombreOriginal,
        size: stats.size,
        lastModified: fileDate.toLocaleString()
      });
    } else {
      res.json({
        success: false,
        message: 'No hay archivo de correos disponible'
      });
    }
  } catch (error) {
    console.error('Error al obtener info de correos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener todos los correos
app.get('/correos', (req, res) => {
  try {
    const correosPath = path.join(correosDirPath, 'correos.csv');
    
    if (!fs.existsSync(correosPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El archivo de correos no está disponible' 
      });
    }
    
    const correos = procesarCsvCorreos(correosPath);
    res.json({ 
      success: true, 
      correos: correos,
      total: correos.length
    });
  } catch (error) {
    console.error('Error al obtener correos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Subir un nuevo archivo de correos
app.post('/upload-correos', requireAuth, upload.single('correos'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(correosDirPath, 'correos.csv');
    const nombreOriginal = req.file.originalname; // Nombre original del archivo

    // Validar el formato CSV antes de guardarlo
    try {
      // Verificar que podemos procesar el archivo
      const correos = procesarCsvCorreos(sourcePath);
      
      if (correos.length === 0) {
        return res.status(400).json({ 
          success: false, 
          message: 'El archivo CSV no contiene correos válidos o tiene un formato incorrecto' 
        });
      }
      
      console.log(`CSV de correos validado correctamente con ${correos.length} correos`);
    } catch (error) {
      return res.status(400).json({ 
        success: false, 
        message: `Error al validar CSV de correos: ${error.message}` 
      });
    }

    // Si el archivo es válido, guardarlo
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath);
    
    // Guardar metadatos con el nombre original
    guardarMetadatosArchivo('correos', nombreOriginal);

    res.json({ success: true, message: 'Archivo de correos actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de correos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


// Endpoint para enviar correo
// Endpoint para enviar correo
app.post('/send-email', upload.single('pdf'), async (req, res) => {
  let pdfPath = null;

  try {
    const { clienteEmail, asesorEmail, asunto, cuerpo } = req.body;
    const clienteNombre = req.body.clienteNombre || ''; // Nombre del cliente
    const ordenNumero = req.body.ordenNumero || ''; // Número de orden
    pdfPath = req.file.path;

    if (!clienteEmail) {
      return res.status(400).json({ success: false, message: 'Falta el correo del cliente' });
    }
    
    // NUEVO: Verificar si este número de orden ya se usó antes
    if (ordenNumero && verificarOrdenDuplicada(ordenNumero)) {
      console.warn(`⚠️ ALERTA: Intento de envío con número de orden duplicado: ${ordenNumero}`);
      
      // Generar un nuevo número para evitar duplicados
      const nuevoNumero = leerContador() + 1;
      const nuevoNumeroFormateado = `OP-${nuevoNumero.toString().padStart(5, '0')}`;
      guardarContadorDisco(nuevoNumero);
      
      return res.status(409).json({
        success: false,
        message: `El número de orden ${ordenNumero} ya fue utilizado previamente.`,
        nuevoNumero: nuevoNumeroFormateado
      });
    }

    // Obtener la lista de correos por área 
    const correosPath = path.join(correosDirPath, 'correos.csv');
    let destinatariosPrincipales = [];
    
    if (fs.existsSync(correosPath)) {
      try {
        const correosPorArea = procesarCsvCorreos(correosPath);
        
        // Log detallado para depuración
        console.log("Correos encontrados en el CSV:", correosPorArea);
        
        // Filtrar correos válidos y eliminar espacios en blanco
        destinatariosPrincipales = correosPorArea
          .filter(c => c.MAIL && typeof c.MAIL === 'string' && c.MAIL.includes('@'))
          .map(c => c.MAIL.trim());
        
        console.log("Destinatarios filtrados y validados:", destinatariosPrincipales);
      } catch (e) {
        console.error("Error al procesar correos de áreas:", e);
        console.error("Detalle del error:", e.stack);
      }
    } else {
      console.log("Archivo de correos no encontrado en:", correosPath);
    }
    
    // Incluir al asesor en la lista si no está ya
    if (asesorEmail && asesorEmail.trim() && !destinatariosPrincipales.includes(asesorEmail.trim())) {
      destinatariosPrincipales.push(asesorEmail.trim());
    }
    
    // Si no hay destinatarios configurados, usar el correo del asesor como destinatario principal
    if (destinatariosPrincipales.length === 0) {
      console.log("No se encontraron destinatarios en correos.csv, usando correo del asesor como principal");
      if (asesorEmail && asesorEmail.trim()) {
        destinatariosPrincipales = [asesorEmail.trim()];
      } else {
        // Si no hay asesor ni destinatarios, usar el correo del cliente como principal
        destinatariosPrincipales = [clienteEmail.trim()];
      }
    }
    
    // Lista de CC (el cliente va en CC)
    let ccList = [];
    
    // Agregar el cliente en CC (si hay un correo válido)
    if (clienteEmail && clienteEmail.trim()) {
      ccList.push(clienteEmail.trim());
    }
    
    // Filtrar duplicados y valores vacíos
    destinatariosPrincipales = [...new Set(destinatariosPrincipales.filter(email => email && email.trim()))];
    ccList = [...new Set(ccList.filter(email => email && email.trim()))];
    
    console.log("Lista final de destinatarios:", destinatariosPrincipales);
    console.log("Lista final de CC:", ccList);

    // Formatear el asunto con el número de orden y nombre del cliente
    const asuntoFormateado = ordenNumero ? 
      `Orden de pedido ${ordenNumero}${clienteNombre ? `, ${clienteNombre}` : ''}` : 
      (asunto || 'Orden de Pedido - DAP AutoPart\'s');

    const mailOptions = {
      from: '"DAP AutoPart\'s" <' + process.env.EMAIL_USER + '>',
      to: destinatariosPrincipales.join(', '),
      cc: ccList.join(', '),
      subject: asuntoFormateado,
      text: cuerpo || `Cordial saludo.
    
    Se adjunta orden de pedido #${ordenNumero} del cliente ${clienteNombre}.
    
    Por su colaboración mil gracias.
    
    Cordialmente,
    
    ${asesorEmail ? asesorEmail.split('@')[0] : 'Asesor'}
    Asesor comercial 
    Distribuciones AutoPart's SAS`,
      attachments: [
        {
          filename: path.basename(pdfPath),
          path: pdfPath
        }
      ]
    };

    console.log("Enviando correo con las siguientes opciones:");
    console.log("- De:", mailOptions.from);
    console.log("- Para:", mailOptions.to);
    console.log("- CC:", mailOptions.cc);
    console.log("- Asunto:", mailOptions.subject);
    
    try {
      const info = await transporter.sendMail(mailOptions);
      console.log("✅ Correo enviado exitosamente:", info.messageId);
      
      // Registrar la orden como enviada
      if (ordenNumero) {
        registrarOrdenEnviada(ordenNumero, clienteNombre, clienteEmail, asesorEmail);
      }
      
    } catch (emailError) {
      console.error("❌ Error al enviar correo:", emailError);
      throw emailError;
    }
    
    fs.unlinkSync(pdfPath);
    
    res.json({
      success: true,
      message: 'Correo enviado correctamente',
      contadorActual: ultimoNumeroOrden,
      // Incluir todos los destinatarios para que la app los muestre
      destinatarios: destinatariosPrincipales,
      cc: ccList
    });
  } catch (error) {
    console.error('Error al enviar correo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

  function guardarMetadatosArchivo(tipo, nombreOriginal) {
    try {
      const metadataPath = path.join(baseStoragePath, `${tipo}_metadata.json`);
      const metadata = {
        nombreOriginal: nombreOriginal,
        fechaSubida: new Date().toISOString()
      };
      
      fs.writeFileSync(metadataPath, JSON.stringify(metadata, null, 2));
      console.log(`Metadatos guardados para ${tipo}: ${nombreOriginal}`);
      return true;
    } catch (error) {
      console.error(`Error al guardar metadatos para ${tipo}:`, error);
      return false;
    }
  }

  function leerMetadatosArchivo(tipo) {
    try {
      const metadataPath = path.join(baseStoragePath, `${tipo}_metadata.json`);
      if (fs.existsSync(metadataPath)) {
        const data = fs.readFileSync(metadataPath, 'utf8');
        return JSON.parse(data);
      }
      return null;
    } catch (error) {
      console.error(`Error al leer metadatos para ${tipo}:`, error);
      return null;
    }
  }

  function procesarCsvClientes(filePath) {
    try {
      // Leer el archivo como buffer binario
      const buffer = fs.readFileSync(filePath);
      
      // Probar diferentes encodings para encontrar el mejor
      const encodingsToTry = ['utf8', 'win1252', 'latin1', 'iso-8859-1'];
      let fileContent = '';
      let bestEncoding = '';
      let minErrorCount = Infinity;
      
      for (const encoding of encodingsToTry) {
        try {
          const testContent = iconv.decode(buffer, encoding);
          // Contar caracteres problemáticos
          const errorCount = (testContent.match(/�/g) || []).length;
          
          if (errorCount < minErrorCount) {
            minErrorCount = errorCount;
            fileContent = testContent;
            bestEncoding = encoding;
            
            // Si no hay errores, usar este encoding inmediatamente
            if (errorCount === 0) break;
          }
        } catch (e) {
          console.log(`Error al decodificar con ${encoding}`);
        }
      }
      
      console.log(`Usando encoding ${bestEncoding} para CSV de clientes`);
      
      // Dividir por líneas
      const lines = fileContent.split('\n');
      
      // Buscar la línea de encabezados en las primeras 10 filas
      let headerRowIndex = -1;
      for (let i = 0; i < Math.min(10, lines.length); i++) {
        const line = lines[i].toUpperCase();
        if (line.includes('NIT')) {
          headerRowIndex = i;
          break;
        }
      }
      
      if (headerRowIndex === -1) headerRowIndex = 0;
      
      // Extraer encabezados
      const headerLine = lines[headerRowIndex];
      const headers = dividirCSV(headerLine);
      
      // Buscar posiciones de las columnas clave
      const NIT_INDEX = encontrarIndice(headers, ['NIT', 'NIT CLIENTE', 'NITCLIENTE', 'ID']);
      const NOMBRE_INDEX = encontrarIndice(headers, ['NOMBRE', 'RAZON SOCIAL', 'RAZONSOCIAL', 'CLIENTE']);
      const ESTABLECIMIENTO_INDEX = encontrarIndice(headers, ['ESTABLECIMIENTO', 'NEGOCIO', 'LOCAL']);
      const DIRECCION_INDEX = encontrarIndice(headers, ['DIRECCION', 'DIRECCIÓN', 'DIRECCIÒN', 'DIR']);
      const TELEFONO_INDEX = encontrarIndice(headers, ['TELEFONO', 'TELÉFONO', 'TEL', 'CELULAR']);
      const DESCTO_INDEX = encontrarIndice(headers, ['DESCTO', 'DESCUENTO', 'DCTO', 'DESC']);
      const CIUDAD_INDEX = encontrarIndice(headers, ['CIUDAD', 'CLI_CIUDAD', 'CITY']);
      const EMAIL_INDEX = encontrarIndice(headers, ['EMAIL', 'CORREO', 'CLI_EMAIL', 'MAIL']);
      const ID_ASESOR_INDEX = encontrarIndice(headers, ['ID ASESOR', 'IDASESOR', 'ASESOR ID', 'ASESOR']);
      
      // Procesar las líneas de datos 
      const clientes = [];
      
      for (let i = headerRowIndex + 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue; // Saltar líneas vacías
        
        try {
          // Dividir la línea considerando comillas
          const campos = dividirCSV(line);
          
          // Saltar la línea si no hay suficientes columnas
          if (campos.length < 2) continue;
          
          // Crear objeto cliente con los campos básicos
          const cliente = {};
          
          // NIT - requerido
          if (NIT_INDEX >= 0 && NIT_INDEX < campos.length) {
            cliente['NIT CLIENTE'] = campos[NIT_INDEX].trim();
            if (!cliente['NIT CLIENTE']) continue;
          } else {
            continue; // Sin NIT válido no procesamos
          }
          
          // Resto de campos
          if (NOMBRE_INDEX >= 0 && NOMBRE_INDEX < campos.length) {
            cliente['NOMBRE'] = campos[NOMBRE_INDEX].trim();
          } else {
            cliente['NOMBRE'] = `Cliente ${cliente['NIT CLIENTE']}`;
          }
          
          if (ESTABLECIMIENTO_INDEX >= 0 && ESTABLECIMIENTO_INDEX < campos.length) {
            cliente['ESTABLECIMIENTO'] = campos[ESTABLECIMIENTO_INDEX].trim();
          } else {
            cliente['ESTABLECIMIENTO'] = '';
          }
          
          if (DIRECCION_INDEX >= 0 && DIRECCION_INDEX < campos.length) {
            cliente['DIRECCION'] = campos[DIRECCION_INDEX].trim();
          } else {
            cliente['DIRECCION'] = '';
          }
          
          if (TELEFONO_INDEX >= 0 && TELEFONO_INDEX < campos.length) {
            cliente['TELEFONO'] = campos[TELEFONO_INDEX].trim();
          } else {
            cliente['TELEFONO'] = '';
          }
          
          if (DESCTO_INDEX >= 0 && DESCTO_INDEX < campos.length) {
            cliente['DESCTO'] = campos[DESCTO_INDEX].trim();
          } else {
            cliente['DESCTO'] = '';
          }
          
          if (CIUDAD_INDEX >= 0 && CIUDAD_INDEX < campos.length) {
            cliente['CLI_CIUDAD'] = campos[CIUDAD_INDEX].trim();
          } else {
            cliente['CLI_CIUDAD'] = '';
          }
          
          if (EMAIL_INDEX >= 0 && EMAIL_INDEX < campos.length) {
            cliente['CLI_EMAIL'] = campos[EMAIL_INDEX].trim();
          } else {
            cliente['CLI_EMAIL'] = '';
          }
          
          if (ID_ASESOR_INDEX >= 0 && ID_ASESOR_INDEX < campos.length) {
            cliente['ID ASESOR'] = campos[ID_ASESOR_INDEX].trim();
          } else {
            cliente['ID ASESOR'] = '';
          }
          
          // Añadir el cliente a la lista
          clientes.push(cliente);
          
        } catch (parseError) {
          console.error(`Error al procesar línea ${i+1}:`, parseError);
        }
      }
  
      return clientes;
    } catch (error) {
      console.error('Error al procesar CSV de clientes:', error);
      return [];
    }
  }

app.get('/lista-imagenes', requireAuth, (req, res) => {
  try {
    // Verificar que el directorio existe
    if (!fs.existsSync(imagenesDir)) {
      return res.json({
        success: false,
        message: 'El directorio de imágenes no existe',
        total: 0,
        imagenes: []
      });
    }
    
    // Leer todos los archivos en el directorio
    const files = fs.readdirSync(imagenesDir);
    
    // Filtrar solo archivos JPG/JPEG
    const imagenes = files.filter(file => 
      file.toLowerCase().endsWith('.jpg') || 
      file.toLowerCase().endsWith('.jpeg')
    );
    
    // Obtener información adicional para cada imagen
    const imagenesInfo = imagenes.map(filename => {
      try {
        const filePath = path.join(imagenesDir, filename);
        const stats = fs.statSync(filePath);
        return {
          filename: filename,
          size: stats.size,
          // Convertir tamaño a formato legible
          sizeFormatted: formatFileSize(stats.size),
          lastModified: stats.mtime.toISOString(),
          // Fecha formateada más legible
          lastModifiedFormatted: new Date(stats.mtime).toLocaleString()
        };
      } catch (err) {
        // Si hay un error al obtener información, devolver info básica
        return {
          filename: filename,
          error: 'No se pudo obtener información adicional'
        };
      }
    });
    
    // Si se especifica un parámetro de búsqueda, filtrar resultados
    let resultados = imagenesInfo;
    const query = req.query.q || '';
    
    if (query) {
      resultados = imagenesInfo.filter(img => 
        img.filename.toLowerCase().includes(query.toLowerCase())
      );
    }
    
    // Implementación básica de paginación
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 100;
    const startIndex = (page - 1) * limit;
    const endIndex = page * limit;
    
    const paginatedResults = resultados.slice(startIndex, endIndex);
    
    res.json({
      success: true,
      total: imagenes.length,
      filtered: resultados.length,
      page: page,
      limit: limit,
      totalPages: Math.ceil(resultados.length / limit),
      query: query,
      imagenes: paginatedResults
    });
  } catch (error) {
    console.error('Error al listar imágenes:', error);
    res.status(500).json({ 
      success: false, 
      message: `Error al listar imágenes: ${error.toString()}` 
    });
  }
});

// Endpoint para verificar si una imagen existe
app.get('/imagen-existe/:filename', requireAuth, (req, res) => {
  try {
    const filename = req.params.filename;
    const filePath = path.join(imagenesDir, filename);
    
    if (fs.existsSync(filePath)) {
      const stats = fs.statSync(filePath);
      res.json({
        success: true,
        exists: true,
        filename: filename,
        size: stats.size,
        sizeFormatted: formatFileSize(stats.size),
        lastModified: stats.mtime.toISOString()
      });
    } else {
      res.json({
        success: true,
        exists: false,
        filename: filename
      });
    }
  } catch (error) {
    console.error('Error al verificar imagen:', error);
    res.status(500).json({ 
      success: false, 
      message: `Error al verificar imagen: ${error.toString()}` 
    });
  }
});

// Endpoint para eliminar una imagen
app.delete('/imagen/:filename', requireAuth, (req, res) => {
  try {
    const filename = req.params.filename;
    const filePath = path.join(imagenesDir, filename);
    
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      res.json({
        success: true,
        message: `Imagen ${filename} eliminada correctamente`
      });
    } else {
      res.status(404).json({
        success: false,
        message: `La imagen ${filename} no existe`
      });
    }
  } catch (error) {
    console.error('Error al eliminar imagen:', error);
    res.status(500).json({ 
      success: false, 
      message: `Error al eliminar imagen: ${error.toString()}` 
    });
  }
});

// Función utilitaria para formatear tamaños de archivo
function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' bytes';
  else if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  else if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
  else return (bytes / 1073741824).toFixed(1) + ' GB';
}

app.get('/diagnostico/contador', (req, res) => {
  try {
    const contadorPath = path.join(ordenesPath, 'contador.json');
    const backupPath = path.join(ordenesPath, 'contador.bak.json');
    
    let diagnostico = {
      valorActual: ultimoNumeroOrden,
      carpetaOrdenes: {
        ruta: ordenesPath,
        existe: fs.existsSync(ordenesPath)
      },
      archivoContador: {
        ruta: contadorPath,
        existe: fs.existsSync(contadorPath),
        contenido: null
      },
      archivoBackup: {
        existe: fs.existsSync(backupPath),
        contenido: null
      },
      permisos: {
        escritura: canWriteToPath(ordenesPath)
      }
    };
    
    if (diagnostico.archivoContador.existe) {
      try {
        const data = fs.readFileSync(contadorPath, 'utf8');
        diagnostico.archivoContador.contenido = data;
      } catch (e) {
        diagnostico.archivoContador.error = e.toString();
      }
    }
    
    if (diagnostico.archivoBackup.existe) {
      try {
        const data = fs.readFileSync(backupPath, 'utf8');
        diagnostico.archivoBackup.contenido = data;
      } catch (e) {
        diagnostico.archivoBackup.error = e.toString();
      }
    }
    
    res.json(diagnostico);
  } catch (error) {
    res.status(500).json({
      error: error.toString(),
      message: "Error al generar diagnóstico"
    });
  }
});
// Endpoint para obtener información sobre el CSV de clientes
app.get('/clientes-info', (req, res) => {
  try {
    const clientesPath = path.join(clientesDirPath, 'clientes.csv');
    
    if (fs.existsSync(clientesPath)) {
      const stats = fs.statSync(clientesPath);
      const fileDate = new Date(stats.mtime);
      
      // Obtener metadatos si existen
      const metadata = leerMetadatosArchivo('clientes');
      const nombreOriginal = metadata ? metadata.nombreOriginal : 'clientes.csv';
      
      res.json({
        success: true,
        filename: nombreOriginal,
        size: stats.size,
        lastModified: fileDate.toLocaleString()
      });
    } else {
      res.json({
        success: false,
        message: 'No hay archivo de clientes disponible'
      });
    }
  } catch (error) {
    console.error('Error al obtener info de clientes:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener todos los clientes
app.get('/clientes', (req, res) => {
  try {
    const clientesPath = path.join(clientesDirPath, 'clientes.csv');
    
    if (!fs.existsSync(clientesPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El archivo de clientes no está disponible' 
      });
    }
    
    const clientes = procesarCsvClientes(clientesPath);
    res.json({ 
      success: true, 
      clientes: clientes,
      total: clientes.length
    });
  } catch (error) {
    console.error('Error al obtener clientes:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para buscar un cliente por NIT
app.get('/clientes/:nit', (req, res) => {
  try {
    const { nit } = req.params;
    const clientesPath = path.join(clientesDirPath, 'clientes.csv');
    
    if (!fs.existsSync(clientesPath)) {
      return res.status(404).json({ success: false, message: 'El archivo de clientes no está disponible' });
    }
    
    const clientes = procesarCsvClientes(clientesPath);
    
    // Buscar cliente por NIT
    const cliente = clientes.find(c => String(c['NIT CLIENTE']).trim() === String(nit).trim());
    
    if (!cliente) {
      return res.status(404).json({ 
        success: false, 
        message: `No se encontró cliente con NIT: ${nit}` 
      });
    }
    
    res.json({ 
      success: true, 
      cliente: cliente 
    });
  } catch (error) {
    console.error('Error al buscar cliente:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Subir un nuevo archivo de clientes
app.post('/upload-clientes', requireAuth, upload.single('clientes'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(clientesDirPath, 'clientes.csv');
    const nombreOriginal = req.file.originalname; // Nombre original del archivo

    // Validar el formato CSV antes de guardarlo
    try {
      // Verificar que podemos procesar el archivo
      const clientes = procesarCsvClientes(sourcePath);
      
      if (clientes.length === 0) {
        return res.status(400).json({ 
          success: false, 
          message: 'El archivo CSV no contiene clientes válidos o tiene un formato incorrecto' 
        });
      }
      
      console.log(`CSV de clientes validado correctamente con ${clientes.length} clientes`);
    } catch (error) {
      return res.status(400).json({ 
        success: false, 
        message: `Error al validar CSV de clientes: ${error.message}` 
      });
    }

    // Si el archivo es válido, guardarlo
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath);
    
    // Guardar metadatos con el nombre original
    guardarMetadatosArchivo('clientes', nombreOriginal);

    res.json({ success: true, message: 'Archivo de clientes actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de clientes:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

function leerContador() {
  try {
    const contadorPath = path.join(ordenesPath, 'contador.json');
    console.log(`Intentando leer contador desde: ${contadorPath}`);
    
    if (!fs.existsSync(ordenesPath)) {
      console.log(`Carpeta de órdenes no existe, creándola...`);
      fs.mkdirSync(ordenesPath, { recursive: true });
    }
    
    let ultimoNumero = 1;
    
    if (fs.existsSync(contadorPath)) {
      const data = fs.readFileSync(contadorPath, 'utf8');
      console.log(`Contenido leído del contador: ${data}`);
      
      try {
        const contador = JSON.parse(data);
        if (contador && typeof contador.ultimoNumero === 'number' && contador.ultimoNumero > 0) {
          ultimoNumero = contador.ultimoNumero;
          console.log(`Contador cargado correctamente: ${ultimoNumero}`);
        } else {
          console.log(`Formato inválido de contador, usando valor predeterminado: 1`);
        }
      } catch (parseError) {
        console.error(`Error al parsear JSON del contador: ${parseError}`);
        console.log(`Usando valor predeterminado: 1`);
      }
    } else {
      console.log(`Archivo de contador no existe, se creará con valor inicial: 1`);
      guardarContadorDisco(1);
    }
    
    return ultimoNumero;
  } catch (error) {
    console.error(`Error crítico al leer contador: ${error}`);
    return 1; // Valor predeterminado en caso de error
  }
}

function guardarContadorDisco(valor) {
  try {
    // Asegurar que la carpeta existe
    if (!fs.existsSync(ordenesPath)) {
      fs.mkdirSync(ordenesPath, { recursive: true });
    }
    
    const contadorPath = path.join(ordenesPath, 'contador.json');
    const tempPath = path.join(ordenesPath, 'contador.tmp.json');
    const backupPath = path.join(ordenesPath, 'contador.bak.json');
    
    console.log(`Guardando contador con valor: ${valor}`);
    
    // Crear contenido del archivo
    const contenido = JSON.stringify({
      ultimoNumero: valor,
      fechaActualizacion: new Date().toISOString()
    }, null, 2);
    
    // Escribir primero a un archivo temporal
    fs.writeFileSync(tempPath, contenido, 'utf8');
    
    // Hacer una copia de respaldo del archivo actual si existe
    if (fs.existsSync(contadorPath)) {
      fs.copyFileSync(contadorPath, backupPath);
    }
    
    // Reemplazar el archivo original con el temporal
    fs.renameSync(tempPath, contadorPath);
    
    console.log(`Contador guardado exitosamente: ${valor}`);
    
    // Verificar que se guardó correctamente
    const verificacion = fs.readFileSync(contadorPath, 'utf8');
    console.log(`Verificación de guardado: ${verificacion}`);
    
    return true;
  } catch (error) {
    console.error(`ERROR CRÍTICO al guardar contador: ${error}`);
    return false;
  }
}
  function procesarCsvAsesores(filePath) {
    try {
      // Leer el archivo como buffer binario
      const buffer = fs.readFileSync(filePath);
      // Convertir de Latin1/Windows-1252 a UTF-8
      const fileContent = iconv.decode(buffer, 'win1252');
      
      // Resto del código igual...
      // Dividir por líneas
      const lines = fileContent.split('\n');
      
      // Buscar la línea de encabezados en las primeras 10 filas
      let headerRowIndex = -1;
      for (let i = 0; i < Math.min(10, lines.length); i++) {
        const line = lines[i].toUpperCase();
        // Buscar una línea que contenga "ID" y "NOMBRE" que probablemente sea la fila de encabezados
        if (line.includes('ID') && line.includes('NOMBRE')) {
          headerRowIndex = i;
          break;
        }
      }
      
      // Si no se encuentra, usar la primera fila como predeterminada
      if (headerRowIndex === -1) {
        headerRowIndex = 0;
      }
      
      // Extraer encabezados
      const headerLine = lines[headerRowIndex];
      
      // Dividir encabezados considerando comillas
      const headers = dividirCSV(headerLine);
      
      // Buscar posiciones de las columnas clave - más flexibilidad en la búsqueda
      const ID_INDEX = encontrarIndice(headers, ['ID', 'IDENTIFICACION', 'CEDULA']);
      const NOMBRE_INDEX = encontrarIndice(headers, ['NOMBRE', 'NAME', 'ASESOR']);
      const ZONA_INDEX = encontrarIndice(headers, ['ZONA', 'ZONE', 'AREA', 'TERRITORIO']);
      const MAIL_INDEX = encontrarIndice(headers, ['MAIL', 'EMAIL', 'CORREO']);
      const CEL_INDEX = encontrarIndice(headers, ['CEL', 'CELULAR', 'TELEFONO', 'PHONE']);
      
      // Procesar las líneas de datos 
      const asesores = [];
      
      for (let i = headerRowIndex + 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue; // Saltar líneas vacías
        
        try {
          // Dividir la línea considerando comillas
          const campos = dividirCSV(line);
          
          // Saltar la línea si no hay suficientes columnas
          if (campos.length < 2) {
            continue;
          }
          
          // Crear objeto asesor con los campos básicos
          const asesor = {};
          
          // ID - requerido
          if (ID_INDEX >= 0 && ID_INDEX < campos.length) {
            asesor.ID = campos[ID_INDEX].trim();
            // Si está vacío, saltar esta línea
            if (!asesor.ID) {
              continue;
            }
          } else {
            continue; // Sin ID válido no procesamos
          }
          
          // NOMBRE - requerido
          if (NOMBRE_INDEX >= 0 && NOMBRE_INDEX < campos.length) {
            asesor.NOMBRE = campos[NOMBRE_INDEX].trim();
            // Si está vacío, usar un nombre genérico
            if (!asesor.NOMBRE) {
              asesor.NOMBRE = `Asesor ${asesor.ID}`;
            }
          } else {
            asesor.NOMBRE = `Asesor ${asesor.ID}`;
          }
          
          // Restantes campos
          if (ZONA_INDEX >= 0 && ZONA_INDEX < campos.length) {
            asesor.ZONA = campos[ZONA_INDEX].trim();
          } else {
            asesor.ZONA = '';
          }
          
          if (MAIL_INDEX >= 0 && MAIL_INDEX < campos.length) {
            asesor.MAIL = campos[MAIL_INDEX].trim();
          } else {
            asesor.MAIL = '';
          }
          
          if (CEL_INDEX >= 0 && CEL_INDEX < campos.length) {
            asesor.CEL = campos[CEL_INDEX].trim();
          } else {
            asesor.CEL = '';
          }
          
          // Añadir el asesor a la lista
          asesores.push(asesor);
          
        } catch (parseError) {
          console.error(`Error al procesar línea ${i+1}:`, parseError);
        }
      }

      return asesores;
    } catch (error) {
      console.error('Error al procesar CSV de asesores:', error);
      return [];
    }
  }

app.get('/asesores-info', (req, res) => {
  try {
    const asesoresPath = path.join(asesoresDirPath, 'asesores.csv');
    
    if (fs.existsSync(asesoresPath)) {
      const stats = fs.statSync(asesoresPath);
      const fileDate = new Date(stats.mtime);
      
      // Obtener metadatos si existen
      const metadata = leerMetadatosArchivo('asesores');
      const nombreOriginal = metadata ? metadata.nombreOriginal : 'asesores.csv';
      
      res.json({
        success: true,
        filename: nombreOriginal,
        size: stats.size,
        lastModified: fileDate.toLocaleString()
      });
    } else {
      res.json({
        success: false,
        message: 'No hay archivo de asesores disponible'
      });
    }
  } catch (error) {
    console.error('Error al obtener info de asesores:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener todos los asesores
app.get('/asesores', (req, res) => {
  try {
    const asesoresPath = path.join(asesoresDirPath, 'asesores.csv');
    
    if (!fs.existsSync(asesoresPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El archivo de asesores no está disponible' 
      });
    }
    
    const asesores = procesarCsvAsesores(asesoresPath);
    res.json({ 
      success: true, 
      asesores: asesores,
      total: asesores.length
    });
  } catch (error) {
    console.error('Error al obtener asesores:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para buscar un asesor por ID
app.get('/asesores/:id', (req, res) => {
  try {
    const { id } = req.params;
    const asesoresPath = path.join(asesoresDirPath, 'asesores.csv');
    
    if (!fs.existsSync(asesoresPath)) {
      return res.status(404).json({ success: false, message: 'El archivo de asesores no está disponible' });
    }
    
    const asesores = procesarCsvAsesores(asesoresPath);
    
    // Buscar asesor por ID
    const asesor = asesores.find(a => String(a.ID).trim() === String(id).trim());
    
    if (!asesor) {
      return res.status(404).json({ 
        success: false, 
        message: `No se encontró asesor con ID: ${id}` 
      });
    }
    
    res.json({ 
      success: true, 
      asesor: asesor 
    });
  } catch (error) {
    console.error('Error al buscar asesor:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para buscar un asesor por correo
app.get('/asesores/correo/:email', (req, res) => {
  try {
    const { email } = req.params;
    const asesoresPath = path.join(asesoresDirPath, 'asesores.csv');
    
    if (!fs.existsSync(asesoresPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El archivo de asesores no está disponible' 
      });
    }
    
    const asesores = procesarCsvAsesores(asesoresPath);
    
    // Buscar asesor por correo (normalizado)
    const emailNormalizado = email.trim().toLowerCase();
    const asesor = asesores.find(a => {
      const asesorEmail = (a.MAIL || '').toString().trim().toLowerCase();
      return asesorEmail === emailNormalizado;
    });
    
    if (!asesor) {
      return res.status(404).json({ 
        success: false, 
        message: `No se encontró asesor con correo: ${email}` 
      });
    }
    
    res.json({ 
      success: true, 
      asesor: asesor 
    });
  } catch (error) {
    console.error('Error al buscar asesor por correo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Subir un nuevo archivo de asesores
app.post('/upload-asesores', requireAuth, upload.single('asesores'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(asesoresDirPath, 'asesores.csv');
    const nombreOriginal = req.file.originalname; // Nombre original del archivo

    // Validar el formato CSV antes de guardarlo
    try {
      // Verificar que podemos procesar el archivo
      const asesores = procesarCsvAsesores(sourcePath);
      
      if (asesores.length === 0) {
        return res.status(400).json({ 
          success: false, 
          message: 'El archivo CSV no contiene asesores válidos o tiene un formato incorrecto' 
        });
      }
      
      console.log(`CSV de asesores validado correctamente con ${asesores.length} asesores`);
    } catch (error) {
      return res.status(400).json({ 
        success: false, 
        message: `Error al validar CSV de asesores: ${error.message}` 
      });
    }

    // Si el archivo es válido, guardarlo
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath);
    
    // Guardar metadatos con el nombre original
    guardarMetadatosArchivo('asesores', nombreOriginal);

    res.json({ success: true, message: 'Archivo de asesores actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de asesores:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

const iconv = require('iconv-lite');
function procesarCsvProductos(filePath) {
  try {
    console.log(`Procesando CSV desde: ${filePath}`);
    
    // Verificar que el archivo existe
    if (!fs.existsSync(filePath)) {
      console.log(`El archivo no existe o ya fue procesado: ${filePath}`);
      return []; // Devolver array vacío sin mostrar error en consola
    }
    const buffer = fs.readFileSync(filePath);
    
    // Probar diferentes encodings para encontrar el mejor
    const encodingsToTry = ['utf8', 'win1252', 'latin1', 'iso-8859-1'];
    let fileContent = '';
    let bestEncoding = '';
    let minErrorCount = Infinity;
    
    for (const encoding of encodingsToTry) {
      try {
        const testContent = iconv.decode(buffer, encoding);
        // Contar caracteres problemáticos
        const errorCount = (testContent.match(/�/g) || []).length;
        
        if (errorCount < minErrorCount) {
          minErrorCount = errorCount;
          fileContent = testContent;
          bestEncoding = encoding;
          
          // Si no hay errores, usar este encoding inmediatamente
          if (errorCount === 0) break;
        }
      } catch (e) {
        console.log(`Error al decodificar con ${encoding}`);
      }
    }
    
    console.log(`Usando encoding ${bestEncoding} para CSV de productos`);
    
    console.log(`Archivo leído correctamente, tamaño: ${buffer.length} bytes`);
    // Dividir por líneas
    const lines = fileContent.split('\n');
    
    // Buscar la línea de encabezados en las primeras 10 filas
    let headerRowIndex = -1;
    for (let i = 0; i < Math.min(10, lines.length); i++) {
      const line = lines[i].toUpperCase();
      // Buscar una línea que contenga "CODIGO" y "DESCRIPCION" que probablemente sea la fila de encabezados
      if (line.includes('CODIGO') && 
         (line.includes('DESCRIPCION') || line.includes('DESC'))) {
        headerRowIndex = i;;
        break;
      }
    }
    
    // Si no se encuentra, usar la fila 7 (índice 6) como predeterminada
    if (headerRowIndex === -1) {
      headerRowIndex = 6;
    }
    
    // Extraer encabezados
    const headerLine = lines[headerRowIndex];

    // Dividir encabezados considerando comillas
    const headers = dividirCSV(headerLine);
    
    
    // Buscar posiciones de las columnas clave - más flexibilidad en la búsqueda
    const ESTADO_INDEX = encontrarIndice(headers, ['ESTADO', 'STATUS', 'DISPONIBLE']);
    const NUMERO_INDEX = encontrarIndice(headers, ['#', 'NUM', 'NUMERO', 'ID']);
    const CODIGO_INDEX = encontrarIndice(headers, ['CODIGO', 'CODE', 'COD']);
    const BODEGA_INDEX = encontrarIndice(headers, ['UB', 'BOD', 'BODEGA', 'UBIC']);
    const REF_INDEX = encontrarIndice(headers, ['REF', 'REFERENCIA', 'REFER']);
    const ORIGEN_INDEX = encontrarIndice(headers, ['ORIGEN', 'NAL', 'PAIS']);
    const DESC_INDEX = encontrarIndice(headers, ['DESCRIPCION', 'DESC', 'DESCRIPTOR', 'NOMBRE']);
    const VEHICULO_INDEX = encontrarIndice(headers, ['VEHICULO', 'VEH', 'AUTO']);
    const MARCA_INDEX = encontrarIndice(headers, ['MARCA', 'OEM', 'BRAND']);
    const PRECIO_INDEX = encontrarIndice(headers, ['PRECIO', 'PRICE', 'VLR', 'VALOR', 'ANTES IVA']);
    const DSCTO_INDEX = encontrarIndice(headers, ['DSCTO', 'DESCUENTO', '%', 'PORCENTAJE']);
    
    // Procesar las líneas de datos 
    const productos = [];
    
    for (let i = headerRowIndex + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue; // Saltar líneas vacías
      
      try {
        // Dividir la línea considerando comillas
        const campos = dividirCSV(line);
        
        // Saltar la línea si no hay suficientes columnas
        if (campos.length < 3) {
          continue;
        }
        
        // Crear objeto producto con los campos básicos
        const producto = {};
        
        // ESTADO (agotado o vacío)
        if (ESTADO_INDEX >= 0 && ESTADO_INDEX < campos.length) {
          producto.ESTADO = campos[ESTADO_INDEX].trim();
        } else {
          producto.ESTADO = '';
        }
        
        // Número/ID (#)
        if (NUMERO_INDEX >= 0 && NUMERO_INDEX < campos.length) {
          producto['#'] = campos[NUMERO_INDEX].trim();
        } else {
          producto['#'] = (i - headerRowIndex).toString();
        }
        
        // CÓDIGO - requerido
        if (CODIGO_INDEX >= 0 && CODIGO_INDEX < campos.length) {
          producto.CODIGO = campos[CODIGO_INDEX].trim();
          // Si está vacío, saltar esta línea
          if (!producto.CODIGO) {;
            continue;
          }
        } else {
          continue; // Sin código válido no procesamos
        }
        
        // DESCRIPCIÓN - con mejor manejo
        if (DESC_INDEX >= 0 && DESC_INDEX < campos.length) {
          producto.DESCRIPCION = campos[DESC_INDEX].trim();
        } else {
          // Si no hay descripción, usar el código
          producto.DESCRIPCION = `Producto ${producto.CODIGO}`;
        }
        
        // Restantes campos
        if (BODEGA_INDEX >= 0 && BODEGA_INDEX < campos.length) {
          producto.UB = campos[BODEGA_INDEX].trim();
        } else {
          producto.UB = '';
        }
        
        if (REF_INDEX >= 0 && REF_INDEX < campos.length) {
          producto.REF = campos[REF_INDEX].trim();
        } else {
          producto.REF = '';
        }
        
        if (ORIGEN_INDEX >= 0 && ORIGEN_INDEX < campos.length) {
          producto.ORIGEN = campos[ORIGEN_INDEX].trim();
        } else {
          producto.ORIGEN = '';
        }
        
        if (VEHICULO_INDEX >= 0 && VEHICULO_INDEX < campos.length) {
          producto.VEHICULO = campos[VEHICULO_INDEX].trim();
        } else {
          producto.VEHICULO = '';
        }
        
        if (MARCA_INDEX >= 0 && MARCA_INDEX < campos.length) {
          producto.MARCA = campos[MARCA_INDEX].trim();
        } else {
          producto.MARCA = '';
        }

        if (DSCTO_INDEX >= 0 && DSCTO_INDEX < campos.length) {
          let descuentoStr = campos[DSCTO_INDEX].trim();
          producto.DSCTO = procesarDescuento(descuentoStr);
        } else {
          // Si no hay columna de descuento en el CSV, asignar un valor predeterminado
          producto.DSCTO = 20;
        }
        
        if (PRECIO_INDEX >= 0 && PRECIO_INDEX < campos.length) {
          let precioStr = campos[PRECIO_INDEX].trim();
          
          // Log para depuración
          
          // Limpiar formato de moneda (quitar $, espacios, etc.)
          precioStr = precioStr.replace(/[^\d.,]/g, '');
          
          // Manejar comas como separadores decimales y de miles
          if (precioStr.includes(',')) {
            // Si hay varias comas, están siendo usadas como separadores de miles
            const commaCount = (precioStr.match(/,/g) || []).length;
            
            if (commaCount > 1) {
              // Formato tipo $4,530,000 -> quitar las comas
              precioStr = precioStr.replace(/,/g, '');
            } else if (precioStr.includes('.')) {
              // Tiene coma y punto, formato internacional tipo 1.234,56
              precioStr = precioStr.replace(/\./g, '').replace(',', '.');
            } else {
              // Solo una coma como en $4,530 -> interpretar como miles, no como decimal
              precioStr = precioStr.replace(',', '');
            }
          }
          
          // Convertir a número
          let precio = parseFloat(precioStr) || 0;
          
          // Verificar si el precio parece demasiado bajo para un producto 
          // Para valores como "4,530" que representan realmente 4530 (no 4.53)
          if (precio > 0 && precio < 100) {
            precio = precio * 1000;
          }
          
          producto.PRECIO = precio;
          
          // Log para depuración
        } else {
          producto.PRECIO = 0;
        }
        
        // Añadir el producto a la lista
        productos.push(producto);
        
      } catch (parseError) {
        console.error(`Error al procesar línea ${i+1}:`, parseError);
      }
    }

    return productos;
  } catch (error) {
    console.error('Error al procesar CSV:', error);
    return [];
  }
}

function procesarDescuento(descuentoStr) {
  
  // Si es null o undefined, usar valor predeterminado
  if (descuentoStr === null || descuentoStr === undefined) {
    console.log("Descuento nulo/undefined, usando predeterminado: 20%");
    return 20;
  }
  
  // Convertir a string y limpiar
  descuentoStr = String(descuentoStr).trim();
  
  // Si es cadena vacía, usar valor predeterminado
  if (descuentoStr === '') {
    return 20;
  }
  
  // Eliminar % y cualquier carácter no numérico
  let limpio = descuentoStr.replace(/[^\d.,]/g, '');;
  
  // Si después de limpiar queda vacío, usar predeterminado
  if (limpio === '') {
    return 20;
  }
  
  // Manejar comas como puntos decimales
  if (limpio.includes(',')) {
    limpio = limpio.replace(',', '.');
  }
  
  // Convertir a número
  const valor = parseFloat(limpio);
  
  // Si no es un número válido, usar predeterminado
  if (isNaN(valor)) {
    return 20;
  }
  
  // Limitar al rango 0-100
  const resultado = Math.min(100, Math.max(0, valor));
  
  return resultado;
}


function dividirCSV(linea) {
  const resultado = [];
  let campoActual = '';
  let enComillas = false;
  
  for (let i = 0; i < linea.length; i++) {
    const caracter = linea[i];
    
    if (caracter === '"') {
      // Si es una comilla escapada (doble comilla)
      if (i + 1 < linea.length && linea[i + 1] === '"') {
        campoActual += '"';
        i++; // Saltar la siguiente comilla
      } else {
        // Cambiar estado de comillas
        enComillas = !enComillas;
      }
    } else if (caracter === ',' && !enComillas) {
      // Si encontramos una coma fuera de comillas, es un separador
      resultado.push(campoActual);
      campoActual = '';
    } else {
      // Cualquier otro carácter, agregarlo al campo actual
      campoActual += caracter;
    }
  }
  
  // No olvidar el último campo
  resultado.push(campoActual);
  
  return resultado;
}

// Función mejorada para encontrar índices con más opciones de búsqueda
function encontrarIndice(encabezados, posiblesNombres) {
  for (const nombre of posiblesNombres) {
    // Primero buscar coincidencia exacta
    let indice = encabezados.findIndex(h => 
      h.toUpperCase().trim() === nombre.toUpperCase().trim()
    );
    
    // Si no hay coincidencia exacta, buscar coincidencia parcial
    if (indice === -1) {
      indice = encabezados.findIndex(h => 
        h.toUpperCase().trim().includes(nombre.toUpperCase().trim())
      );
    }
    
    if (indice !== -1) return indice;
  }
  return -1;
}

// Endpoint para obtener información sobre el catálogo actual
app.get('/catalogo-info', (req, res) => {
  try {
    const catalogoPath = path.join(catDirPath, 'catalogo.pdf');
    
    if (fs.existsSync(catalogoPath)) {
      const stats = fs.statSync(catalogoPath);
      const fileDate = new Date(stats.mtime);
      
      // Obtener metadatos si existen
      const metadata = leerMetadatosArchivo('catalogo');
      const nombreOriginal = metadata ? metadata.nombreOriginal : 'catalogo.pdf';
      
      res.json({
        success: true,
        filename: nombreOriginal,
        size: stats.size,
        lastModified: fileDate.toLocaleString()
      });
    } else {
      res.json({
        success: false,
        message: 'No hay catálogo disponible'
      });
    }
  } catch (error) {
    console.error('Error al obtener info del catálogo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


app.get('/catalogo', (req, res) => {
  try {
    const catalogoPath = path.join(catDirPath, 'catalogo.pdf');
    
    if (!fs.existsSync(catalogoPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El catálogo no está disponible' 
      });
    }
    
    // Leer el archivo PDF y enviarlo como respuesta
    const fileStream = fs.createReadStream(catalogoPath);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'inline; filename=catalogo.pdf');
    
    fileStream.pipe(res);
  } catch (error) {
    console.error('Error al servir el catálogo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener información sobre el CSV de productos
app.get('/productos-info', (req, res) => {
  try {
    const productosPath = path.join(productosDirPath, 'productos.csv');
    
    if (fs.existsSync(productosPath)) {
      const stats = fs.statSync(productosPath);
      const fileDate = new Date(stats.mtime);
      
      // Obtener metadatos si existen
      const metadata = leerMetadatosArchivo('productos');
      const nombreOriginal = metadata ? metadata.nombreOriginal : 'productos.csv';
      
      res.json({
        success: true,
        filename: nombreOriginal,
        size: stats.size,
        lastModified: fileDate.toLocaleString()
      });
    } else {
      res.json({
        success: false,
        message: 'No hay archivo de productos disponible'
      });
    }
  } catch (error) {
    console.error('Error al obtener info de productos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener todos los productos
app.get('/productos', (req, res) => {
  try {
    const productosPath = path.join(productosDirPath, 'productos.csv');
    
    if (!fs.existsSync(productosPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'El archivo de productos no está disponible' 
      });
    }
    
    const productos = procesarCsvProductos(productosPath);
    res.json({ 
      success: true, 
      productos: productos,
      total: productos.length
    });
  } catch (error) {
    console.error('Error al obtener productos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para buscar un producto por su número
app.get('/productos/:numero', (req, res) => {
  try {
    const { numero } = req.params;
    const productosPath = path.join(productosDirPath, 'productos.csv');
    
    if (!fs.existsSync(productosPath)) {
      return res.status(404).json({ success: false, message: 'El archivo de productos no está disponible' });
    }
    
    const productos = procesarCsvProductos(productosPath);
    
    // Buscar producto por número
    const producto = productos.find(p => String(p['#']).trim() === String(numero).trim());
    
    if (!producto) {
      return res.status(404).json({ 
        success: false, 
        message: `No se encontró producto con número: ${numero}` 
      });
    }
    
    res.json({ 
      success: true, 
      producto: producto 
    });
  } catch (error) {
    console.error('Error al buscar producto:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

app.get('/ping', (req, res) => {
  res.json({ status: 'ok' });
});



// Subir un nuevo catálogo
app.post('/upload-catalogo', requireAuth, (req, res) => {
  // Establecer un timeout largo para el manejo de la petición
  req.setTimeout(UPLOAD_TIMEOUT);
  
  // Usar el middleware de multer para la subida
  uploadCatalogo.single('catalogo')(req, res, async function(err) {
    try {
      console.log("Procesando solicitud de subida de catálogo");
      
      if (err) {
        console.error('Error en multer:', err);
        if (err instanceof multer.MulterError) {
          if (err.code === 'LIMIT_FILE_SIZE') {
            return res.status(400).json({ 
              success: false, 
              message: `El archivo excede el límite de tamaño de ${formatFileSize(UPLOAD_FILE_SIZE_LIMIT)}.` 
            });
          }
        }
        return res.status(500).json({ 
          success: false, 
          message: `Error al subir archivo: ${err.message}` 
        });
      }
      
      if (!req.file) {
        return res.status(400).json({ 
          success: false, 
          message: 'No se ha subido ningún archivo' 
        });
      }
      
      console.log(`Archivo recibido: ${req.file.originalname}, tamaño: ${req.file.size}, guardado como: ${req.file.filename} en ${req.file.path}`);
      
      const sourcePath = req.file.path; // Usar la ruta real proporcionada por multer
      const destPath = path.join(catDirPath, 'catalogo.pdf');
      const nombreOriginal = req.file.originalname;
      
      // Verificar que el archivo realmente existe
      if (!fs.existsSync(sourcePath)) {
        return res.status(500).json({
          success: false,
          message: `Error: El archivo temporal no existe en ${sourcePath}`
        });
      }
      
      // Verificar que el archivo sea realmente un PDF
      try {
        const fileHeader = Buffer.alloc(5);
        const fd = fs.openSync(sourcePath, 'r');
        fs.readSync(fd, fileHeader, 0, 5, 0);
        fs.closeSync(fd);
        
        const isPDF = fileHeader.toString().includes('%PDF');
        if (!isPDF) {
          fs.unlinkSync(sourcePath);
          return res.status(400).json({ 
            success: false, 
            message: 'El archivo subido no parece ser un PDF válido.' 
          });
        }
      } catch (validationErr) {
        console.error('Error al validar PDF:', validationErr);
        // Continuar a pesar de error en validación
      }
      
      // Mover el archivo a su ubicación final
      try {
        if (fs.existsSync(destPath)) {
          // Hacer backup antes de sobrescribir
          const backupPath = path.join(catDirPath, 'catalogo.bak.pdf');
          if (fs.existsSync(backupPath)) {
            fs.unlinkSync(backupPath);
          }
          fs.copyFileSync(destPath, backupPath);
          console.log(`Backup creado: ${backupPath}`);
        }
        
        // Usar copyFile en lugar de rename para mayor compatibilidad
        fs.copyFileSync(sourcePath, destPath);
        fs.unlinkSync(sourcePath); // Eliminar el archivo temporal
        
        // Guardar metadatos con el nombre original
        guardarMetadatosArchivo('catalogo', nombreOriginal);
        
        console.log(`Catálogo actualizado: ${destPath}`);
        
        res.json({ 
          success: true, 
          message: 'Catálogo actualizado correctamente',
          filename: nombreOriginal,
          size: req.file.size
        });
      } catch (moveErr) {
        console.error('Error al mover archivo:', moveErr);
        
        // Si el error persiste, informar al cliente
        res.status(500).json({ 
          success: false, 
          message: `Error al guardar el catálogo: ${moveErr.message}` 
        });
      }
    } catch (error) {
      console.error('Error general en subida de catálogo:', error);
      res.status(500).json({ 
        success: false, 
        message: `Error general en la subida: ${error.message}` 
      });
    }
  });
});

function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' bytes';
  else if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  else if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
  else return (bytes / 1073741824).toFixed(1) + ' GB';
}

// Subir un nuevo archivo de productos
app.post('/upload-productos', requireAuth, upload.single('productos'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(productosDirPath, 'productos.csv');
    const nombreOriginal = req.file.originalname;

    // Añadir bandera para evitar validaciones duplicadas
    let archivoYaProcesado = false;

    // Validar el formato CSV directamente desde la ruta temporal
    try {
      console.log(`Validando CSV desde la ruta temporal: ${sourcePath}`);
      
      // Verificar que el archivo existe
      if (!fs.existsSync(sourcePath)) {
        return res.status(400).json({
          success: false,
          message: `El archivo temporal no existe: ${sourcePath}`
        });
      }
      
      // Verificar que podemos procesar el archivo
      const productos = procesarCsvProductos(sourcePath);
      
      if (productos.length === 0) {
        return res.status(400).json({ 
          success: false, 
          message: 'El archivo CSV no contiene productos válidos o tiene un formato incorrecto' 
        });
      }
      
      console.log(`CSV validado correctamente con ${productos.length} productos`);
    } catch (error) {
      // Solo mostrar el error si el archivo no ha sido procesado
      if (!archivoYaProcesado) {
        console.error('Error al validar CSV:', error);
        return res.status(400).json({ 
          success: false, 
          message: `Error al validar CSV: ${error.message}` 
        });
      }
    }

    // Asegurarse de que el directorio de productos existe
    if (!fs.existsSync(productosDirPath)) {
      console.log(`Creando directorio de productos: ${productosDirPath}`);
      fs.mkdirSync(productosDirPath, { recursive: true });
    }

    // Si el archivo es válido, guardarlo
    if (fs.existsSync(destPath)) {
      try {
        fs.unlinkSync(destPath);
        console.log(`Archivo existente eliminado: ${destPath}`);
      } catch (deleteErr) {
        console.error(`Error al eliminar archivo existente: ${deleteErr}`);
      }
    }

    try {
      console.log(`Copiando de ${sourcePath} a ${destPath}`);
      fs.copyFileSync(sourcePath, destPath);
      console.log(`Archivo copiado exitosamente`);
      
      // Marcar como procesado después de copiar exitosamente
      archivoYaProcesado = true;
      
      // Eliminar el archivo temporal
      try {
        fs.unlinkSync(sourcePath);
        console.log(`Archivo temporal eliminado: ${sourcePath}`);
      } catch (deleteErr) {
        console.error(`Error al eliminar archivo temporal: ${deleteErr}`);
      }
    } catch (copyErr) {
      console.error(`Error al copiar archivo: ${copyErr}`);
      return res.status(500).json({
        success: false,
        message: `Error al copiar archivo: ${copyErr.message}`
      });
    }
    
    // Guardar metadatos con el nombre original
    guardarMetadatosArchivo('productos', nombreOriginal);

    // Responder al cliente solo una vez y salir de la función
    res.json({ success: true, message: 'Archivo de productos actualizado correctamente' });
    return;
  } catch (error) {
    console.error('Error al subir archivo de productos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

app.use('/css', express.static(path.join(__dirname, 'public', 'css')));
app.use('/js', express.static(path.join(__dirname, 'public', 'js')));
app.use('/images', express.static(path.join(__dirname, 'public', 'images')));


const PORT = process.env.PORT;
// Iniciar el servidor
app.listen(PORT, () => {
  console.log(`Servidor escuchando en http://0.0.0.0:${PORT}`);
  console.log(`Puedes acceder desde otros dispositivos usando: http://<IP_LOCAL>:${PORT}`);

  ultimoNumeroOrden = leerContador();
  console.log(`Contador inicializado con valor: ${ultimoNumeroOrden}`);

  procesarCsvProductos(path.join(productosDirPath, 'productos.csv'));
});