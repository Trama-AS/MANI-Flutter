# Evidencia de corridas — CFG-09 (SCRUM-962)

- **Fecha:** 2026-09-21
- **Ambiente:** Supabase QA `hpsxdotaizzclkeufzct` · PostgreSQL 17.6 · `READ COMMITTED`
- **Herramienta:** k6 v2.3.0 (commit/devel, go1.27.1, darwin/arm64)
- **Poblacion:** tenant `poc-concurrencia`, 50 aliados aprobados, solicitud
  `a0000000-0000-4000-8000-900000000001`
- **Bitacora cruda:** `bitacora.json` (fuente de verdad, leida via PostgREST con JWT de aliado)

## Resultados

| corrida | RPC | ventana | asignaciones | txid distintos | ventana observada | 200 | 409 | otros |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1-sin-exclusion | `aceptar_solicitud_sin_exclusion` | 50 ms | 1 | 1 | 0 ms | 1 | 49 | 0 |
| r2-sin-exclusion-3s | `aceptar_solicitud_sin_exclusion` | 3 s | **10** | **10** | **136 ms** | 10 | 40 | 0 |
| r3-control-malo | `aceptar_solicitud_control_malo` | 3 s | 1 | 1 | 0 ms | 1 | 49 | 0 |
| r4-exclusion | `aceptar_solicitud` | 3 s | **1** | 1 | 0 ms | **1** | **49** | **0** |
| r5-idempotencia | `aceptar_solicitud` | — | 0 filas nuevas | — | — | 1 | 1 | 0 |

`http_req_duration` — r2: avg 3.09 s, max 3.26 s · r3: avg 9.02 s, max 15.24 s ·
r4: avg 9.04 s, max 15.27 s.

## Como leer estas cinco filas

**r4 es la respuesta a la pregunta de la PoC.** 1 asignacion, 49 conflictos, 0 respuestas
inesperadas, 50/50 checks. Los tres umbrales de k6 en verde.

**r2 es lo que hace que r4 signifique algo.** Corrio con la misma alineacion de 3 segundos
y el mismo N: la unica diferencia es el mecanismo. Diez transacciones distintas asignaron
la misma solicitud en una ventana de 136 ms. Eso descarta que el 1 de r4 venga de falta de
carrera en vez de exclusion.

**r1 es el falso verde en estado puro.** Mismo codigo sin exclusion que r2, pero con
ventana de 50 ms: da 1 asignacion. Las peticiones llegan repartidas en ~900 ms, mas de
quince veces la ventana, asi que nunca se solapan. El harness reporto "1 exito" sin que
hubiera existido ninguna carrera.

**r3 confirma el hallazgo H-01.** El control negativo que proponia la primera version del
informe —quitarle al `UPDATE` solo el predicado `estado = 'pending'`— da 1 asignacion bajo
exactamente la carga donde r2 dio 10. La guarda `aliado_id IS NULL` excluye sola: en
`READ COMMITTED` la segunda transaccion re-evalua el `WHERE` contra la version ya
comprometida (EvalPlanQual) y afecta 0 filas. Un control negativo que no puede fallar no
valida nada.

**r5 cubre los tres caminos de error de `DD-MANI.md` §7.1** contra HTTP real, no simulado:
reintento del ganador `200 OK` con su mismo `aliado_id`; otro aliado `409 PT409
ya_no_disponible`; solicitud inexistente `404 PT404 no_encontrada`. Cero filas nuevas en la
bitacora: el reintento idempotente no se contabiliza como asignacion, que es lo que evita
inflar el conteo de dobles con reintentos legitimos (RNF-03).

## Dos lecturas de los tiempos

**El 10 de r2 no es arbitrario.** De 50 peticiones enviadas, solo 10 llegan a solaparse.
Coincide con el tamano tipico del pool de PostgREST: la concurrencia efectiva la acota el
pool, no N. Enviar N=200 no produciria 200 transacciones solapadas, produciria mas cola.

**El salto de 3 s a 15 s es la firma del mecanismo.** En r2 las transacciones no se
estorban: leen, esperan y escriben encima unas de otras, y terminan en ~3 s. En r3 y r4
hacen cola sobre el bloqueo de la fila, y el `max` sube a 15.2 s. Ese tiempo es el
mecanismo de exclusion funcionando, no un problema de rendimiento — con la salvedad de que
los 3 s de alineacion son artificiales y no representan latencia de produccion.

## Reproducir

```bash
set -a; source .env; set +a
bash qa/k6/obtener_tokens.sh 50          # una vez por hora (vigencia del JWT)
bash qa/k6/reset.sh                      # entre corridas
k6 run -e MODO=sin_exclusion -e ESPERA=3 -e CORRIDA=<etiqueta> qa/k6/aceptar_concurrente.js
k6 run -e MODO=control_malo  -e ESPERA=3 -e CORRIDA=<etiqueta> qa/k6/aceptar_concurrente.js
k6 run -e MODO=exclusion     -e ESPERA=3 -e CORRIDA=<etiqueta> qa/k6/aceptar_concurrente.js
```

Verificacion en base: `supabase/poc-cfg09/30_verificar_corrida.sql`.
