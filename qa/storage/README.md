# Storage KYC y URLs firmadas — CFG-13

Ticket: **SCRUM-930 (CFG-13)** · Ambiente: **solo QA** (`hpsxdotaizzclkeufzct`)

Valida ADR-0013: bucket privado `kyc-documentos`, rutas `tenant_id/<uid>/archivo.ext` y la
política `kyc_isolation` sobre `storage.objects`. El informe va a `Trama-AS/MANI-docs`,
`Entregas/PoC/PoC-003-almacenamiento-kyc-urls-firmadas.md`.

## Orden de ejecución

| # | Qué | Dónde |
| --- | --- | --- |
| 1 | Terreno (solo lectura) | `supabase/poc-cfg13/00_verificar_terreno.sql`, SQL Editor |
| 2 | Bucket y política (SCRUM-977) | `supabase/poc-cfg13/10_bucket_kyc.sql`, SQL Editor |
| 3 | Rutas de `documento_kyc` alineadas con ADR-0013 | `supabase/poc-cfg13/20_seed_storage.sql`, SQL Editor |
| 4 | Fixtures: cada aliado sube su cédula (SCRUM-978) | `node qa/storage/cargar_kyc.mjs` |
| 5 | Tiempo de carga (SCRUM-979) | `node qa/storage/bench_carga.mjs` |
| 6 | Acceso cruzado (SCRUM-980) | carpeta `06 caso 6` de `qa/newman/mani-aislamiento.postman_collection.json` |
| 7 | Control negativo | bloque comentado al final de `10_bucket_kyc.sql`, suite otra vez, restaurar con el paso 2 |

```bash
set -a; source .env; set +a
node qa/storage/cargar_kyc.mjs
node qa/storage/bench_carga.mjs 30
```

Sin dependencias: `fetch` nativo de Node (≥ 18), contra las mismas rutas REST de Storage que
usa la suite de Newman y que `supabase_flutter` llama por debajo. Nunca se usa
`service_role`, porque salta RLS y no se mediría nada.

## Umbral (publicado en SCRUM-930 antes de ejecutar)

| Métrica | Umbral |
| --- | --- |
| Carga de 1 MB, 30 corridas | **p95 < 2 s** |
| `createSignedUrl` | p95 < 500 ms |
| 100 KB, 5 MB y descarga firmada | solo se reportan |

Se mide desde la máquina que corre el script. El informe tiene que decir desde dónde.

## Tres cosas que hay que saber antes de leer los resultados

**Una URL firmada es un token al portador.** La descarga por `/object/sign/...?token=` no
lleva JWT de usuario ni pasa por RLS. `kyc_isolation` decide quién puede **emitir** la URL;
una vez emitida, cualquiera que la tenga la descarga hasta que expire. Es el diseño de
Supabase, no un defecto de la política. La suite lo registra como control positivo
esperado (C1). Las mitigaciones (TTL corto, emitir bajo demanda, no persistir la URL) las
decide el Backend Lead.

**El segundo segmento de la ruta es `auth.uid()`, no `aliado.id`.** Es lo que compara la
política. ADR-0013 lo llama `aliado_id`, pero `aliado.id` es otro valor (`50000000-…`
frente a `30000000-…` en QA). El caso N11 demuestra que con `aliado.id` el propio dueño
queda bloqueado.

**Quitar la política no sirve de control negativo.** Con RLS y sin políticas, Storage lo
niega todo: los negativos siguen en verde y caen los positivos. El control es reemplazarla
por una política que solo mire el bucket.

## Evidencia

`evidencia/bench-carga-<timestamp>.json`: estadísticas, umbrales y veredicto. No contiene
tokens ni URLs firmadas, así que se versiona tal cual. La evidencia de Newman se redacta con
`qa/newman/redactar_evidencia.mjs`: el token de las URLs firmadas es un JWT y lo atrapa la
misma regla.
