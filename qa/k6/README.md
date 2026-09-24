# Harness de concurrencia — CFG-09 (SCRUM-926)

Dispara N aceptaciones simultaneas sobre la misma solicitud para responder:
**¿el UPDATE condicional de ADR-0021 deja exactamente 1 asignacion exitosa?**

El codigo SQL de la PoC vive aparte, en `supabase/poc-cfg09/` (ADR-0001:
scripts ejecutables en el repo de codigo). El informe va a MANI-docs.

## Requisitos

- k6 instalado (`brew install k6`). Version usada: **2.3.0**.
- Los dos scripts aplicados en QA, en orden:
  1. `supabase/poc-cfg09/10_seed_concurrencia.sql`
  2. `supabase/poc-cfg09/20_rpc_aceptar_solicitud.sql`
- Un `.env` en la raiz con `SUPABASE_URL` y `SUPABASE_ANON_KEY` del proyecto
  QA. Esta gitignoreado; ver `.env.example`.

## Correr

```bash
set -a; source .env; set +a

# Caso principal — MODO=exclusion por defecto
k6 run qa/k6/aceptar_concurrente.js

# Control negativo — DEBE producir dobles asignaciones
k6 run -e MODO=sin_exclusion qa/k6/aceptar_concurrente.js

# Curva de carga
k6 run -e N=10 qa/k6/aceptar_concurrente.js
```

Entre corridas hay que devolver la solicitud a `PENDIENTE` con
`supabase/poc-cfg09/11_reset_solicitud.sql`. El bloque 1 de ese archivo
captura el ganador saliente antes de borrarlo.

## Leer el resultado

k6 reporta lo que el **cliente recibio**. La metrica del ticket se decide
con `supabase/poc-cfg09/30_verificar_corrida.sql`, que lee lo que la base
**hizo**. Si discrepan, manda la base.

| | Caso principal | Control negativo |
|---|---|---|
| `exito_200` | 1 | >1 |
| `conflicto_409` | N-1 | <N-1 |
| `asignaciones` en bitacora | 1 | >1 |

**El control negativo tiene que fallar.** Si tambien da 1 asignacion, el
harness no genero peticiones solapadas: no se probo exclusion, se probo que
no hubo carrera. En ese caso el verde del caso principal no vale y hay que
ensanchar la ventana (`-e ESPERA=0.2`) antes de concluir nada.

## Evidencia

Guardar en `qa/k6/evidencia/` la salida de k6 y la de los cuatro bloques de
`30_verificar_corrida.sql`, una carpeta por corrida.
