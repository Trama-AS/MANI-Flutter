// =====================================================================
// MANI — Redactor de la evidencia de Newman
// =====================================================================
// Ticket: SCRUM-929 (CFG-12)
//
// POR QUE EXISTE
//   El reporte JSON de newman guarda la peticion completa, incluidas las
//   cabeceras `apikey` y `Authorization`, y los cuerpos de respuesta de
//   los logins — que traen access_token y refresh_token. Versionar eso
//   tal cual publica credenciales de sesion en el repositorio.
//
//   CFG-09 resolvio el mismo problema gitignoreando qa/k6/tokens.json.
//   Aqui no sirve gitignorar el reporte entero: ES la evidencia que el
//   punto 2 del DoD pide adjuntar. Se versiona redactado.
//
// QUE REDACTA
//   * Valores de las cabeceras `apikey` y `Authorization`.
//   * `access_token`, `refresh_token` y `provider_token` de los cuerpos.
//   * Cualquier cadena con forma de JWT en el resto del reporte.
//   * Los cuerpos de respuesta, que newman NO guarda como texto sino en
//     `response.stream` como Buffer serializado ({type:'Buffer',data:[…]}).
//     Es el escondite que importa: ahi viven enteros los access_token y
//     refresh_token de cada login. Una primera version de este archivo no
//     lo miraba y reportaba "0 tokens redactados" sobre un archivo que los
//     tenia todos. Se descubrio al verificar por que el conteo daba cero.
//
// QUE CONSERVA
//   Aserciones, nombres de prueba, codigos de estado, tiempos y tamaños:
//   todo lo que hace de esto una evidencia legible. Los cuerpos se
//   conservan con sus claves y su estructura; solo se sustituyen los
//   valores sensibles.
//
// USO
//   node qa/newman/redactar_evidencia.mjs <entrada.json> <salida.json> [anon_key]
//
//   El tercer argumento es opcional: si se pasa, esa cadena exacta se
//   redacta donde aparezca. La anon key es publica por diseño (viaja
//   embebida en el cliente Flutter), pero no hace falta versionarla.
// =====================================================================

import fs from 'node:fs';

const [entrada, salida, anonKey] = process.argv.slice(2);
if (!entrada || !salida) {
  console.error('Uso: node redactar_evidencia.mjs <entrada.json> <salida.json> [anon_key]');
  process.exit(1);
}

const CABECERAS = /^(apikey|authorization|x-supabase-auth)$/i;
const CLAVES    = /^(access_token|refresh_token|provider_token|provider_refresh_token)$/i;
// Tres segmentos base64url separados por puntos, con el primero decodificable
// como cabecera JWT. El largo minimo evita confundirlo con un uuid con puntos.
const JWT = /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g;

let cabeceras = 0, claves = 0, sueltos = 0, cuerpos = 0;

/** Redacta el texto de un cuerpo: claves conocidas primero, JWT sueltos despues. */
const limpiarTexto = (texto) => {
  let t = texto;
  t = t.replace(/"(access_token|refresh_token|provider_token|provider_refresh_token)"\s*:\s*"[^"]*"/g,
                (_, k) => { claves++; return `"${k}":"<redactado>"`; });
  const antes = t;
  t = t.replace(JWT, '<jwt-redactado>');
  if (t !== antes) sueltos++;
  if (anonKey) t = t.split(anonKey).join('<anon-key-redactada>');
  return t;
};

const limpiar = (valor, clave) => {
  if (typeof valor === 'string') {
    if (clave && CLAVES.test(clave)) { claves++; return '<redactado>'; }
    let v = valor.replace(JWT, (m) => { sueltos++; return '<jwt-redactado>'; });
    if (anonKey) v = v.split(anonKey).join('<anon-key-redactada>');
    return v;
  }
  if (Array.isArray(valor)) return valor.map(v => limpiar(v));
  if (valor && typeof valor === 'object') {
    // Cabecera de Postman: { key, value, ... }
    if (typeof valor.key === 'string' && CABECERAS.test(valor.key) && 'value' in valor) {
      cabeceras++;
      return { ...valor, value: '<redactado>' };
    }
    // Cuerpo de respuesta: Buffer serializado. Es donde newman guarda los
    // access_token y refresh_token de cada login.
    if (valor.type === 'Buffer' && Array.isArray(valor.data)) {
      cuerpos++;
      const texto = Buffer.from(valor.data).toString('utf8');
      const limpio = limpiarTexto(texto);
      return { type: 'Buffer', data: Array.from(Buffer.from(limpio, 'utf8')) };
    }
    return Object.fromEntries(Object.entries(valor).map(([k, v]) => [k, limpiar(v, k)]));
  }
  return valor;
};

const original = JSON.parse(fs.readFileSync(entrada, 'utf8'));
const limpio = limpiar(original);
fs.writeFileSync(salida, JSON.stringify(limpio, null, 2) + '\n');

// Verificacion. No basta con buscar JWT en el texto del archivo: los
// cuerpos viven dentro de arrays de bytes, asi que hay que decodificarlos
// y volver a mirar. Si algo sobrevive, el redactor fallo y no se commitea
// "casi limpio".
const salidaJson = JSON.parse(fs.readFileSync(salida, 'utf8'));
let restantes = 0, anonRestantes = 0;

const auditar = (v) => {
  if (typeof v === 'string') {
    restantes += (v.match(JWT) || []).length;
    if (anonKey && v.includes(anonKey)) anonRestantes++;
    return;
  }
  if (Array.isArray(v)) return v.forEach(auditar);
  if (v && typeof v === 'object') {
    if (v.type === 'Buffer' && Array.isArray(v.data)) return auditar(Buffer.from(v.data).toString('utf8'));
    Object.values(v).forEach(auditar);
  }
};
auditar(salidaJson);

console.log(`cabeceras redactadas: ${cabeceras}`);
console.log(`cuerpos de respuesta redactados: ${cuerpos}`);
console.log(`claves de token redactadas: ${claves}`);
console.log(`cadenas con JWT redactadas: ${sueltos}`);
console.log(`JWT restantes tras decodificar los cuerpos: ${restantes}`);
if (anonKey) console.log(`anon key restante: ${anonRestantes}`);

if (restantes > 0 || anonRestantes > 0) {
  console.error('FALLO: quedaron credenciales sin redactar. No commitear este archivo.');
  process.exit(1);
}
