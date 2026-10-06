// =====================================================================
// MANI — Delta de latencia autenticado vs. anonimo (contexto de SCRUM-974)
// =====================================================================
// Ticket: SCRUM-929 (CFG-12) · Subtarea: SCRUM-974
// Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
// Requiere aplicados: supabase/poc-cfg12/10_hook_claims_tenant.sql (con el
//   hook registrado en Authentication > Hooks) y 20_seed_identidad.sql
//
// QUE MIDE, Y QUE NO
//   La medicion que responde a SCRUM-974 es otra: el costo de verificar
//   la firma ES256 contra el JWKS, que mide qa/jwt/bench_verificacion.mjs
//   y que salio en p95 = 0.1169 ms. Ese es el numero que ADR-0018
//   atribuye al middleware de Java y .NET.
//
//   Este script aporta CONTEXTO: cuanto pesa ese costo dentro de una
//   peticion real. Compara la misma consulta con token valido y con solo
//   la anon key, y reporta la diferencia.
//
//   ⚠️ NO ES UN CRITERIO DE ACEPTACION. PoC-001 (CFG-09) ya documento que
//   el pool de PostgREST domina estos tiempos: alli http_req_duration
//   paso de 3.09 s a 9.04 s de media entre dos corridas que solo
//   diferian en el mecanismo bajo prueba. Una latencia medida contra un
//   ambiente compartido, por red, no decide si esta PoC cumple. Se
//   registra y se interpreta; no se compara contra un umbral.
//
// POR QUE 1 VU Y SECUENCIAL
//   Por la misma razon. Con varios VU las peticiones hacen cola en el
//   pool y lo que se mide es la cola, no el costo de autenticar. Aqui
//   interesa el camino limpio: una peticion a la vez, alternando los dos
//   modos en la misma iteracion para que cualquier variacion de red les
//   afecte por igual.
//
// POR QUE EL USUARIO ES hook.t1
//   Su raw_app_meta_data no lleva claims de tenant: los del token los
//   pone el hook. Medir contra el es medir el camino que esta PoC
//   construyo, no el del seed de CFG-04.
//
// COMO CORRE
//   set -a; source .env; set +a
//   k6 run qa/k6/latencia_claims.js
//
//   Variables (con -e VAR=valor):
//     N       iteraciones por modo (default 100)
//     EMAIL   cuenta a usar (default hook.t1@cfg12.mani.test)
// =====================================================================

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const URL_BASE = __ENV.SUPABASE_URL;
const ANON_KEY = __ENV.SUPABASE_ANON_KEY;
const N        = Number(__ENV.N || 100);
const EMAIL    = __ENV.EMAIL || 'hook.t1@cfg12.mani.test';
const PASSWORD = __ENV.PASSWORD || 'QaSeed2026!';

if (!URL_BASE || !ANON_KEY) {
  throw new Error('Falta SUPABASE_URL o SUPABASE_ANON_KEY. Corre: set -a; source .env; set +a');
}

const t_auth  = new Trend('latencia_autenticado', true);
const t_anon  = new Trend('latencia_anonimo', true);
const filas_auth = new Counter('filas_devueltas_autenticado');
const filas_anon = new Counter('filas_devueltas_anonimo');

export const options = {
  scenarios: {
    secuencial: {
      executor: 'per-vu-iterations',
      vus: 1,
      iterations: N,
      maxDuration: '10m',
    },
  },
  // Sin thresholds de latencia a proposito: ver la nota de arriba. El
  // unico threshold es de correccion, no de tiempo.
  thresholds: {
    'checks': ['rate==1.0'],
  },
};

export function setup() {
  // El login queda fuera de la ventana medida: cuesta un verify de bcrypt
  // y contaminaria la primera iteracion.
  const r = http.post(
    `${URL_BASE}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' } }
  );

  if (r.status !== 200) {
    throw new Error(`Login fallido (${r.status}): ${r.body}`);
  }

  const token = r.json('access_token');

  // Se comprueba que el token venga del hook antes de medir nada. Si el
  // hook estuviera desactivado, este script mediria otra cosa y no lo
  // diria: la peticion autenticada devolveria 0 filas y el delta
  // resultante seria el de una consulta vacia.
  const payload = JSON.parse(decodificarPayload(token));
  const tenant = payload.app_metadata && payload.app_metadata.tenant_id;
  if (!tenant) {
    throw new Error(
      `El token de ${EMAIL} no trae app_metadata.tenant_id. ` +
      `¿Esta el hook registrado y activo en Authentication > Hooks?`
    );
  }

  return { token, tenant, alg: JSON.parse(decodificarPayload(token, 0)).alg };
}

/** base64url -> texto. El runtime de k6 no trae Buffer ni atob. */
function decodificarPayload(token, indice = 1) {
  const seg = token.split('.')[indice];
  const b64 = seg.replace(/-/g, '+').replace(/_/g, '/');
  const relleno = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  return String.fromCharCode.apply(null, new Uint8Array(decodeBase64(relleno)));
}

function decodeBase64(s) {
  const ABC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const bytes = [];
  let buffer = 0, bits = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '=') break;
    const v = ABC.indexOf(c);
    if (v < 0) continue;
    buffer = (buffer << 6) | v;
    bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push((buffer >> bits) & 0xff); }
  }
  return bytes;
}

export default function (data) {
  const url = `${URL_BASE}/rest/v1/sitio?select=id,tenant_id`;

  // --- Autenticado: firma verificada + RLS evaluada con el claim ---
  const auth = http.get(url, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${data.token}` },
    tags: { modo: 'autenticado' },
  });
  t_auth.add(auth.timings.duration);

  // --- Anonimo: misma consulta, sin token. RLS no encuentra claim ---
  const anon = http.get(url, {
    headers: { apikey: ANON_KEY },
    tags: { modo: 'anonimo' },
  });
  t_anon.add(anon.timings.duration);

  const nAuth = auth.status === 200 ? auth.json().length : -1;
  const nAnon = anon.status === 200 ? anon.json().length : -1;
  filas_auth.add(nAuth > 0 ? nAuth : 0);
  filas_anon.add(nAnon > 0 ? nAnon : 0);

  // La correccion SI se verifica. Si el autenticado dejara de ver sus
  // filas, o el anonimo empezara a verlas, los tiempos dejan de
  // significar lo que se cree y la corrida no sirve.
  check(null, {
    'el autenticado responde 200': () => auth.status === 200,
    'el autenticado ve filas de su tenant': () => nAuth > 0,
    'el anonimo no ve ninguna fila': () => nAnon === 0,
  });
}

export function handleSummary(data) {
  const m = data.metrics;
  const p = (nombre, est) => (m[nombre] && m[nombre].values[est]) || 0;

  const resumen = {
    ticket: 'SCRUM-974',
    proposito: 'contexto del costo de verificacion dentro de una peticion real; no es criterio de aceptacion',
    ejecutado: new Date().toISOString(),
    proyecto: URL_BASE,
    iteraciones_por_modo: N,
    cuenta: EMAIL,
    autenticado_ms: {
      avg: p('latencia_autenticado', 'avg'),
      med: p('latencia_autenticado', 'med'),
      p95: p('latencia_autenticado', 'p(95)'),
      max: p('latencia_autenticado', 'max'),
    },
    anonimo_ms: {
      avg: p('latencia_anonimo', 'avg'),
      med: p('latencia_anonimo', 'med'),
      p95: p('latencia_anonimo', 'p(95)'),
      max: p('latencia_anonimo', 'max'),
    },
    delta_ms: {
      avg: p('latencia_autenticado', 'avg') - p('latencia_anonimo', 'avg'),
      med: p('latencia_autenticado', 'med') - p('latencia_anonimo', 'med'),
      p95: p('latencia_autenticado', 'p(95)') - p('latencia_anonimo', 'p(95)'),
    },
    checks_fallidos: (m.checks && m.checks.values.fails) || 0,
  };

  const linea = (k, o) =>
    `  ${k.padEnd(14)} avg ${o.avg.toFixed(2).padStart(8)}  med ${o.med.toFixed(2).padStart(8)}  p95 ${o.p95.toFixed(2).padStart(8)}`;

  const texto = [
    '',
    `Delta de latencia autenticado vs. anonimo — ${N} iteraciones de cada uno`,
    '',
    linea('autenticado', resumen.autenticado_ms),
    linea('anonimo', resumen.anonimo_ms),
    linea('delta', resumen.delta_ms),
    '',
    `  checks fallidos: ${resumen.checks_fallidos}`,
    '',
    '  El delta incluye la verificacion de firma Y la evaluacion de RLS con',
    '  el claim, que el anonimo no paga porque no tiene claim que evaluar.',
    '  No es atribuible solo a la firma: para eso esta el benchmark aislado',
    '  de qa/jwt/bench_verificacion.mjs.',
    '',
  ].join('\n');

  return {
    stdout: texto,
    'qa/k6/evidencia/latencia-claims.json': JSON.stringify(resumen, null, 2) + '\n',
  };
}
