-- =====================================================================
-- MANI — Verificacion de terreno para la PoC de exclusion concurrente
-- =====================================================================
-- Ticket: SCRUM-926 (CFG-09) · Cierra SCRUM-959
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: supabase/seed/seed_qa_multitenant.sql (CFG-04, SCRUM-921)
-- Salida de la corrida del 2026-09-21: Entregas/PoC/SCRUM-959-verificacion-terreno.md
-- del repositorio Trama-AS/MANI-docs. Por ADR-0001 el script vive aqui (codigo)
-- y el informe alla (documentacion tecnica, ADR-0007).
--
-- TODO ESTE ARCHIVO ES DE SOLO LECTURA. No modifica datos ni esquema.
--
-- POR QUE EXISTE
--   Product/DDL_MANI.sql de MANI-docs esta desactualizado respecto de QA.
--   La PoC no puede partir de ese archivo: la fuente de verdad del esquema
--   es la base de QA. Estos bloques la interrogan directamente.
--
--   Ademas hay dos bloqueos que, si no se resuelven aqui, hacen que el
--   harness k6 falle sin decir nada util sobre concurrencia:
--     B1. Sin GRANT sobre `solicitud` a los roles de PostgREST, la API
--         responde 401/403 ANTES de que RLS actue (bloque 2).
--     B2. El seed de CFG-04 siembra 1 aliado por tenant y CERO solicitudes
--         (su Parte A las borra). N aceptaciones simultaneas necesitan N
--         aliados aprobados compitiendo (bloque 5).
--
-- COMO USARLO
--   SQL Editor del dashboard, bloque por bloque. Guardar cada salida:
--   el conjunto es la evidencia de cierre de SCRUM-959.
-- =====================================================================


-- ---------------------------------------------------------------------
-- BLOQUE 1 — Forma REAL de `solicitud` en QA
-- ---------------------------------------------------------------------
-- El UPDATE condicional de ADR-0021 asume tres cosas:
--   estado text con 'pending' permitido, aliado_id uuid NULLABLE,
--   updated_at presente.
-- Si alguna no se cumple, la RPC de SCRUM-960 se escribe distinto.

-- 1.a — Columnas
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'solicitud'
 ORDER BY ordinal_position;

-- 1.b — Restricciones CHECK (valores admitidos de `estado`)
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicion
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'solicitud'
 ORDER BY con.contype, con.conname;

-- 1.c — Indices. Si `estado`/`aliado_id` no estan indexados no importa
-- para la correccion, pero si para leer los tiempos de la corrida.
SELECT indexname, indexdef FROM pg_indexes
 WHERE schemaname = 'public' AND tablename = 'solicitud';

-- 1.d — Deriva contra el DDL documentado. Esperado: cero filas.
-- Cada fila que salga es una columna que el DDL de MANI-docs declara y QA
-- no tiene. Es el insumo para la deuda tecnica del informe, no un fallo.
SELECT c.columna AS columna_del_ddl_ausente_en_qa
  FROM (VALUES ('id'),('tenant_id'),('cliente_id'),('sitio_id'),
               ('categoria_id'),('zona_id'),('aliado_id'),('estado'),
               ('created_at'),('updated_at')) AS c(columna)
 WHERE NOT EXISTS (
   SELECT 1 FROM information_schema.columns ic
    WHERE ic.table_schema = 'public' AND ic.table_name = 'solicitud'
      AND ic.column_name = c.columna);


-- ---------------------------------------------------------------------
-- BLOQUE 2 — GRANTs a los roles de PostgREST  ← BLOQUEO B1
-- ---------------------------------------------------------------------
-- Esperado: `authenticated` con al menos SELECT y UPDATE sobre solicitud.
-- Si sale VACIO o sin UPDATE, k6 recibira "permission denied" y la PoC no
-- mide nada. Es hallazgo propio de CFG-09, no un fallo del seed de CFG-04.
SELECT grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
  FROM information_schema.role_table_grants
 WHERE table_schema = 'public' AND table_name = 'solicitud'
   AND grantee IN ('anon', 'authenticated')
 GROUP BY grantee ORDER BY grantee;

-- 2.b — USAGE sobre el esquema. Sin esto nada de lo anterior sirve.
SELECT nspname,
       has_schema_privilege('anon',          nspname, 'USAGE') AS anon_usage,
       has_schema_privilege('authenticated', nspname, 'USAGE') AS auth_usage
  FROM pg_namespace WHERE nspname = 'public';


-- ---------------------------------------------------------------------
-- BLOQUE 3 — RLS sobre `solicitud`: hay politica que permita UPDATE?
-- ---------------------------------------------------------------------
-- Mirar `cmd`, `with_check` y `roles`.
--   * Si cmd = ALL y with_check es NULL, Postgres reutiliza la expresion
--     USING como WITH CHECK: el UPDATE pasa mientras la fila resultante
--     siga cumpliendola. Como el UPDATE condicional no toca tenant_id, no
--     hay bloqueo. (Verificado en QA el 2026-09-21.)
--   * Si en cambio hubiera una politica FOR UPDATE con WITH CHECK propio,
--     hay que leerla antes de medir: un rechazo por RLS se veria igual que
--     un fallo de exclusion concurrente — falso rojo.
--   * `roles` dice a quien aplica. Si es {public} sin distincion de rol,
--     la tabla no restringe QUIEN acepta, solo de que tenant es la fila.
SELECT policyname, cmd, permissive, roles, qual AS using_expr, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'solicitud';

-- 3.b — RLS activo
SELECT c.relname AS tabla, c.relrowsecurity AS rls_activo, c.relforcerowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'solicitud';


-- ---------------------------------------------------------------------
-- BLOQUE 4 — La RPC de SCRUM-960 ya existe?
-- ---------------------------------------------------------------------
-- Esperado hoy: cero filas. Si devuelve algo, alguien ya la creo y hay que
-- leerla antes de escribir la de la PoC.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       CASE WHEN p.prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END AS seguridad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname ILIKE '%acepta%';


-- ---------------------------------------------------------------------
-- BLOQUE 5 — Poblacion disponible para competir  ← BLOQUEO B2
-- ---------------------------------------------------------------------
-- Esperado segun el seed de CFG-04: aliados_aprobados = 1 por tenant,
-- solicitudes = 0. Eso CONFIRMA que hace falta el seed de la Fase 0.
-- N de la PoC nunca puede superar aliados_aprobados del tenant elegido.
SELECT t.slug,
       (SELECT count(*) FROM aliado a
         WHERE a.tenant_id = t.id AND a.estado_verificacion = 'aprobado') AS aliados_aprobados,
       (SELECT count(*) FROM solicitud s WHERE s.tenant_id = t.id)         AS solicitudes,
       (SELECT count(*) FROM solicitud s
         WHERE s.tenant_id = t.id AND s.estado = 'pending')                AS solicitudes_pending
  FROM tenant t ORDER BY t.slug;

-- 5.b — pgcrypto: el seed de la Fase 0 crea N usuarios de Auth con
-- crypt()/gen_salt(). Sin la extension, no se puede sembrar.
SELECT extname, extversion FROM pg_extension WHERE extname = 'pgcrypto';


-- ---------------------------------------------------------------------
-- BLOQUE 6 — Contexto del motor (para leer la corrida despues)
-- ---------------------------------------------------------------------
-- El riesgo principal de la PoC es un FALSO VERDE: si el pooler serializa
-- las N peticiones, sale "1 exito" sin que haya habido concurrencia real.
-- Estos numeros son el punto de partida para dimensionar N y para el
-- control negativo de la Fase 3.
SELECT version() AS motor;
SELECT name, setting FROM pg_settings
 WHERE name IN ('max_connections', 'default_transaction_isolation');


-- ---------------------------------------------------------------------
-- RESUMEN A ADJUNTAR EN SCRUM-959
-- ---------------------------------------------------------------------
--   Bloque 1   : esquema real de `solicitud` + deriva vs. DDL documentado
--   Bloque 2   : authenticated con SELECT+UPDATE  -> si no, arreglar aqui
--   Bloque 3   : politica con cmd y with_check    -> si UPDATE queda sin
--                WITH CHECK, hay que corregir la politica antes de medir
--   Bloque 4   : cero funciones de aceptacion previas
--   Bloque 5   : 1 aliado aprobado / 0 solicitudes -> justifica la Fase 0
--   Bloque 6   : motor y limites de conexion
