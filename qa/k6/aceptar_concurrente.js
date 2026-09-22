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
// POR QUE EL LOGIN VA EN setup()
//   Autenticar 50 cuentas cuesta un verify de bcrypt cada una. Si eso
//   ocurriera dentro del escenario medido, las peticiones de aceptacion
//   saldrian escalonadas por el costo del login y no habria carrera. En
//   setup() se paga una sola vez, antes de que el reloj empiece.
//
// POR QUE HAY UNA BARRERA DE TIEMPO
//   k6 arranca los VU casi a la vez, pero "casi" no alcanza: la PoC vive o
//   muere de que las transacciones se solapen. setup() fija un instante
//   comun y cada VU duerme hasta el. Sin esa barrera, un arranque
//   escalonado produce 1 exito por falta de concurrencia y no por
//   exclusion — el falso verde contra el que advierte SCRUM-959.
// =====================================================================

import http from 'k6/http';
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

const RPC = MODO === 'sin_exclusion'
  ? 'aceptar_solicitud_sin_exclusion'
  : 'aceptar_solicitud';

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

  // Login secuencial por lotes: paralelizar los 50 a la vez satura el
  // endpoint de Auth y algunos responden 429, que no tiene nada que ver con
  // lo que la PoC mide.
  const tokens = [];
  for (let i = 1; i <= N; i++) {
    const r = http.post(
      `${URL}/auth/v1/token?grant_type=password`,
      JSON.stringify({ email: email(i), password: PASSWORD }),
      { headers: { apikey: ANON, 'Content-Type': 'application/json' }, tags: { fase: 'login' } },
    );
    if (r.status !== 200) {
      throw new Error(`Login fallido para ${email(i)}: ${r.status} ${r.body}`);
    }
    tokens.push(JSON.parse(r.body).access_token);
  }

  // Instante comun de disparo. Se calcula DESPUES de los logins para que el
  // margen no se consuma autenticando.
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
  if (MODO === 'sin_exclusion') cuerpo.p_espera = ESPERA;

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
