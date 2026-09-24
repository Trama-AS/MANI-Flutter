// =====================================================================
// MANI — Harness de concurrencia para la PoC de exclusion concurrente
// =====================================================================
// Ticket: SCRUM-926 (CFG-09) · Subtareas: SCRUM-961, SCRUM-962
// Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
// Requiere aplicados, en orden:
//   supabase/poc-cfg09/10_seed_concurrencia.sql
//   supabase/poc-cfg09/20_rpc_aceptar_solicitud.sql
//
// PREGUNTA QUE RESPONDE
//   ¿El UPDATE condicional garantiza exactamente 1 asignacion exitosa bajo
//   N aceptaciones simultaneas sobre la misma solicitud?
//
// COMO CORRE
//   set -a; source .env; set +a
//   k6 run qa/k6/aceptar_concurrente.js
//
//   Variables (todas con -e VAR=valor):
//     N        aliados que compiten (default 50; el seed sembro 50)
//     MODO     'exclusion' (default) | 'sin_exclusion' (control negativo)
//     CORRIDA  etiqueta que separa corridas en la bitacora (default: fecha)
//     ESPERA   ventana del control negativo en segundos (default 0.05)
//
// POR QUE LOS TOKENS VIENEN DE UN ARCHIVO
//   Dos razones. La de metodo: autenticar N cuentas cuesta un verify de
//   bcrypt cada una, y hacerlo dentro del escenario escalonaria las
//   peticiones por el costo del login en vez de por el comportamiento de
//   la base. La practica: Supabase Auth limita el endpoint de token a ~30
//   peticiones por 5 minutos por IP, asi que 50 logins seguidos devuelven
//   429 over_request_rate_limit y abortan la corrida.
//
//   qa/k6/obtener_tokens.sh los obtiene por lotes y los deja en
//   tokens.json. Se reutilizan en todas las corridas mientras los JWT
//   sigan vigentes (1 hora por defecto).
//
// POR QUE HAY UNA BARRERA DE TIEMPO
//   k6 arranca los VU casi a la vez, pero "casi" no alcanza: la PoC vive o
//   muere de que las transacciones se solapen. setup() fija un instante
//   comun y cada VU duerme hasta el. Sin esa barrera, un arranque
//   escalonado produce 1 exito por falta de concurrencia y no por
//   exclusion — el falso verde contra el que advierte SCRUM-959.
// =====================================================================

import http from 'k6/http';
// Tokens precalculados por qa/k6/obtener_tokens.sh. Ver setup().
const TOKENS_CACHE = JSON.parse(open('./tokens.json'));
import { Counter, Trend } from 'k6/metrics';
import { check } from 'k6';

const URL      = __ENV.SUPABASE_URL;
const ANON     = __ENV.SUPABASE_ANON_KEY;
const N        = parseInt(__ENV.N || '50', 10);
const MODO     = __ENV.MODO || 'exclusion';
const ESPERA   = parseFloat(__ENV.ESPERA || '0.05');
const CORRIDA  = __ENV.CORRIDA || `${MODO}-N${N}-${new Date().toISOString().slice(0, 19)}`;

// UUIDs fijos del seed (supabase/poc-cfg09/10_seed_concurrencia.sql).
const SOLICITUD = 'a0000000-0000-4000-8000-900000000001';
const aliadoId  = (i) => `50000000-0000-4000-8000-9${String(i).padStart(11, '0')}`;
const email     = (i) => `aliado.poc.${i}@poc.mani.test`;
const PASSWORD  = 'QaSeed2026!';

// MODO decide que funcion se mide:
//   exclusion     -> el mecanismo de ADR-0021. Debe dar 1 asignacion.
//   sin_exclusion -> control negativo correcto (check-then-act). Debe dar >1.
//   control_malo  -> control negativo MAL disenado, el que proponia la
//                    primera version del informe. Da 1 asignacion aunque
//                    haya concurrencia real: por eso no servia.
const RPC = {
  sin_exclusion: 'aceptar_solicitud_sin_exclusion',
  control_malo:  'aceptar_solicitud_control_malo',
}[MODO] || 'aceptar_solicitud';

// Milisegundos de margen entre el fin de setup() y el disparo sincronizado.
const MARGEN_MS = 3000;

const exito200    = new Counter('exito_200');
const conflicto409 = new Counter('conflicto_409');
const otros       = new Counter('otros');
const latencia    = new Trend('latencia_aceptar', true);

export const options = {
  scenarios: {
    carrera: {
      executor: 'per-vu-iterations',
      vus: N,
      iterations: 1,
      maxDuration: '2m',
    },
  },
  // Umbrales del criterio de terminado del ticket. En MODO=sin_exclusion se
  // ESPERA que fallen: ese es justamente el resultado que valida el harness.
  thresholds: {
    exito_200:     ['count==1'],
    conflicto_409: [`count==${N - 1}`],
    otros:         ['count==0'],
  },
  // Un umbral incumplido marca la corrida, pero no debe abortarla: hace
  // falta la salida completa para el informe.
  throw: false,
};

export function setup() {
  if (!URL || !ANON) {
    throw new Error('Faltan SUPABASE_URL y/o SUPABASE_ANON_KEY. Cargalas desde .env.');
  }

  const tokens = TOKENS_CACHE;
  if (tokens.length < N) {
    throw new Error(
      `tokens.json trae ${tokens.length} tokens y N=${N}. Corre qa/k6/obtener_tokens.sh.`);
  }

  // Un token vencido devolveria 401 y se contaria como "otros", ensuciando
  // la metrica. Mejor fallar aqui con un mensaje claro.
  const sonda = http.post(`${URL}/rest/v1/rpc/aceptar_solicitud`,
    JSON.stringify({ p_solicitud: '00000000-0000-4000-8000-000000000000',
                     p_aliado: aliadoId(1), p_corrida: 'sonda' }),
    { headers: { apikey: ANON, Authorization: `Bearer ${tokens[0]}`,
                 'Content-Type': 'application/json' }, tags: { fase: 'sonda' } });
  if (sonda.status === 401) {
    throw new Error('Tokens vencidos. Vuelve a correr qa/k6/obtener_tokens.sh.');
  }

  return { tokens, disparo: Date.now() + MARGEN_MS, corrida: CORRIDA };
}

export default function (data) {
  const i = __VU;                    // 1..N
  const token = data.tokens[i - 1];

  // Barrera: espera activa hasta el instante comun. Se usa busy-wait y no
  // sleep() porque sleep() de k6 tiene resolucion de decimas de segundo, y
  // aqui el objetivo es que los N disparos caigan dentro de la misma
  // ventana de milisegundos.
  while (Date.now() < data.disparo) { /* spin */ }

  const cuerpo = {
    p_solicitud: SOLICITUD,
    p_aliado: aliadoId(i),
    p_corrida: data.corrida,
  };
  // Las tres variantes reciben la misma espera. No toca el mecanismo de
  // exclusion —el UPDATE sigue siendo atomico y condicional— solo alinea la
  // llegada para que las N peticiones entren a la funcion dentro de la misma
  // ventana. Sin esto llegan repartidas en ~900 ms y no compiten: darian
  // 1 asignacion por falta de carrera, no por exclusion.
  cuerpo.p_espera = ESPERA;

  const r = http.post(`${URL}/rest/v1/rpc/${RPC}`, JSON.stringify(cuerpo), {
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    tags: { fase: 'aceptar' },
  });

  latencia.add(r.timings.duration);

  if (r.status === 200) {
    exito200.add(1);
  } else if (r.status === 409) {
    conflicto409.add(1);
  } else {
    otros.add(1);
    console.error(`VU ${i}: HTTP ${r.status} — ${r.body}`);
  }

  // Los 409 son el resultado correcto para N-1 aliados, no un fallo: por eso
  // el check acepta ambos y solo marca lo que no es ninguno de los dos.
  check(r, {
    'respuesta 200 o 409': (res) => res.status === 200 || res.status === 409,
  });
}

export function teardown(data) {
  console.log(`corrida=${data.corrida} modo=${MODO} N=${N} rpc=${RPC}`);
  console.log('Verificar en la bitacora:');
  console.log(`  SELECT count(*) FROM poc_asignacion_log WHERE corrida = '${data.corrida}';`);
}
