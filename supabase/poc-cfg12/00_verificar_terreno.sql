-- =====================================================================
-- MANI — Verificacion de terreno para la PoC de identidad y claims
-- =====================================================================
-- Ticket: SCRUM-929 (CFG-12) · Precede a SCRUM-971
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: supabase/seed/seed_qa_multitenant.sql (CFG-04, SCRUM-921)
-- Salida de la corrida: Entregas/PoC/SCRUM-971-verificacion-terreno.md del
-- repositorio Trama-AS/MANI-docs. Por ADR-0001 el script vive aqui (codigo)
-- y el informe alla (documentacion tecnica, ADR-0007).
--
-- TODO ESTE ARCHIVO ES DE SOLO LECTURA. No modifica datos ni esquema.
--
-- POR QUE EXISTE
--   CFG-12 mide si el JWT de Supabase Auth propaga tenant_id y user_role
--   en el 100% de los casos (ADR-0018, RNF-01). Hoy esa propagacion NO
--   tiene mecanismo: el tenant_id llega al token solo porque el seed de
--   CFG-04 lo escribe a mano en auth.users.raw_app_meta_data. Un usuario
--   dado de alta por el flujo real saldria sin tenant.
--
--   La PoC construye el mecanismo (Custom Access Token Hook) y lo mide
--   contra usuarios cuyo raw_app_meta_data esta vacio a proposito. Antes
--   de escribir ese hook hay cuatro cosas que decidir con datos, no con
--   suposiciones:
--
--     D1. De donde lee el hook el tenant y el rol. Se asume public.usuario
--         con columnas tenant_id y rol (bloque 1). El nombre de la columna
--         de rol importa: ADR-0018 y la politica kyc_isolation leen
--         `user_role` en el JWT, el DDL llama `rol` a la columna.
--     D2. Si el modelo admite que un usuario pertenezca a mas de un tenant.
--         Si no, el caso borde "multiples roles" (SCRUM-973) no es medible
--         y se declara como limitacion del modelo, no como fallo (bloque 1).
--     D3. Que rol ejecuta el hook y si alcanza a leer la tabla. GoTrue lo
--         invoca como supabase_auth_admin; sin GRANT ni politica RLS para
--         ese rol la funcion queda ciega y emite claims vacios (bloque 4).
--     D4. Si el caso 6 de ADR-0015 (aislamiento de KYC en Storage) es
--         ejecutable en QA (bloque 6).
--
--   Y una verificacion que no es de la PoC sino del ambiente: que las 15
--   politicas RLS sigan aplicadas (bloque 3). SCRUM-1039 encontro QA con
--   RLS habilitado y CERO politicas. Si eso se repite, toda la suite de
--   acceso cruzado de la Fase 5 daria verde en falso, porque nadie accede
--   a nada y los 6 casos negativos pasan por la razon equivocada.
--
-- COMO USARLO
--   SQL Editor del dashboard, bloque por bloque. Guardar cada salida:
--   el conjunto es la evidencia de cierre de la verificacion de terreno.
--   Corre como `postgres`, que bypassa RLS — correcto para introspeccion.
-- =====================================================================


-- ---------------------------------------------------------------------
-- BLOQUE 1 — Forma REAL de `public.usuario`, la fuente del hook
-- ---------------------------------------------------------------------
-- Resuelve D1 y D2.

-- 1.a — Columnas. Se esperan `tenant_id uuid` y `rol text`.
--   Si `tenant_id` sale NULLABLE, el caso borde "usuario sin tenant"
--   (SCRUM-973) se puede sembrar sin trucos: es un estado que el modelo
--   ya admite, no una anomalia fabricada para la prueba.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'usuario'
 ORDER BY ordinal_position;

-- 1.b — Restricciones. Interesa si `rol` tiene CHECK con el vocabulario
--   de roles. SCRUM-959 documento la deriva D2 de CFG-09: `solicitud.estado`
--   no tiene CHECK en QA aunque el DDL lo declara. Si `rol` esta igual,
--   el hook puede emitir cualquier cadena como user_role y nada lo impide.
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicion
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'usuario'
 ORDER BY con.contype, con.conname;

-- 1.c — ¿Existe alguna tabla de membresia usuario-tenant?
--   Si devuelve 0 filas, un usuario pertenece exactamente a un tenant y
--   el caso borde "multiples roles" de SCRUM-973 NO es medible contra
--   este modelo. Eso no invalida la PoC: se declara como limitacion, y
--   se cruza con la consecuencia negativa que ADR-0018 ya admite
--   ("el cambio de contexto de tenant requiere reexpedir el token").
SELECT c.relname AS tabla,
       string_agg(a.attname, ', ' ORDER BY a.attnum) AS columnas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relname <> 'usuario'
   AND EXISTS (SELECT 1 FROM pg_attribute x
                WHERE x.attrelid = c.oid AND x.attname = 'tenant_id')
   AND EXISTS (SELECT 1 FROM pg_attribute y
                WHERE y.attrelid = c.oid AND y.attname IN ('usuario_id', 'user_id'))
 GROUP BY c.relname
 ORDER BY c.relname;

-- 1.d — ¿Cuantos tenants distintos tiene hoy cada usuario?
--   Complemento empirico de 1.c. Todo > 1 seria un multi-tenant real.
SELECT u.email, count(DISTINCT u.tenant_id) AS tenants, count(*) AS filas
  FROM public.usuario u
 GROUP BY u.email
HAVING count(*) > 1 OR count(DISTINCT u.tenant_id) > 1
 ORDER BY u.email;


-- ---------------------------------------------------------------------
-- BLOQUE 2 — ¿Ya existe un Custom Access Token Hook?
-- ---------------------------------------------------------------------
-- Si devuelve filas, alguien ya monto un mecanismo de claims y la Fase 1
-- lo extiende en vez de escribirlo desde cero. Esperado: 0 filas.
SELECT n.nspname AS esquema,
       p.proname  AS funcion,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       p.prosecdef AS security_definer,
       p.provolatile AS volatilidad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname ILIKE '%access_token%'
    OR p.proname ILIKE '%custom_claims%'
    OR p.proname ILIKE '%hook%'
 ORDER BY n.nspname, p.proname;


-- ---------------------------------------------------------------------
-- BLOQUE 3 — Politicas RLS: ¿siguen aplicadas? ¿estan versionadas?
-- ---------------------------------------------------------------------
-- Este bloque no valida la PoC, valida que el ambiente sirva para medirla.

-- 3.a — RLS habilitado y conteo de politicas por tabla.
--   Una tabla con relrowsecurity = true y politicas = 0 niega todo a
--   cualquier rol que no sea el dueño. Ese fue el estado que encontro
--   SCRUM-1039 y el que haria pasar en falso la suite de la Fase 5.
SELECT c.relname AS tabla,
       c.relrowsecurity  AS rls_habilitado,
       c.relforcerowsecurity AS rls_forzado,
       count(pol.polname) AS politicas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_policy pol ON pol.polrelid = c.oid
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 GROUP BY c.relname, c.relrowsecurity, c.relforcerowsecurity
 ORDER BY (c.relrowsecurity AND count(pol.polname) = 0) DESC, c.relname;

-- 3.b — Definicion de cada politica. Interesan dos cosas:
--   * que `qual` use el predicado de ADR-0018 sobre app_metadata->>'tenant_id'
--     y no una cabecera ni una variable de sesion editable por el cliente;
--   * si `with_check` viene NULL. SCRUM-1039 dejo ese punto abierto: con
--     solo USING, Postgres reutiliza esa expresion para INSERT y UPDATE.
--     Funciona, pero el caso 3b de la Fase 5 lo comprueba en vez de asumirlo.
SELECT tablename, policyname, cmd, roles,
       qual       AS using_expr,
       with_check AS with_check_expr
  FROM pg_policies
 WHERE schemaname = 'public'
 ORDER BY tablename, policyname;

-- 3.c — Deriva entre la base y la cadena de migraciones versionada.
--   database/migrations/001_initial_schema.sql NO contiene ningun
--   CREATE POLICY ni ENABLE ROW LEVEL SECURITY. Las politicas que este
--   bloque encuentre existen SOLO en la base de QA, aplicadas a mano al
--   cerrar SCRUM-1039, que dejo pendiente justamente "versionar
--   aplicar_rls_qa.sql". Reconstruir DEV o PROD desde la cadena daria un
--   esquema sin RLS. El conteo de abajo es la evidencia de esa brecha.
SELECT count(*) AS politicas_en_qa_sin_versionar
  FROM pg_policies
 WHERE schemaname = 'public';

-- 3.d — ¿Que migraciones cree QA que tiene aplicadas?
--   Se contrasta contra database/migrations/ del repositorio.
SELECT version, description, applied_at
  FROM public.schema_migrations
 ORDER BY version;


-- ---------------------------------------------------------------------
-- BLOQUE 4 — ¿Puede el hook leer `usuario`?
-- ---------------------------------------------------------------------
-- Resuelve D3. GoTrue invoca el hook como `supabase_auth_admin`, un rol
-- distinto de `authenticated` y de `postgres`. Le hacen falta dos cosas:
-- USAGE sobre el esquema, SELECT sobre la tabla — y, si `usuario` tiene
-- RLS, una politica que lo deje leer. Sin eso el hook no falla: devuelve
-- claims vacios, que es peor, porque el token sale valido y sin tenant.

-- 4.a — El rol existe.
SELECT rolname, rolsuper, rolbypassrls
  FROM pg_roles
 WHERE rolname IN ('supabase_auth_admin', 'authenticated', 'anon', 'service_role')
 ORDER BY rolname;

-- 4.b — Privilegios efectivos sobre lo que el hook necesita tocar.
SELECT 'usage_schema_public' AS privilegio,
       has_schema_privilege('supabase_auth_admin', 'public', 'USAGE') AS concedido
UNION ALL
SELECT 'select_usuario',
       has_table_privilege('supabase_auth_admin', 'public.usuario', 'SELECT')
UNION ALL
SELECT 'select_tenant',
       has_table_privilege('supabase_auth_admin', 'public.tenant', 'SELECT');

-- 4.c — Si `usuario` tiene RLS, ¿alguna politica alcanza a ese rol?
--   `roles = {public}` cubre a todos; un listado explicito sin
--   supabase_auth_admin lo deja fuera aunque tenga el GRANT.
SELECT policyname, cmd, roles, qual
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'usuario';


-- ---------------------------------------------------------------------
-- BLOQUE 5 — Poblacion de identidad disponible
-- ---------------------------------------------------------------------

-- 5.a — Usuarios de Auth y que traen HOY en app_metadata.
--   Los 6 de CFG-04 deben traer tenant_id, user_role y rol escritos a
--   mano por el seed. Eso es precisamente lo que hace tautologica la
--   medicion: el seed de la Fase 2 sembrara usuarios SIN estos claims,
--   para que un tenant_id en el token pruebe el hook y no el seed.
SELECT u.email,
       u.raw_app_meta_data ->> 'tenant_id' AS meta_tenant_id,
       u.raw_app_meta_data ->> 'user_role' AS meta_user_role,
       u.raw_app_meta_data ->> 'rol'       AS meta_rol,
       u.email_confirmed_at IS NOT NULL    AS confirmado
  FROM auth.users u
 ORDER BY u.email;

-- 5.b — ¿Se cumple la convencion usuario.id = auth.users.id?
--   El hook resuelve el tenant por event->>'user_id', que es el id de
--   auth.users. Sin esa correspondencia no tiene por donde entrar a
--   public.usuario. Filas con `en_public = false` rompen el hook.
SELECT a.email,
       (p.id IS NOT NULL) AS en_public,
       p.tenant_id,
       p.rol,
       p.estado
  FROM auth.users a
  LEFT JOIN public.usuario p ON p.id = a.id
 ORDER BY (p.id IS NULL) DESC, a.email;

-- 5.c — Tenants disponibles. La PoC reutiliza los 2 de CFG-04; el tenant
--   desechable de CFG-09 (`poc-concurrencia`) no deberia estorbar, pero
--   se lista para que el informe declare el estado real del ambiente.
SELECT t.id, t.slug, count(u.id) AS usuarios
  FROM public.tenant t
  LEFT JOIN public.usuario u ON u.tenant_id = t.id
 GROUP BY t.id, t.slug
 ORDER BY t.slug;


-- ---------------------------------------------------------------------
-- BLOQUE 6 — Storage: ¿es ejecutable el caso 6 de ADR-0015?
-- ---------------------------------------------------------------------
-- Resuelve D4. El caso 6 que enumera
-- Project/Documento_Herramientas_Politicas_Lineamientos_V2.md seccion
-- 4.3.3 es el aislamiento de documentos KYC en Supabase Storage
-- (ADR-0013). Es un camino distinto al de PostgREST: bucket, objetos y
-- politicas sobre storage.objects. Si no esta aprovisionado, el caso se
-- declara no ejecutable con su justificacion en vez de omitirse.

-- 6.a — Buckets existentes.
SELECT id, name, public, created_at
  FROM storage.buckets
 ORDER BY name;

-- 6.b — Politicas sobre storage.objects.
SELECT policyname, cmd, roles, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'storage' AND tablename = 'objects'
 ORDER BY policyname;

-- 6.c — ¿Hay filas de KYC que referencien rutas de Storage?
--   `documento_kyc.ruta_storage` es el puente entre la tabla y el bucket.
--   Sin filas no hay dato ajeno que intentar leer, y el caso 6 necesita
--   que la Fase 2 siembre al menos un documento por tenant.
SELECT d.tenant_id, count(*) AS documentos,
       count(*) FILTER (WHERE d.ruta_storage IS NOT NULL) AS con_ruta
  FROM public.documento_kyc d
 GROUP BY d.tenant_id
 ORDER BY d.tenant_id;


-- ---------------------------------------------------------------------
-- BLOQUE 7 — Entorno
-- ---------------------------------------------------------------------
-- Para el encabezado del informe y para interpretar los tiempos de la
-- Fase 6. El algoritmo de firma se verifica fuera de la base, contra
-- /auth/v1/.well-known/jwks.json: la corrida del 2026-09-21 devolvio una
-- sola clave ES256 (kid a069a215-25f2-4958-8b90-ef5b289a025a). Se repite
-- esa consulta al ejecutar, porque una rotacion de clave cambiaria el
-- benchmark de verificacion offline.
SELECT version() AS motor,
       current_setting('server_version_num') AS version_num,
       current_setting('default_transaction_isolation') AS aislamiento,
       current_setting('max_connections') AS max_connections;

-- 7.b — Extensiones que la PoC asume (pgcrypto para sembrar usuarios).
SELECT extname, extversion
  FROM pg_extension
 ORDER BY extname;
