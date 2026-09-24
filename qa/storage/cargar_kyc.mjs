// =====================================================================
// MANI — Carga de los documentos KYC de prueba y URL firmada (CFG-13)
// =====================================================================
// Ticket: SCRUM-930 (CFG-13) · Subtarea: SCRUM-978
// Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
// Depende de: supabase/poc-cfg13/10_bucket_kyc.sql y 20_seed_storage.sql
//
// QUE HACE
//   Cada aliado de CFG-04 inicia sesion y sube SU cedula (PDF sintetico)
//   a `<tenant>/<su auth.uid>/cedula.pdf`, la misma ruta que
//   20_seed_storage.sql dejo en documento_kyc.ruta_storage. Despues emite
//   una URL firmada de 60 s y la descarga para comprobar el ciclo entero.
//
//   Los dos objetos son los fixtures del caso 6 de la suite de Newman
//   (qa/newman/mani-aislamiento.postman_collection.json). Correr esto una
//   vez antes de la suite; es idempotente (x-upsert).
//
//   La subida va con el JWT del aliado: la politica kyc_isolation se
//   ejercita en el INSERT. Que la subida funcione ya es un positivo.
//
// USO
//   set -a; source .env; set +a
//   node qa/storage/cargar_kyc.mjs
//
// No imprime tokens ni URLs firmadas: la URL es una credencial al portador.
// =====================================================================

import { login, subir, firmar, descargarFirmada, pdfSintetico } from './comun.mjs';

const ALIADOS = ['aliado.t1@qa.mani.test', 'aliado.t2@qa.mani.test'];

async function main() {
  let fallos = 0;
  for (const email of ALIADOS) {
    const u = await login(email);
    const ruta = `${u.tenant}/${u.uid}/cedula.pdf`;
    const pdf = pdfSintetico(200 * 1024);

    const t0 = performance.now();
    const rs = await subir(u.token, ruta, pdf);
    const cargaMs = performance.now() - t0;

    const { r: rf, url } = await firmar(u.token, ruta, 60);
    const rd = url ? await descargarFirmada(url) : null;
    const bytes = rd?.ok ? (await rd.arrayBuffer()).byteLength : 0;

    const ok = rs.ok && rf.ok && rd?.ok && bytes === pdf.length;
    if (!ok) fallos++;
    console.log(`${ok ? 'OK   ' : 'FALLA'} ${email.padEnd(24)} ruta=${ruta}`);
    console.log(`      subir=${rs.status} (${cargaMs.toFixed(0)} ms)  firmar=${rf.status}  ` +
                `descargar=${rd?.status ?? '—'}  bytes=${bytes}/${pdf.length}`);
    if (!rs.ok) console.log(`      respuesta de subida: ${await rs.text()}`);
  }
  if (fallos) {
    console.error(`\n${fallos} aliado(s) no pudieron completar el ciclo. Revisa que 10_bucket_kyc.sql este aplicado.`);
    process.exit(1);
  }
  console.log('\nFixtures del caso 6 listos.');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
