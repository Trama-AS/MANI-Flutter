// =====================================================================
// MANI — Utilidades compartidas de la PoC de Storage KYC (CFG-13)
// =====================================================================
// Ticket: SCRUM-930 (CFG-13) · Ambiente: SOLO QA (hpsxdotaizzclkeufzct)
//
// Todo va con fetch contra la API REST de Storage, sin supabase-js: las
// mismas rutas que usa la suite de Newman, asi un numero medido aqui y un
// caso de la suite hablan del mismo endpoint. supabase_flutter llama a
// estas mismas rutas por debajo.
//
// Nunca se usa service_role: bypassa RLS y la PoC no mediria nada.
// =====================================================================

export const URL_BASE = process.env.SUPABASE_URL;
export const ANON_KEY = process.env.SUPABASE_ANON_KEY;
export const PASSWORD = process.env.QA_PASSWORD ?? 'QaSeed2026!';
export const BUCKET = 'kyc-documentos';

if (!URL_BASE || !ANON_KEY) {
  console.error('Falta SUPABASE_URL o SUPABASE_ANON_KEY. Corre: set -a; source .env; set +a');
  process.exit(1);
}

const b64u = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');

/** Login real contra GoTrue. Devuelve token, uid y tenant del JWT (puestos por el hook). */
export async function login(email) {
  const r = await fetch(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  const cuerpo = await r.json();
  if (!r.ok || !cuerpo.access_token) {
    throw new Error(`Login fallido para ${email} (${r.status}): ${cuerpo.error_description ?? cuerpo.msg ?? r.statusText}`);
  }
  const claims = JSON.parse(b64u(cuerpo.access_token.split('.')[1]));
  const tenant = claims.app_metadata?.tenant_id;
  if (!tenant) throw new Error(`El JWT de ${email} no trae app_metadata.tenant_id: ¿esta registrado el hook de CFG-12?`);
  return { email, token: cuerpo.access_token, uid: claims.sub, tenant, rol: claims.app_metadata?.user_role };
}

const cab = (token, extra = {}) => ({ apikey: ANON_KEY, Authorization: `Bearer ${token}`, ...extra });

/** Sube (o reemplaza) un objeto con el JWT del usuario. */
export async function subir(token, ruta, cuerpo, tipo = 'application/pdf') {
  return fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${ruta}`, {
    method: 'POST',
    headers: cab(token, { 'Content-Type': tipo, 'x-upsert': 'true' }),
    body: cuerpo,
  });
}

/** Emite una URL firmada. Devuelve { r, url } con url absoluta o null. */
export async function firmar(token, ruta, expiraEn = 60) {
  const r = await fetch(`${URL_BASE}/storage/v1/object/sign/${BUCKET}/${ruta}`, {
    method: 'POST',
    headers: cab(token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ expiresIn: expiraEn }),
  });
  const cuerpo = await r.json().catch(() => ({}));
  const rel = cuerpo.signedURL ?? cuerpo.signedUrl;
  return { r, url: rel ? `${URL_BASE}/storage/v1${rel}` : null };
}

/** Descarga por URL firmada: sin apikey ni JWT, como la usaria cualquiera que la tenga. */
export async function descargarFirmada(url) {
  return fetch(url);
}

export async function borrar(token, rutas) {
  return fetch(`${URL_BASE}/storage/v1/object/${BUCKET}`, {
    method: 'DELETE',
    headers: cab(token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ prefixes: rutas }),
  });
}

/**
 * PDF sintetico de `bytes` bytes. Cabecera y trailer validos con un
 * comentario de relleno: pasa el filtro de MIME del bucket sin llevar
 * datos reales de nadie.
 */
export function pdfSintetico(bytes) {
  const cabecera = Buffer.from('%PDF-1.4\n%MANI CFG-13 documento sintetico de prueba\n');
  const cola = Buffer.from('\n%%EOF\n');
  const relleno = Buffer.alloc(Math.max(0, bytes - cabecera.length - cola.length), 0x25); // '%'
  return Buffer.concat([cabecera, relleno, cola]);
}

function percentil(ordenadas, p) {
  if (ordenadas.length === 0) return null;
  const i = Math.min(ordenadas.length - 1, Math.ceil((p / 100) * ordenadas.length) - 1);
  return ordenadas[i];
}

export function estadisticas(muestras) {
  const ord = [...muestras].sort((a, b) => a - b);
  const suma = ord.reduce((a, b) => a + b, 0);
  return {
    n: ord.length,
    avg_ms: suma / ord.length,
    min_ms: ord[0],
    p50_ms: percentil(ord, 50),
    p95_ms: percentil(ord, 95),
    max_ms: ord[ord.length - 1],
  };
}
