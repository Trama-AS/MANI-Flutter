// =====================================================================
// MANI — Benchmark de tiempo de carga de documentos KYC (CFG-13)
// =====================================================================
// Ticket: SCRUM-930 (CFG-13) · Subtarea: SCRUM-979
// Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
//
// QUE MIDE
//   Por cada tamaño (100 KB, 1 MB, 5 MB), N subidas de extremo a extremo
//   desde este cliente: desde que sale la peticion hasta que Storage
//   responde 200. Incluye red, TLS reutilizado, evaluacion de
//   kyc_isolation en el INSERT y escritura en el backend de Storage. Es
//   lo que percibe el aliado en la app.
//
//   Ademas, sobre los objetos recien subidos: la emision de la URL
//   firmada (createSignedUrl) y su descarga.
//
// UMBRAL (fijado antes de ejecutar, por el DoR de tickets PoC; publicado
// en SCRUM-930)
//   Carga de 1 MB:   p95 < 2000 ms   <- el que decide
//   createSignedUrl: p95 < 500 ms
//   100 KB y 5 MB, y la descarga firmada: solo se reportan.
//
// CONTEXTO QUE HAY QUE REPORTAR CON EL NUMERO
//   Se mide desde la maquina que corre el script, no desde un celular en
//   red movil. El informe tiene que decir desde donde se corrio.
//
// USO
//   set -a; source .env; set +a
//   node qa/storage/bench_carga.mjs [N]        (N por tamaño, default 30)
//
// SALIDA
//   Tabla por consola y qa/storage/evidencia/bench-carga-<timestamp>.json.
//   Borra sus objetos al terminar (carpeta bench/ del aliado).
// =====================================================================

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { URL_BASE, login, subir, firmar, descargarFirmada, borrar, pdfSintetico, estadisticas } from './comun.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));
const N = Number(process.argv[2] ?? 30);
const CALENTAMIENTO = 3;
const EMAIL = process.env.BENCH_EMAIL ?? 'aliado.t1@qa.mani.test';

const TAMANOS = [
  { etiqueta: '100KB', bytes: 100 * 1024 },
  { etiqueta: '1MB', bytes: 1024 * 1024 },
  { etiqueta: '5MB', bytes: 5 * 1024 * 1024 },
];
const UMBRAL_CARGA_1MB_P95_MS = 2000;
const UMBRAL_FIRMA_P95_MS = 500;

async function cronometrar(fn) {
  const t = performance.now();
  const r = await fn();
  return { r, ms: performance.now() - t };
}

async function main() {
  const u = await login(EMAIL);
  const corrida = new Date().toISOString().replace(/[:.]/g, '-');
  const base = `${u.tenant}/${u.uid}/bench/${corrida}`;
  console.log(`Proyecto: ${URL_BASE}`);
  console.log(`Usuario:  ${u.email} (rol ${u.rol})`);
  console.log(`N=${N} por tamaño, ${CALENTAMIENTO} de calentamiento descartadas\n`);

  const rutas = [];
  const resultados = {};
  const errores = [];

  for (const { etiqueta, bytes } of TAMANOS) {
    const pdf = pdfSintetico(bytes);
    const carga = [], firma = [], descarga = [];

    for (let i = -CALENTAMIENTO; i < N; i++) {
      const ruta = `${base}/${etiqueta}-${i < 0 ? `w${-i}` : i}.pdf`;
      rutas.push(ruta);

      const s = await cronometrar(() => subir(u.token, ruta, pdf));
      if (!s.r.ok) { errores.push({ etiqueta, i, paso: 'subir', status: s.r.status, cuerpo: await s.r.text() }); continue; }
      await s.r.arrayBuffer();

      const f = await cronometrar(() => firmar(u.token, ruta, 60));
      if (!f.r.r.ok || !f.r.url) { errores.push({ etiqueta, i, paso: 'firmar', status: f.r.r.status }); continue; }

      const d = await cronometrar(async () => {
        const rd = await descargarFirmada(f.r.url);
        await rd.arrayBuffer(); // el tiempo incluye bajar el cuerpo completo
        return rd;
      });
      if (!d.r.ok) { errores.push({ etiqueta, i, paso: 'descargar', status: d.r.status }); continue; }

      if (i < 0) continue;
      carga.push(s.ms); firma.push(f.ms); descarga.push(d.ms);
    }

    resultados[etiqueta] = {
      bytes,
      carga: estadisticas(carga),
      firma: estadisticas(firma),
      descarga_firmada: estadisticas(descarga),
    };
    if (carga.length < N) {
      throw new Error(`${etiqueta}: solo ${carga.length}/${N} ciclos completos. Primer error: ${JSON.stringify(errores[0])}`);
    }
    const c = resultados[etiqueta].carga;
    console.log(`${etiqueta.padEnd(6)} carga p50=${c.p50_ms.toFixed(0)} p95=${c.p95_ms.toFixed(0)} max=${c.max_ms.toFixed(0)} ms` +
                `  | firma p95=${resultados[etiqueta].firma.p95_ms.toFixed(0)} ms` +
                `  | descarga p95=${resultados[etiqueta].descarga_firmada.p95_ms.toFixed(0)} ms`);
  }

  // La firma no depende del tamaño del objeto: el umbral se evalua contra
  // el peor p95 de las tres series.
  const p95Carga1MB = resultados['1MB'].carga.p95_ms;
  const p95FirmaMax = Math.max(...TAMANOS.map(({ etiqueta }) => resultados[etiqueta].firma.p95_ms));
  const cumpleCarga = p95Carga1MB < UMBRAL_CARGA_1MB_P95_MS;
  const cumpleFirma = p95FirmaMax < UMBRAL_FIRMA_P95_MS;

  console.log('');
  console.log(`Carga 1 MB  p95 < ${UMBRAL_CARGA_1MB_P95_MS} ms: ${cumpleCarga ? 'CUMPLE' : 'NO CUMPLE'} (p95 = ${p95Carga1MB.toFixed(0)} ms)`);
  console.log(`Firma       p95 < ${UMBRAL_FIRMA_P95_MS} ms: ${cumpleFirma ? 'CUMPLE' : 'NO CUMPLE'} (peor p95 = ${p95FirmaMax.toFixed(0)} ms)`);
  if (errores.length) console.log(`\n${errores.length} error(es) — ver la evidencia.`);

  const rb = await borrar(u.token, rutas);
  console.log(`\nLimpieza: ${rutas.length} objetos, status ${rb.status}`);

  const evidencia = {
    ticket: 'SCRUM-979',
    ejecutado: new Date().toISOString(),
    proyecto: URL_BASE,
    usuario: u.email,
    runtime: `node ${process.version}`,
    plataforma: `${process.platform}/${process.arch}`,
    n_por_tamano: N,
    calentamiento_descartado: CALENTAMIENTO,
    resultados,
    umbrales: { carga_1mb_p95_ms: UMBRAL_CARGA_1MB_P95_MS, firma_p95_ms: UMBRAL_FIRMA_P95_MS },
    cumple: { carga_1mb: cumpleCarga, firma: cumpleFirma },
    errores,
    limpieza_status: rb.status,
  };

  const dir = join(AQUI, 'evidencia');
  mkdirSync(dir, { recursive: true });
  const salida = join(dir, `bench-carga-${corrida}.json`);
  writeFileSync(salida, JSON.stringify(evidencia, null, 2) + '\n');
  console.log(`Evidencia: ${salida}`);
  if (errores.length) process.exit(1);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
