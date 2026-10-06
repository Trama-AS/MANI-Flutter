// =====================================================================
// MANI — Benchmark de verificacion de firma JWT contra la clave publica
// =====================================================================
// Ticket: SCRUM-929 (CFG-12) · Subtarea: SCRUM-974
// Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
//
// QUE MIDE
//   El costo de verificar criptograficamente la firma de un JWT de
//   Supabase contra la clave publica del JWKS. Es exactamente lo que
//   paga el middleware de cada microservicio segun ADR-0018:
//
//     "Un middleware de autenticacion valida la firma del JWT contra la
//      clave publica de Supabase, extrae el tenant_id y lo inyecta en el
//      contexto de seguridad" (Java con JJWT/Nimbus, .NET con JwtBearer)
//
//   ADR-0018 declara esa verificacion como "sobrecarga de computo
//   marginal en cada microservicio" sin haberla medido nunca. Este
//   script pone el numero.
//
// POR QUE NO SE MIDE CONTRA LA API
//   Una peticion a PostgREST mezcla red, pool de conexiones, RLS y
//   verificacion de firma en un solo numero. PoC-001 (CFG-09) ya
//   documento que el pool domina esos tiempos y por eso dejo la latencia
//   fuera del criterio de aceptacion. La verificacion de firma es CPU
//   local y pura: se mide sola. El delta contra la API lo aporta
//   qa/k6/latencia_claims.js, como contexto, no como criterio.
//
// LAS DOS MEDICIONES
//   en_frio      Primera verificacion, incluyendo el fetch del JWKS.
//                Es lo que paga un servicio recien arrancado. El fetch
//                de red domina, asi que no es comparable con la otra.
//   en_caliente  Verificacion con el JWKS ya cacheado en memoria. Es el
//                caso normal de un servicio en regimen, y el numero que
//                responde a SCRUM-974.
//
// UMBRAL (fijado antes de ejecutar, por el DoR de tickets PoC)
//   p95 en caliente < 5 ms. Orientativo: el criterio que decide CFG-12
//   es el 100% de propagacion con 0 fugas, no este tiempo.
//
// USO
//   set -a; source .env; set +a
//   node qa/jwt/bench_verificacion.mjs [ITERACIONES]
//
// SALIDA
//   Tabla por consola y qa/jwt/evidencia/bench-<timestamp>.json
// =====================================================================

import { createRemoteJWKSet, jwtVerify, decodeProtectedHeader } from 'jose';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

const URL_BASE = process.env.SUPABASE_URL;
const ANON_KEY = process.env.SUPABASE_ANON_KEY;
const ITERACIONES = Number(process.argv[2] ?? 1000);

// Usuario de CFG-04. Sirve cualquier token valido: lo que se mide es el
// costo de verificar la firma, no el contenido de los claims.
const EMAIL = process.env.BENCH_EMAIL ?? 'aliado.t1@qa.mani.test';
const PASSWORD = process.env.BENCH_PASSWORD ?? 'QaSeed2026!';

if (!URL_BASE || !ANON_KEY) {
  console.error('Falta SUPABASE_URL o SUPABASE_ANON_KEY. Corre: set -a; source .env; set +a');
  process.exit(1);
}

const JWKS_URL = new URL(`${URL_BASE}/auth/v1/.well-known/jwks.json`);

/** Login real contra GoTrue. El token se obtiene fuera de la ventana medida. */
async function obtenerToken() {
  const r = await fetch(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  const cuerpo = await r.json();
  if (!r.ok || !cuerpo.access_token) {
    throw new Error(`Login fallido (${r.status}): ${JSON.stringify(cuerpo)}`);
  }
  return cuerpo.access_token;
}

function percentil(ordenadas, p) {
  if (ordenadas.length === 0) return null;
  const i = Math.min(ordenadas.length - 1, Math.ceil((p / 100) * ordenadas.length) - 1);
  return ordenadas[i];
}

function estadisticas(muestras) {
  const ord = [...muestras].sort((a, b) => a - b);
  const suma = ord.reduce((a, b) => a + b, 0);
  return {
    n: ord.length,
    avg_ms: suma / ord.length,
    min_ms: ord[0],
    p50_ms: percentil(ord, 50),
    p95_ms: percentil(ord, 95),
    p99_ms: percentil(ord, 99),
    max_ms: ord[ord.length - 1],
  };
}

const fmt = (x) => (x === null ? '—' : x.toFixed(4));

async function main() {
  console.log(`Proyecto: ${URL_BASE}`);
  console.log(`JWKS:     ${JWKS_URL}`);

  const token = await obtenerToken();
  const encabezado = decodeProtectedHeader(token);
  console.log(`Token:    alg=${encabezado.alg} kid=${encabezado.kid}`);

  if (encabezado.alg !== 'ES256') {
    // No es un fallo: es un cambio de configuracion del proyecto que
    // invalida la comparacion con corridas anteriores. Se avisa fuerte.
    console.warn(`AVISO: se esperaba ES256 y el proyecto emite ${encabezado.alg}. ` +
                 `El numero no es comparable con la corrida de referencia.`);
  }

  // --- En frio: JWKS sin cachear. Incluye el viaje de red. ---
  const jwksFrio = createRemoteJWKSet(JWKS_URL);
  const t0 = performance.now();
  await jwtVerify(token, jwksFrio);
  const enFrioMs = performance.now() - t0;

  // --- En caliente: JWKS ya resuelto. Solo criptografia. ---
  // Se reutiliza la instancia de arriba, que ya tiene la clave en memoria.
  await jwtVerify(token, jwksFrio); // descarta la primera, ya calentada

  const muestras = [];
  for (let i = 0; i < ITERACIONES; i++) {
    const t = performance.now();
    await jwtVerify(token, jwksFrio);
    muestras.push(performance.now() - t);
  }

  const caliente = estadisticas(muestras);

  console.log('');
  console.log(`Verificacion en frio (incluye fetch del JWKS): ${fmt(enFrioMs)} ms`);
  console.log(`Verificacion en caliente, ${caliente.n} iteraciones:`);
  console.log('');
  console.log('  metrica      ms');
  console.log('  ---------  ------');
  for (const k of ['avg_ms', 'min_ms', 'p50_ms', 'p95_ms', 'p99_ms', 'max_ms']) {
    console.log(`  ${k.replace('_ms', '').padEnd(9)}  ${fmt(caliente[k])}`);
  }

  const UMBRAL_P95_MS = 5;
  const cumple = caliente.p95_ms < UMBRAL_P95_MS;
  console.log('');
  console.log(`Umbral p95 < ${UMBRAL_P95_MS} ms: ${cumple ? 'CUMPLE' : 'NO CUMPLE'} ` +
              `(p95 = ${fmt(caliente.p95_ms)} ms)`);

  const evidencia = {
    ticket: 'SCRUM-974',
    ejecutado: new Date().toISOString(),
    proyecto: URL_BASE,
    algoritmo: encabezado.alg,
    kid: encabezado.kid,
    runtime: `node ${process.version}`,
    plataforma: `${process.platform}/${process.arch}`,
    iteraciones: ITERACIONES,
    en_frio_ms: enFrioMs,
    en_caliente: caliente,
    umbral_p95_ms: UMBRAL_P95_MS,
    cumple,
  };

  const dir = join(AQUI, 'evidencia');
  mkdirSync(dir, { recursive: true });
  const salida = join(dir, `bench-${evidencia.ejecutado.replace(/[:.]/g, '-')}.json`);
  writeFileSync(salida, JSON.stringify(evidencia, null, 2) + '\n');
  console.log(`\nEvidencia: ${salida}`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
