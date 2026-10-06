// =====================================================================
// MANI — Latencia extremo a extremo de "aliados validos" (CFG-10)
// =====================================================================
// Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-969
// Ambiente: SOLO QA (proyecto Supabase MANI-QA)
// Requiere aplicados: supabase/poc-cfg10/10, 20, 30 y 60, y un nivel
//   sembrado (poc_cfg10.sembrar(10000) es el que se reporta).
//
// QUE MIDE
//   QS-08: "listado entregado en menos de 1 segundo con 20 usuarios
//   buscando a la vez". 20 VUs en lazo cerrado, sin tiempo de espera entre
//   peticiones (siempre hay 20 consultas en vuelo: mas exigente que 20
//   personas reales), contra la RPC public.poc_cfg10_aliados_validos via
//   PostgREST, con el JWT de un aliado del tenant grande. Incluye red,
//   TLS, PostgREST, verificacion del JWT y RLS.
//
//   Las cuatro variantes corren una despues de otra, no a la vez, para que
//   no compitan por el pool de PostgREST entre ellas.
//
// UMBRAL (fijado antes de ejecutar y publicado en SCRUM-927)
//   p95 < 1000 ms por variante (QS-08). Como en PoC-001 (CFG-09), el
//   numero depende del pool de PostgREST y de la red del que corre el
//   script: el informe tiene que decir desde donde se corrio. El umbral
//   que decide la PoC es el de base de datos (40_medir.sql).
//
// COMO CORRE
//   set -a; source .env; set +a
//   k6 run qa/k6/latencia_cobertura.js
//
//   Variables (con -e VAR=valor):
//     VUS       usuarios concurrentes por variante (default 20)
//     DURACION  duracion por variante (default 60s)
//     EMAIL     cuenta a usar (default aliado.poc.1@poc.mani.test, tenant
//               PoC Concurrencia CFG-09, el tenant grande del seed)
//
// SALIDA
//   Resumen por consola y qa/k6/evidencia/latencia-cobertura-<fecha>.json
// =====================================================================

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import encoding from 'k6/encoding';

const URL_BASE = __ENV.SUPABASE_URL;
const ANON_KEY = __ENV.SUPABASE_ANON_KEY;
const VUS      = Number(__ENV.VUS || 20);
const DURACION = __ENV.DURACION || '60s';
const EMAIL    = __ENV.EMAIL || 'aliado.poc.1@poc.mani.test';
const PASSWORD = __ENV.PASSWORD || 'QaSeed2026!';

const TENANT_GRANDE = '10000000-0000-4000-8000-900000000001';
const VARIANTES = ['zona', 'postgis', 'bbox', 'geohash'];

if (!URL_BASE || !ANON_KEY) {
  throw new Error('Falta SUPABASE_URL o SUPABASE_ANON_KEY. Corre: set -a; source .env; set +a');
}

const latencia = {};
const filas = {};
for (const v of VARIANTES) {
  latencia[v] = new Trend(`latencia_${v}`, true);
  filas[v] = new Counter(`filas_${v}`);
}

function segundos(d) {
  const m = /^(\d+)(s|m)$/.exec(d);
  if (!m) throw new Error(`DURACION invalida: ${d} (usa p. ej. 60s o 2m)`);
  return Number(m[1]) * (m[2] === 'm' ? 60 : 1);
}

const PAUSA = 10;
const scenarios = {};
VARIANTES.forEach((v, i) => {
  scenarios[v] = {
    executor: 'constant-vus',
    vus: VUS,
    duration: DURACION,
    startTime: `${i * (segundos(DURACION) + PAUSA)}s`,
    env: { VARIANTE: v },
    tags: { variante: v },
    gracefulStop: '5s',
  };
});

const thresholds = { checks: ['rate==1.0'] };
for (const v of VARIANTES) {
  thresholds[`latencia_${v}`] = ['p(95)<1000'];
}

export const options = { scenarios, thresholds, summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'] };

export function setup() {
  // El login queda fuera de la ventana medida.
  const r = http.post(
    `${URL_BASE}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' } }
  );
  if (r.status !== 200) {
    throw new Error(`Login fallido (${r.status}): ${r.body}`);
  }
  const token = r.json('access_token');

  // Si el token no trae el tenant grande, RLS devolveria 0 filas y se
  // mediria una consulta vacia sin que nada fallara.
  const payload = JSON.parse(encoding.b64decode(token.split('.')[1], 'rawurl', 's'));
  const tenant = payload.app_metadata && payload.app_metadata.tenant_id;
  if (tenant !== TENANT_GRANDE) {
    throw new Error(`El token de ${EMAIL} trae tenant ${tenant}, se esperaba ${TENANT_GRANDE}`);
  }

  const e = http.post(`${URL_BASE}/rest/v1/rpc/poc_cfg10_entradas`, '{}', {
    headers: cabeceras(token),
  });
  if (e.status !== 200) {
    throw new Error(`No se pudieron leer las entradas (${e.status}): ${e.body}`);
  }
  // PostgREST de Supabase corta en 1000 filas (max-rows). Las 50 que no
  // llegan son las ultimas; da igual cuales, aqui no hay calentamiento.
  const entradas = e.json();
  if (entradas.length !== 1000) {
    throw new Error(`Se esperaban 1000 entradas del tenant grande, llegaron ${entradas.length}. ¿Se sembro el nivel?`);
  }
  return { token, entradas };
}

function cabeceras(token) {
  return {
    apikey: ANON_KEY,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

export default function (datos) {
  const v = __ENV.VARIANTE;
  // Cada VU recorre las entradas desde un desplazamiento distinto, asi las
  // 20 consultas en vuelo no piden la misma zona a la vez.
  const e = datos.entradas[(__VU * 131 + __ITER) % datos.entradas.length];
  const cuerpo = v === 'zona'
    ? { p_variante: v, p_categoria_id: e.categoria_id, p_zona_id: e.zona_id }
    : { p_variante: v, p_categoria_id: e.categoria_id, p_lat: e.lat, p_lon: e.lon };

  const r = http.post(`${URL_BASE}/rest/v1/rpc/poc_cfg10_aliados_validos`, JSON.stringify(cuerpo), {
    headers: cabeceras(datos.token),
    tags: { variante: v },
  });

  const ok = check(r, {
    'status 200': (x) => x.status === 200,
    'devuelve lista': (x) => Array.isArray(x.json()),
  });
  if (ok) {
    latencia[v].add(r.timings.duration);
    filas[v].add(r.json().length);
  }
}

export function handleSummary(data) {
  const fecha = new Date().toISOString().replace(/[:.]/g, '-');
  const resumen = {
    ticket: 'SCRUM-927 (CFG-10)',
    fecha: new Date().toISOString(),
    vus: VUS,
    duracion_por_variante: DURACION,
    cuenta: EMAIL,
    umbral: 'p95 < 1000 ms por variante (QS-08)',
    checks_ok: data.metrics.checks ? data.metrics.checks.values.rate : null,
    variantes: {},
  };
  let texto = `\nCFG-10 · latencia extremo a extremo · ${VUS} VUs · ${DURACION} por variante\n`;
  for (const v of VARIANTES) {
    const m = data.metrics[`latencia_${v}`];
    const f = data.metrics[`filas_${v}`];
    if (!m) continue;
    const s = m.values;
    const filasMedia = f && s.count ? f.values.count / s.count : null;
    resumen.variantes[v] = {
      peticiones: s.count,
      p50_ms: s.med, p95_ms: s['p(95)'], p99_ms: s['p(99)'], media_ms: s.avg, max_ms: s.max,
      filas_media: filasMedia,
      cumple: s['p(95)'] < 1000,
    };
    texto += `  ${v.padEnd(8)} n=${String(s.count).padStart(6)}  p50=${s.med.toFixed(1)} ms  p95=${s['p(95)'].toFixed(1)} ms  p99=${s['p(99)'].toFixed(1)} ms  max=${s.max.toFixed(1)} ms  ${s['p(95)'] < 1000 ? 'cumple' : 'NO cumple'}\n`;
  }
  return {
    stdout: texto,
    [`qa/k6/evidencia/latencia-cobertura-${fecha}.json`]: JSON.stringify(resumen, null, 2),
  };
}
