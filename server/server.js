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
const asesoresDirPath = path.join(__dirname, 'asesores');
const clientesDirPath = path.join(__dirname, 'clientes');
const correosDirPath = path.join(__dirname, 'correos');
const ordenesPath = path.join(__dirname, 'ordenes');
if (!fs.existsSync(ordenesPath)) {
  fs.mkdirSync(ordenesPath, { recursive: true });
}


[uploadDir, catDirPath, tempDir, productosDirPath, asesoresDirPath, clientesDirPath, correosDirPath, ordenesPath].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

let ultimoNumeroOrden = 1;

// Intentar cargar el contador desde un archivo
try {
  const contadorPath = path.join(ordenesPath, 'contador.json');
  if (fs.existsSync(contadorPath)) {
    const data = fs.readFileSync(contadorPath, 'utf8');
    const contador = JSON.parse(data);
    ultimoNumeroOrden = contador.ultimoNumero || 1;
    console.log(`Contador de órdenes cargado: ${ultimoNumeroOrden}`);
  } else {
    // Crear el archivo si no existe
    fs.writeFileSync(contadorPath, JSON.stringify({ ultimoNumero: ultimoNumeroOrden }));
    console.log(`Archivo de contador creado con valor inicial: ${ultimoNumeroOrden}`);
  }
} catch (error) {
  console.error('Error al cargar el contador de órdenes:', error);
}

function guardarContador() {
  try {
    const contadorPath = path.join(ordenesPath, 'contador.json');
    fs.writeFileSync(contadorPath, JSON.stringify({ ultimoNumero: ultimoNumeroOrden }));
  } catch (error) {
    console.error('Error al guardar el contador de órdenes:', error);
  }
}

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

// Endpoint para confirmar que un número de orden fue utilizado
// Endpoint para confirmar e INCREMENTAR el número de orden
app.post('/confirmar-orden', (req, res) => {
  try {
    const { numeroOrden } = req.body;
    
    if (!numeroOrden) {
      return res.status(400).json({ success: false, message: 'Falta el número de orden' });
    }
    
    // Incrementar el contador ahora que se confirma el uso
    ultimoNumeroOrden++;
    
    // Guardar el nuevo valor
    guardarContador();
    
    console.log(`Orden confirmada y contador incrementado a: ${ultimoNumeroOrden}`);
    
    // Guardar registro de la orden
    const registroPath = path.join(ordenesPath, 'registro.json');
    let registro = [];
    
    if (fs.existsSync(registroPath)) {
      try {
        const data = fs.readFileSync(registroPath, 'utf8');
        registro = JSON.parse(data);
      } catch (e) {
        console.error('Error al cargar registro:', e);
      }
    }
    
    registro.push({
      numeroOrden: numeroOrden,
      contador: ultimoNumeroOrden,
      fecha: new Date().toISOString(),
      ip: req.ip
    });
    
    fs.writeFileSync(registroPath, JSON.stringify(registro, null, 2));
    
    res.json({ success: true, message: 'Orden confirmada correctamente' });
  } catch (error) {
    console.error('Error al confirmar orden:', error);
    res.status(500).json({ success: false, message: error.toString() });
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


const upload = multer({ storage: storage });

// Transportador de correo
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: process.env.EMAIL_USER || 'camilosanchezwwe@gmail.com',
    pass: process.env.EMAIL_PASS || 'xens efby pvfc qdhz'
  }
});

// Función para procesar CSV de correos de área
function procesarCsvCorreos(filePath) {
  try {
    // Leer el archivo completo
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
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
// Endpoint para obtener información sobre el CSV de correos
app.get('/correos-info', (req, res) => {
  try {
    const correosPath = path.join(correosDirPath, 'correos.csv');
    
    if (fs.existsSync(correosPath)) {
      const stats = fs.statSync(correosPath);
      const fileDate = new Date(stats.mtime);
      
      res.json({
        success: true,
        filename: 'correos.csv',
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
app.post('/upload-correos', upload.single('correos'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(correosDirPath, 'correos.csv');

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

    res.json({ success: true, message: 'Archivo de correos actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de correos:', error);
    res.status(500).json({ success: false, message: error.toString() });
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

    // Obtener la lista de correos por área (solo incluirá áreas antes de ASESOR QUE GENERA EL PEDIDO)
    const correosPath = path.join(correosDirPath, 'correos.csv');
    let correosAdicionales = [];
    
    if (fs.existsSync(correosPath)) {
      try {
        const correosPorArea = procesarCsvCorreos(correosPath);
        correosAdicionales = correosPorArea.map(c => c.MAIL);
        console.log("Correos adicionales para copia:", correosAdicionales);
      } catch (e) {
        console.error("Error al procesar correos adicionales:", e);
      }
    }

    // Lista de CC
    let ccList = [];
    
    // Agregar el asesor que hizo login
    if (asesorEmail && asesorEmail.trim()) {
      ccList.push(asesorEmail.trim());
    }
    
    // Agregar áreas adicionales (solo CARTERA, BODEGA, DIRECCION COMERCIAL)
    if (correosAdicionales.length > 0) {
      ccList = ccList.concat(correosAdicionales);
    }
    
    // Filtrar duplicados y valores vacíos
    ccList = [...new Set(ccList.filter(email => email && email.trim()))];
    
    console.log("Lista final de CC:", ccList);

    const mailOptions = {
      from: '"DAP AutoPart\'s" <camilosanchezwwe@gmail.com>',
      to: clienteEmail,
      cc: ccList.join(', '),
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

function procesarCsvClientes(filePath) {
  try {
    // Leer el archivo completo
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
    // Dividir por líneas
    const lines = fileContent.split('\n');
    
    // Buscar la línea de encabezados en las primeras 10 filas
    let headerRowIndex = -1;
    for (let i = 0; i < Math.min(10, lines.length); i++) {
      const line = lines[i].toUpperCase();
      // Buscar una línea que contenga "NIT" que probablemente sea la fila de encabezados
      if (line.includes('NIT')) {
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
        if (campos.length < 2) {
          continue;
        }
        
        // Crear objeto cliente con los campos básicos
        const cliente = {};
        
        // NIT - requerido
        if (NIT_INDEX >= 0 && NIT_INDEX < campos.length) {
          cliente['NIT CLIENTE'] = campos[NIT_INDEX].trim();
          // Si está vacío, saltar esta línea
          if (!cliente['NIT CLIENTE']) {
            continue;
          }
        } else {
          continue; // Sin NIT válido no procesamos
        }
        
        // NOMBRE - requerido
        if (NOMBRE_INDEX >= 0 && NOMBRE_INDEX < campos.length) {
          cliente['NOMBRE'] = campos[NOMBRE_INDEX].trim();
        } else {
          cliente['NOMBRE'] = `Cliente ${cliente['NIT CLIENTE']}`;
        }
        
        // Restantes campos
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

// Endpoint para obtener información sobre el CSV de clientes
app.get('/clientes-info', (req, res) => {
  try {
    const clientesPath = path.join(clientesDirPath, 'clientes.csv');
    
    if (fs.existsSync(clientesPath)) {
      const stats = fs.statSync(clientesPath);
      const fileDate = new Date(stats.mtime);
      
      res.json({
        success: true,
        filename: 'clientes.csv',
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
app.post('/upload-clientes', upload.single('clientes'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(clientesDirPath, 'clientes.csv');

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

    res.json({ success: true, message: 'Archivo de clientes actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de clientes:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});

function procesarCsvAsesores(filePath) {
  try {
    // Leer el archivo completo
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
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
      
      res.json({
        success: true,
        filename: 'asesores.csv',
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
app.post('/upload-asesores', upload.single('asesores'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No se ha subido ningún archivo' });
    }

    const sourcePath = req.file.path;
    const destPath = path.join(asesoresDirPath, 'asesores.csv');

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

    res.json({ success: true, message: 'Archivo de asesores actualizado correctamente' });
  } catch (error) {
    console.error('Error al subir archivo de asesores:', error);
    res.status(500).json({ success: false, message: error.toString() });
  }
});


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
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Servidor escuchando en http://0.0.0.0:${PORT}`);
  console.log(`Puedes acceder desde otros dispositivos usando: http://<IP_LOCAL>:${PORT}`);

  procesarCsvProductos(path.join(productosDirPath, 'productos.csv'));
});