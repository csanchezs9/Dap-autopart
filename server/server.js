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


// Reemplaza la función procesarCsvProductos con esta versión mejorada
// Reemplaza la función procesarCsvProductos en server.js con esta versión mejorada
function procesarCsvProductos(filePath) {
  try {
    // Leer el archivo completo
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
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