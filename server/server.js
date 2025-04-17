const express = require('express');
const multer = require('multer');
const nodemailer = require('nodemailer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const bodyParser = require('body-parser');
const csv = require('csv-parser'); // Para CSV estándar
const { parse } = require('csv-parse/sync'); // Para control manual del parsing

const app = express();
const PORT = process.env.PORT || 3000;

// Configurar CORS para permitir solicitudes de la app
app.use(cors());
app.use(bodyParser.json());

// Crear carpeta de archivos si no existe
const uploadDir = path.join(__dirname, 'uploads');
const catDirPath = path.join(__dirname, 'catalogos');
const tempDir = path.join(__dirname, 'temp');
const productosDirPath = path.join(__dirname, 'productos');

[uploadDir, catDirPath, tempDir, productosDirPath].forEach(dir => {
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
    if (file.fieldname === 'catalogo') {
      cb(null, 'catalogo.pdf');
    } else if (file.fieldname === 'productos') {
      cb(null, 'productos.csv');
    } else {
      cb(null, file.originalname);
    }
  }
});

const upload = multer({ storage: storage });

// Transportador de correo
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: 'camilosanchezwwe@gmail.com',
    pass: 'xens efby pvfc qdhz'
  }
});

// Endpoint para enviar correo
app.post('/send-email', upload.single('pdf'), async (req, res) => {
  try {
    const { clienteEmail, asesorEmail, asunto, cuerpo } = req.body;
    const pdfPath = req.file.path;

    if (!clienteEmail) {
      return res.status(400).json({ success: false, message: 'Falta el correo del cliente' });
    }

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
    
    fs.unlinkSync(pdfPath);

    res.json({ success: true, message: 'Correo enviado correctamente' });
  } catch (error) {
    console.error('Error al enviar correo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Función para procesar el archivo CSV de productos y extraer datos
// Adaptada específicamente para el formato proporcionado
const fs = require('fs');

// Reemplaza la función procesarCsvProductos con esta versión mejorada
function procesarCsvProductos(filePath) {
  try {
    // Leer el archivo completo
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
    // Imprimir el contenido para diagnóstico
    console.log("===== DIAGNÓSTICO DE CSV =====");
    console.log(`Primeros 200 caracteres: ${fileContent.substring(0, 200)}`);
    
    // Dividir por líneas
    const lines = fileContent.split('\n');
    
    // Encontrar la línea de encabezados (asumimos fila 7)
    const HEADER_ROW_INDEX = 6; // Fila 7 (índice base 0)
    if (lines.length <= HEADER_ROW_INDEX) {
      console.error('El archivo CSV no tiene suficientes filas para contener encabezados');
      return [];
    }
    
    // Extraer encabezados manualmente dividiéndolos por comas
    // pero considerando posibles comillas que pueden contener comas
    const headerLine = lines[HEADER_ROW_INDEX];
    console.log(`Línea de encabezados: ${headerLine}`);
    
    // Dividir encabezados considerando comillas (parsing básico)
    const headers = dividirCSV(headerLine);
    console.log("Encabezados procesados:", headers);
    
    // Buscar posiciones de las columnas clave
    const ESTADO_INDEX = encontrarIndice(headers, ['ESTADO', 'STATUS']);
    const NUMERO_INDEX = encontrarIndice(headers, ['#', 'NUM', 'NUMERO']);
    const CODIGO_INDEX = encontrarIndice(headers, ['CODIGO', 'CODE']);
    const BODEGA_INDEX = encontrarIndice(headers, ['UB', 'BOD', 'BODEGA']);
    const REF_INDEX = encontrarIndice(headers, ['REF', 'REFERENCIA']);
    const ORIGEN_INDEX = encontrarIndice(headers, ['ORIGEN', 'NAL']);
    const DESC_INDEX = encontrarIndice(headers, ['DESCRIPCION', 'DESC', 'DESCRIPTOR']);
    const VEHICULO_INDEX = encontrarIndice(headers, ['VEHICULO', 'VEH']);
    const MARCA_INDEX = encontrarIndice(headers, ['MARCA', 'OEM']);
    const PRECIO_INDEX = encontrarIndice(headers, ['PRECIO', 'PRICE', 'VLR']);
    const DSCTO_INDEX = encontrarIndice(headers, ['DSCTO', 'DESCUENTO', '%']);
    
    console.log(`Índices: ESTADO=${ESTADO_INDEX}, #=${NUMERO_INDEX}, CODIGO=${CODIGO_INDEX}, DESC=${DESC_INDEX}, PRECIO=${PRECIO_INDEX}`);
    
    // Procesar las líneas de datos 
    const productos = [];
    
    // Usar un mapeo directo para las descripciones basadas en #/código
    // para casos específicos que sabemos que están fallando
    const descripcionesFijas = {
      'H1245': 'ABRAZADERA BUJE PUÑO',
      'H4211': 'BOMBA AGUA',
      'R0197': 'ABRAZADERA CAJA DIR',
      'K0182': 'BIELETA SUSPENSION DEL RH',
      '2': 'ABRAZADERA BUJE PUÑO',
      '3': 'ABRAZADERA CAJA DIR', 
      '54': 'BIELETA SUSPENSION DEL RH',
      '99': 'BOMBA AGUA'
    };
    
    for (let i = HEADER_ROW_INDEX + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue; // Saltar líneas vacías
      
      console.log(`\nProcesando línea ${i}:`);
      console.log(`Línea: ${line.substring(0, 100)}...`);
      
      try {
        // Dividir la línea considerando comillas
        const campos = dividirCSV(line);
        console.log(`Campos procesados (${campos.length}):`, campos.slice(0, 10));
        
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
          producto['#'] = (i - HEADER_ROW_INDEX).toString();
        }
        
        // CÓDIGO
        if (CODIGO_INDEX >= 0 && CODIGO_INDEX < campos.length) {
          producto.CODIGO = campos[CODIGO_INDEX].trim();
        } else {
          console.warn(`Línea ${i} sin código, saltando`);
          continue;
        }
        
        // DESCRIPCIÓN - con verificación cuidadosa y diagnóstico
        let descripcion = '';
        
        // Primero intentar obtener del CSV
        if (DESC_INDEX >= 0 && DESC_INDEX < campos.length) {
          descripcion = campos[DESC_INDEX].trim();
          console.log(`Descripción extraída: "${descripcion}"`);
        }
        
        // Si no tiene descripción, buscar en el mapeo directo por código
        if (!descripcion && producto.CODIGO && descripcionesFijas[producto.CODIGO]) {
          descripcion = descripcionesFijas[producto.CODIGO];
          console.log(`Usando descripción fija por código: "${descripcion}"`);
        }
        
        // Si aún no tiene, buscar en el mapeo por número
        if (!descripcion && producto['#'] && descripcionesFijas[producto['#']]) {
          descripcion = descripcionesFijas[producto['#']];
          console.log(`Usando descripción fija por número: "${descripcion}"`);
        }
        
        producto.DESCRIPCION = descripcion;
        
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
        
        // PRECIO
        if (PRECIO_INDEX >= 0 && PRECIO_INDEX < campos.length) {
          let precio = campos[PRECIO_INDEX].trim();
          // Eliminar caracteres no numéricos excepto puntos y comas
          precio = precio.replace(/[^\d.,]/g, '');
          producto.PRECIO = precio;
        } else {
          producto.PRECIO = '0';
        }
        
        // DESCUENTO
        if (DSCTO_INDEX >= 0 && DSCTO_INDEX < campos.length) {
          let descuento = campos[DSCTO_INDEX].trim();
          // Eliminar caracteres no numéricos excepto puntos y comas
          descuento = descuento.replace(/[^\d.,]/g, '');
          producto.DSCTO = descuento;
        } else {
          producto.DSCTO = '0';
        }
        
        productos.push(producto);
        
      } catch (parseError) {
        console.error(`Error al procesar línea ${i}:`, parseError);
      }
    }
    
    console.log(`Total de productos procesados: ${productos.length}`);
    return productos;
  } catch (error) {
    console.error('Error al procesar CSV:', error);
    return [];
  }
}
function dividirCSV(linea) {
  const resultado = [];
  let campoActual = '';
  let enComillas = false;
  
  for (let i = 0; i < linea.length; i++) {
    const caracter = linea[i];
    
    if (caracter === '"') {
      // Cambiar estado de comillas
      enComillas = !enComillas;
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
function encontrarIndice(encabezados, posiblesNombres) {
  for (const nombre of posiblesNombres) {
    const indice = encabezados.findIndex(h => 
      h.toUpperCase().trim() === nombre.toUpperCase().trim()
    );
    if (indice !== -1) return indice;
  }
  return -1;
}

// Asegúrate de exportar esta función para usarla en los endpoints
module.exports = { procesarCsvProductos };

// Endpoint para obtener el catálogo actual
app.get('/catalogo', (req, res) => {
  try {
    const catalogoPath = path.join(catDirPath, 'catalogo.pdf');
    
    if (!fs.existsSync(catalogoPath)) {
      return res.status(404).json({ success: false, message: 'El catálogo no está disponible' });
    }
    
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

// Endpoint para obtener información sobre el CSV de productos
app.get('/productos-info', (req, res) => {
  try {
    const productosPath = path.join(productosDirPath, 'productos.csv');
    
    if (fs.existsSync(productosPath)) {
      const stats = fs.statSync(productosPath);
      const fileDate = new Date(stats.mtime);
      
      res.json({
        success: true,
        filename: 'productos.csv',
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

// Endpoints para la administración web
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Servir archivos estáticos para la interfaz de administración
app.use(express.static(path.join(__dirname, 'public')));

// Subir un nuevo catálogo
app.post('/upload-catalogo', upload.single('catalogo'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(catDirPath, 'catalogo.pdf');

    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath);

    res.json({ success: true, message: 'Catálogo actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir catálogo:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Subir un nuevo archivo de productos
app.post('/upload-productos', upload.single('productos'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(productosDirPath, 'productos.csv');

    // Validar el formato CSV antes de guardarlo
    try {
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
      return res.status(400).json({ 
        success: false, 
        message: `Error al validar CSV: ${error.message}` 
      });
    }

    // Si el archivo es válido, guardarlo
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
    }

    fs.copyFileSync(sourcePath, destPath);
    fs.unlinkSync(sourcePath);

    res.json({ success: true, message: 'Archivo de productos actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de productos:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

// Iniciar el servidor
app.listen(PORT, () => {
  console.log(`Servidor ejecutándose en http://localhost:${PORT}`);
  console.log(`Interfaz de administración: http://localhost:${PORT}/admin`);

  procesarCsvProductos(path.join(productosDirPath, 'productos.csv'));
});