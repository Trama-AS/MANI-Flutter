-- =====================================================================
-- MANI — UPDATE condicional de exclusion concurrente (ADR-0021)
-- =====================================================================
-- Ticket: SCRUM-926 (CFG-09) · Subtarea: SCRUM-960
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Requiere: supabase/poc-cfg09/10_seed_concurrencia.sql ya aplicado
--
-- ⚠️ ESCRIBE ESQUEMA: crea 1 tabla y 2 funciones. No toca datos existentes.
-- ⚠️ RE-EJECUTARLO BORRA LA BITACORA (`DROP TABLE`). Es un script de
--    preparacion, no de uso entre corridas: si ya hay evidencia de
--    SCRUM-962 sin exportar, expórtala antes de volver a correrlo.
--
-- QUE CREA
--   1. `poc_asignacion_log` — bitacora APPEND-ONLY de asignaciones exitosas.
--   2. `aceptar_solicitud(...)` — el mecanismo de ADR-0021. Lo que se mide.
--   3. `aceptar_solicitud_sin_exclusion(...)` — el CONTROL NEGATIVO.
--
-- POR QUE HACE FALTA LA BITACORA
--   La metrica del ticket es "exactamente 1 exito, 0 dobles asignaciones",
--   pero hay UNA sola fila de solicitud. Si dos aliados ganan, el segundo
--   pisa al primero y la fila queda con 1 aliado_id — indistinguible del
--   caso correcto. Consultar `solicitud` al final NO puede detectar el
--   fallo. La bitacora si: dos filas para la misma solicitud y corrida es
--   una doble asignacion probada del lado de la base, sin depender de lo
--   que reporte k6.
--
--   Esto corrige lo que afirmaba el informe de SCRUM-959 ("las dobles
--   asignaciones se cuentan en tabla") — era cierto el principio, pero no
--   existia la tabla que lo hiciera posible.
--
-- POR QUE EL CONTROL NEGATIVO ES OTRO DISENO
--   La primera version proponia quitar solo el predicado `estado =
--   'pending'`. No sirve: el `UPDATE` lleva DOS guardas y la otra
--   —`aliado_id IS NULL`— sigue excluyendo sola. El primer UPDATE deja
--   ese campo no nulo y bajo READ COMMITTED las transacciones siguientes
--   reevaluan el WHERE y afectan 0 filas. Daria 1 exito con o sin
--   concurrencia real, que es justo lo que el control debia descartar.
--   (Hallazgo de la revision del PR #4 de MANI-docs.)
--
--   La version correcta separa la comprobacion de la escritura —lee que
--   este 'pending', espera, y despues actualiza SIN condicion— creando la
--   ventana check-then-act. Bajo concurrencia real produce N filas en la
--   bitacora; si el pooler serializa, produce 1. Eso es lo que distingue
--   "hay exclusion" de "no hubo carrera".
--
-- SECURITY INVOKER a proposito: RLS debe aplicar igual que en produccion.
-- Con SECURITY DEFINER la funcion bypasaria el aislamiento por tenant y la
-- PoC mediria un escenario que no existe.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Bitacora append-only
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS public.poc_asignacion_log;

CREATE TABLE public.poc_asignacion_log (
    id             bigserial PRIMARY KEY,
    tenant_id      uuid        NOT NULL,
    solicitud_id   uuid        NOT NULL,
    aliado_id      uuid        NOT NULL,
    -- Etiqueta libre que manda el harness para separar corridas sin tener
    -- que truncar la tabla entre una y otra.
    corrida        text        NULL,
    -- clock_timestamp() y NO now(): now() devuelve el instante de INICIO de
    -- la transaccion y seria identico para todas las que arrancaron juntas.
    -- Para leer el entrelazado hace falta la hora real del INSERT.
    asignada_en    timestamptz NOT NULL DEFAULT clock_timestamp(),
    -- Identifica la transaccion: dos filas con txid distinto y la misma
    -- solicitud son dos transacciones que ganaron.
    txid           bigint      NOT NULL DEFAULT txid_current(),
    -- Solo lo llena el control negativo: el valor que fue pisado.
    aliado_previo  uuid        NULL
);

CREATE INDEX idx_poc_log_solicitud ON public.poc_asignacion_log (solicitud_id, corrida);

-- Append-only de verdad: sin UPDATE ni DELETE para los roles de la API.
-- Supabase concede ALL por defecto a anon/authenticated en tablas nuevas;
-- hay que revocarlo explicitamente o la bitacora seria falsificable por el
-- mismo cliente cuyo comportamiento estamos midiendo.
REVOKE ALL ON public.poc_asignacion_log FROM anon, authenticated;
GRANT SELECT, INSERT ON public.poc_asignacion_log TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.poc_asignacion_log_id_seq TO authenticated;

ALTER TABLE public.poc_asignacion_log ENABLE ROW LEVEL SECURITY;

-- WITH CHECK explicito: el INSERT lo hace la funcion como el usuario
-- invocador, asi que la fila nueva tiene que pasar la politica.
CREATE POLICY tenant_isolation_poc_log ON public.poc_asignacion_log
  FOR ALL TO public
  USING      (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid)
  WITH CHECK (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid);

-- ---------------------------------------------------------------------
-- 2. El mecanismo de ADR-0021 — lo que la PoC mide
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.aceptar_solicitud(uuid, uuid, text);

CREATE FUNCTION public.aceptar_solicitud(
    p_solicitud uuid,
    p_aliado    uuid,
    p_corrida   text DEFAULT NULL)
RETURNS TABLE (id uuid, estado text, aliado_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
  v_actual uuid;
BEGIN
  -- EL UPDATE CONDICIONAL. Las dos guardas son el mecanismo completo de
  -- exclusion: la fila solo se deja tomar si sigue libre. Postgres bloquea
  -- la fila mientras una transaccion la actualiza; las demas esperan, y al
  -- desbloquearse reevaluan el WHERE contra la version ya comprometida, que
  -- ya no cumple. De ahi que afecten 0 filas sin bloqueo pesimista.
  UPDATE solicitud s
     SET aliado_id  = p_aliado,
         estado     = 'assigned',
         updated_at = now()
   WHERE s.id = p_solicitud
     AND s.estado = 'pending'
     AND s.aliado_id IS NULL
  RETURNING s.tenant_id INTO v_tenant;

  IF FOUND THEN
    INSERT INTO poc_asignacion_log (tenant_id, solicitud_id, aliado_id, corrida)
    VALUES (v_tenant, p_solicitud, p_aliado, p_corrida);

    RETURN QUERY
      SELECT s.id, s.estado, s.aliado_id FROM solicitud s WHERE s.id = p_solicitud;
    RETURN;
  END IF;

  -- 0 filas afectadas. Tres motivos posibles, y hay que distinguirlos.
  SELECT s.aliado_id INTO v_actual FROM solicitud s WHERE s.id = p_solicitud;

  IF NOT FOUND THEN
    -- No existe, o es de otro tenant y RLS la oculta. DD-MANI.md 7.1 exige
    -- no distinguir los dos casos: distinguirlos filtraria la existencia de
    -- filas ajenas entre tenants.
    RAISE EXCEPTION 'no_encontrada' USING ERRCODE = 'PT404';
  END IF;

  IF v_actual = p_aliado THEN
    -- Reintento del mismo aliado tras un exito previo (timeout de red).
    -- DD-MANI.md 7.1 y RNF-03: responde exito, no error. NO se registra en
    -- la bitacora: no hubo asignacion nueva, y contarla inflaria el conteo
    -- de dobles asignaciones con reintentos legitimos.
    RETURN QUERY
      SELECT s.id, s.estado, s.aliado_id FROM solicitud s WHERE s.id = p_solicitud;
    RETURN;
  END IF;

  -- Otro aliado la tomo primero.
  RAISE EXCEPTION 'ya_no_disponible' USING ERRCODE = 'PT409';
END;
$fn$;

REVOKE ALL ON FUNCTION public.aceptar_solicitud(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aceptar_solicitud(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Control negativo — DEBE fallar
-- ---------------------------------------------------------------------
-- No es una alternativa de diseno: es el instrumento que valida el
-- instrumento. Si esta funcion tambien produce 1 sola asignacion, entonces
-- el harness no esta generando concurrencia real y el verde de la funcion
-- de arriba no prueba nada.
DROP FUNCTION IF EXISTS public.aceptar_solicitud_sin_exclusion(uuid, uuid, text, numeric);

CREATE FUNCTION public.aceptar_solicitud_sin_exclusion(
    p_solicitud uuid,
    p_aliado    uuid,
    p_corrida   text    DEFAULT NULL,
    p_espera    numeric DEFAULT 0.05)
RETURNS TABLE (id uuid, estado text, aliado_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
  v_tenant  uuid;
  v_estado  text;
  v_previo  uuid;
BEGIN
  -- PASO 1 — COMPROBAR (check). Lectura sin bloqueo: varias transacciones
  -- pueden pasar por aqui a la vez y todas ver 'pending'.
  SELECT s.tenant_id, s.estado, s.aliado_id
    INTO v_tenant, v_estado, v_previo
    FROM solicitud s WHERE s.id = p_solicitud;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_encontrada' USING ERRCODE = 'PT404';
  END IF;

  IF v_estado <> 'pending' THEN
    RAISE EXCEPTION 'ya_no_disponible' USING ERRCODE = 'PT409';
  END IF;

  -- PASO 2 — La ventana. Ensancha el intervalo entre comprobar y escribir
  -- para que el entrelazado sea observable aunque el pooler escalone las
  -- peticiones. Sin esto el control negativo puede dar un falso verde por
  -- la razon opuesta: ventana demasiado corta para solaparse.
  PERFORM pg_sleep(p_espera);

  -- PASO 3 — ESCRIBIR (act). SIN condicion: la decision se tomo en el paso
  -- 1 sobre un estado que ya puede estar obsoleto. Esto es exactamente el
  -- lost update que ADR-0021 evita.
  UPDATE solicitud s
     SET aliado_id  = p_aliado,
         estado     = 'assigned',
         updated_at = now()
   WHERE s.id = p_solicitud;

  INSERT INTO poc_asignacion_log (tenant_id, solicitud_id, aliado_id, corrida, aliado_previo)
  VALUES (v_tenant, p_solicitud, p_aliado, p_corrida, v_previo);

  RETURN QUERY
    SELECT s.id, s.estado, s.aliado_id FROM solicitud s WHERE s.id = p_solicitud;
END;
$fn$;

REVOKE ALL ON FUNCTION public.aceptar_solicitud_sin_exclusion(uuid, uuid, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aceptar_solicitud_sin_exclusion(uuid, uuid, text, numeric) TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Control negativo MAL DISENADO — se conserva a proposito
-- ---------------------------------------------------------------------
-- Esta funcion NO es un error que quedo suelto: es la demostracion de por
-- que el primer diseno del control negativo no servia.
--
-- La primera version del informe de SCRUM-959 proponia "quitar el predicado
-- estado = 'pending'". Eso es esto. Y no funciona, porque el UPDATE lleva
-- DOS guardas: al quitar una, la otra sigue excluyendo sola.
--
-- El motivo es EvalPlanQual. En READ COMMITTED, cuando dos transacciones
-- van contra la misma fila, la segunda espera a que la primera termine y
-- entonces NO reusa la version que leyo al planificar: re-evalua el WHERE
-- contra la version ya comprometida. La primera dejo `aliado_id` no nulo,
-- asi que la segunda ya no cumple y afecta 0 filas.
--
-- Resultado: 1 sola asignacion, con o sin concurrencia real. Un control
-- negativo que no puede fallar no controla nada.
--
-- Se despliega para medirlo y dejar el dato en el informe: es la evidencia
-- de que el instrumento de validacion tambien hay que validarlo.
DROP FUNCTION IF EXISTS public.aceptar_solicitud_control_malo(uuid, uuid, text);

CREATE FUNCTION public.aceptar_solicitud_control_malo(
    p_solicitud uuid,
    p_aliado    uuid,
    p_corrida   text DEFAULT NULL)
RETURNS TABLE (id uuid, estado text, aliado_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
BEGIN
  -- UNA sola guarda. El predicado de estado se quito; el de aliado_id no.
  UPDATE solicitud s
     SET aliado_id  = p_aliado,
         estado     = 'assigned',
         updated_at = now()
   WHERE s.id = p_solicitud
     AND s.aliado_id IS NULL
  RETURNING s.tenant_id INTO v_tenant;

  IF FOUND THEN
    INSERT INTO poc_asignacion_log (tenant_id, solicitud_id, aliado_id, corrida)
    VALUES (v_tenant, p_solicitud, p_aliado, p_corrida);
    RETURN QUERY
      SELECT s.id, s.estado, s.aliado_id FROM solicitud s WHERE s.id = p_solicitud;
    RETURN;
  END IF;

  RAISE EXCEPTION 'ya_no_disponible' USING ERRCODE = 'PT409';
END;
$fn$;

REVOKE ALL ON FUNCTION public.aceptar_solicitud_control_malo(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aceptar_solicitud_control_malo(uuid, uuid, text) TO authenticated;

COMMIT;

-- PostgREST cachea el esquema: sin esto las funciones existen en la base
-- pero /rest/v1/rpc/... responde 404 hasta el proximo reinicio.
NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- VERIFICACION (solo lectura)
-- =====================================================================
-- Esperado: 2 funciones, ambas SECURITY INVOKER, ambas con EXECUTE para
-- `authenticated` y sin EXECUTE para `anon`.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS seguridad,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_execute,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_execute
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname LIKE 'aceptar_solicitud%'
 ORDER BY p.proname;

-- La bitacora debe ser append-only para la API: INSERT y SELECT, nada mas.
SELECT grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
  FROM information_schema.role_table_grants
 WHERE table_schema = 'public' AND table_name = 'poc_asignacion_log'
   AND grantee IN ('anon', 'authenticated')
 GROUP BY grantee ORDER BY grantee;
