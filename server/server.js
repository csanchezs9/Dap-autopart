const express = require('express');
const multer = require('multer');
const nodemailer = require('nodemailer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3000;

// Configurar CORS para permitir solicitudes de la app
app.use(cors());
app.use(bodyParser.json());

// Crear carpeta de archivos si no existe
const uploadDir = path.join(__dirname, 'uploads');
const catDirPath = path.join(__dirname, 'catalogos');
const tempDir = path.join(__dirname, 'temp');

[uploadDir, catDirPath, tempDir].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Configurar almacenamiento para archivos subidos
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    cb(null, `catalogo.pdf`);
  }
});

const upload = multer({ storage: storage });

// Transportador de correo (puedes usar tus propias credenciales)
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: 'camilosanchezwwe@gmail.com', // CAMBIAR: Coloca tu correo aquí
    pass: 'xens efby pvfc qdhz' // Reemplaza con tu contraseña o token de app
  }
});

// Endpoint para enviar correo
app.post('/send-email', upload.single('pdf'), async (req, res) => {
  try {
    const { clienteEmail, asesorEmail, asunto, cuerpo } = req.body;
    const pdfPath = req.file.path;

    // Verificar correo del cliente
    if (!clienteEmail) {
      return res.status(400).json({ success: false, message: 'Falta el correo del cliente' });
    }

    // Enviar correo
    const mailOptions = {
      from: '"DAP AutoPart\'s" <camilosanchezwwe@gmail.com>',
      to: clienteEmail,
      cc: asesorEmail || '',
      subject: asunto || 'Orden de Pedido - DAP AutoPart\'s',
      text: cuerpo || 'Adjunto encontrará su orden de pedido.',
      attachments: [
        {
          filename: path.basename(pdfPath),
          path: pdfPath
        }
      ]
    };

    await transporter.sendMail(mailOptions);
    
    // Eliminar archivo temporal después de enviar
    fs.unlinkSync(pdfPath);

    res.json({ success: true, message: 'Correo enviado correctamente' });
  } catch (error) {
    console.error('Error al enviar correo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


// Endpoint para obtener el catálogo actual
app.get('/catalogo', (req, res) => {
  try {
    const catalogoPath = path.join(catDirPath, 'catalogo.pdf');
    
    // Verificar si existe el archivo
    if (!fs.existsSync(catalogoPath)) {
      return res.status(404).json({ success: false, message: 'El catálogo no está disponible' });
    }
    
    // Enviar el archivo
    res.sendFile(catalogoPath);
  } catch (error) {
    console.error('Error al enviar catálogo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Endpoint para obtener información sobre el catálogo actual
app.get('/catalogo-info', (req, res) => {
  try {
    const catalogoPath = path.join(catDirPath, 'catalogo.pdf');
    
    if (fs.existsSync(catalogoPath)) {
      const stats = fs.statSync(catalogoPath);
      const fileDate = new Date(stats.mtime);
      
      res.json({
        success: true,
        filename: 'catalogo.pdf',
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

app.get('/ping', (req, res) => {
  res.json({ status: 'ok' });
});
// Endpoints para la administración web
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Servir archivos estáticos para la interfaz de administración
app.use(express.static(path.join(__dirname, 'public')));

// Subir un nuevo catálogo (desde la interfaz web)
app.post('/upload-catalogo', upload.single('catalogo'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    // Mover archivo a la carpeta de catálogos
    const sourcePath = req.file.path;
    const destPath = path.join(catDirPath, 'catalogo.pdf');

    // Si ya existe, reemplazarlo
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    // Copiar el nuevo archivo
    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath); // Eliminar el archivo temporal

    res.json({ success: true, message: 'Catálogo actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir catálogo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Iniciar el servidor
app.listen(PORT, () => {
  console.log(`Servidor ejecutándose en http://localhost:${PORT}`);
  console.log(`Interfaz de administración: http://localhost:${PORT}/admin`);
});