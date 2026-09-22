-- =====================================================================
-- MANI — Reset de la solicitud en disputa entre corridas del harness
-- =====================================================================
-- Ticket: SCRUM-926 (CFG-09) · Subtarea: SCRUM-962
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Requiere: supabase/poc-cfg09/10_seed_concurrencia.sql ya aplicado
--
-- ⚠️ ESCRIBE, pero solo sobre 1 fila del tenant `poc-concurrencia`.
--
-- POR QUE EXISTE
--   Cada corrida de k6 deja la solicitud en 'assigned'. Volver a correr el
--   seed completo re-crearia los N usuarios de Auth (bcrypt x N) sin
--   necesidad: entre corridas solo hay que devolver ESTA fila a 'pending'.
--
-- ORDEN DE USO POR CORRIDA
--   1. Bloque 1 de este archivo  -> captura el resultado de la corrida
--      anterior ANTES de borrarlo (evidencia de SCRUM-962).
--   2. Bloque 2                  -> devuelve la fila a 'pending'.
--   3. k6                        -> siguiente corrida.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BLOQUE 1 — Estado saliente (SOLO LECTURA; correr ANTES del reset)
-- ---------------------------------------------------------------------
-- Guardar esta salida junto al summary.json de la corrida. `ganador` es
-- el aliado que se quedo con la solicitud; `estado` deberia ser
-- 'assigned' si la corrida tuvo al menos un exito.
SELECT s.id            AS solicitud,
       s.estado,
       s.aliado_id     AS ganador,
       a.nombre_razon_social AS ganador_nombre,
       s.updated_at    AS asignada_en
  FROM solicitud s
  LEFT JOIN aliado a ON a.id = s.aliado_id
 WHERE s.id = 'a0000000-0000-4000-8000-900000000001';

-- ---------------------------------------------------------------------
-- BLOQUE 2 — Reset
-- ---------------------------------------------------------------------
-- `estado` explicito por la deriva D1: QA no tiene DEFAULT en la columna.
-- El RETURNING confirma que quedo exactamente 1 fila lista para la
-- siguiente carrera; si devuelve 0 filas, el seed no esta aplicado.
UPDATE solicitud
   SET aliado_id  = NULL,
       estado     = 'pending',
       updated_at = now()
 WHERE id = 'a0000000-0000-4000-8000-900000000001'
RETURNING id, estado, aliado_id, updated_at;
