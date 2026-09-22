-- =====================================================================
-- MANI — Resumen de terreno en una sola consulta (CFG-12)
-- =====================================================================
-- Ticket: SCRUM-929 (CFG-12) · Complementa 00_verificar_terreno.sql
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
--
-- SOLO LECTURA. No modifica datos ni esquema.
--
-- POR QUE EXISTE
--   El SQL Editor del dashboard muestra unicamente el resultado de la
--   ultima sentencia. Correr 00_verificar_terreno.sql bloque por bloque
--   son ~18 viajes de ida y vuelta. Esta consulta devuelve UNA fila con
--   un jsonb que contiene las mismas respuestas, para pegar una vez y
--   copiar el resultado completo.
--
--   00_verificar_terreno.sql sigue siendo el artefacto de evidencia:
--   sus bloques son legibles uno por uno y explican por que se pregunta
--   cada cosa. Este archivo es la version operativa del mismo contenido.
--
-- COMO USARLO
--   Pegar entero en el SQL Editor, ejecutar, y copiar la celda de salida.
--
-- TOLERANCIA A AUSENCIAS
--   Cada sub-consulta que toca una tabla opcional esta protegida con
--   to_regclass. Si `schema_migrations`, `documento_kyc` o el esquema
--   `storage` no existen, ese campo sale en null en vez de abortar la
--   consulta entera y dejarnos sin ninguna de las otras respuestas.
-- =====================================================================

SELECT jsonb_pretty(jsonb_build_object(

  'meta', jsonb_build_object(
    'ejecutado', now(),
    'base', current_database(),
    'rol_ejecutor', current_user,
    'motor', version(),
    'aislamiento', current_setting('default_transaction_isolation'),
    'max_connections', current_setting('max_connections')
  ),

  -- D1/D2 — de donde lee el hook, y si el modelo admite multi-tenant
  'b1a_columnas_usuario', (
    SELECT jsonb_agg(jsonb_build_object(
             'columna', column_name, 'tipo', data_type,
             'nullable', is_nullable, 'default', column_default)
             ORDER BY ordinal_position)
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'usuario'
  ),

  'b1b_constraints_usuario', (
    SELECT jsonb_agg(jsonb_build_object(
             'nombre', con.conname,
             'definicion', pg_get_constraintdef(con.oid)) ORDER BY con.conname)
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'usuario'
  ),

  -- 0 filas => un usuario pertenece a exactamente un tenant
  'b1c_tablas_membresia', (
    SELECT jsonb_agg(jsonb_build_object('tabla', t.relname, 'columnas', t.cols))
      FROM (
        SELECT c.relname,
               string_agg(a.attname, ', ' ORDER BY a.attnum) AS cols
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
         WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname <> 'usuario'
           AND EXISTS (SELECT 1 FROM pg_attribute x
                        WHERE x.attrelid = c.oid AND x.attname = 'tenant_id')
           AND EXISTS (SELECT 1 FROM pg_attribute y
                        WHERE y.attrelid = c.oid AND y.attname IN ('usuario_id','user_id'))
         GROUP BY c.relname
      ) t
  ),

  'b1d_usuarios_multi_tenant', (
    SELECT jsonb_agg(jsonb_build_object('email', s.email, 'tenants', s.tenants, 'filas', s.filas))
      FROM (
        SELECT u.email, count(DISTINCT u.tenant_id) AS tenants, count(*) AS filas
          FROM public.usuario u
         GROUP BY u.email
        HAVING count(*) > 1 OR count(DISTINCT u.tenant_id) > 1
      ) s
  ),

  -- ¿Ya hay un hook montado? Esperado: vacio
  'b2_hooks_existentes', (
    SELECT jsonb_agg(jsonb_build_object(
             'esquema', n.nspname, 'funcion', p.proname,
             'args', pg_get_function_identity_arguments(p.oid),
             'security_definer', p.prosecdef, 'volatilidad', p.provolatile))
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname ILIKE '%access_token%' OR p.proname ILIKE '%custom_claims%'
  ),

  -- RLS: el ambiente sirve para medir, o no
  'b3a_tablas_rls_sin_politicas', (
    SELECT jsonb_agg(t.relname ORDER BY t.relname)
      FROM (
        SELECT c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_policy pol ON pol.polrelid = c.oid
         WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
         GROUP BY c.relname
        HAVING count(pol.polname) = 0
      ) t
  ),

  'b3a_resumen_rls', (
    SELECT jsonb_agg(jsonb_build_object(
             'tabla', t.relname, 'rls', t.rls, 'forzado', t.forzado, 'politicas', t.pol)
             ORDER BY t.relname)
      FROM (
        SELECT c.relname, c.relrowsecurity AS rls,
               c.relforcerowsecurity AS forzado, count(pol.polname) AS pol
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_policy pol ON pol.polrelid = c.oid
         WHERE n.nspname = 'public' AND c.relkind = 'r'
         GROUP BY c.relname, c.relrowsecurity, c.relforcerowsecurity
      ) t
  ),

  -- with_check en null => Postgres reutiliza USING. Lo comprueba el caso 3b
  'b3b_politicas', (
    SELECT jsonb_agg(jsonb_build_object(
             'tabla', tablename, 'politica', policyname, 'cmd', cmd,
             'roles', roles, 'using', qual, 'with_check', with_check)
             ORDER BY tablename, policyname)
      FROM pg_policies WHERE schemaname = 'public'
  ),

  'b3c_total_politicas_sin_versionar', (
    SELECT count(*) FROM pg_policies WHERE schemaname = 'public'
  ),

  'b3d_migraciones_aplicadas', (
    SELECT CASE WHEN to_regclass('public.schema_migrations') IS NULL THEN NULL
           ELSE (SELECT jsonb_agg(jsonb_build_object(
                          'version', m.version, 'descripcion', m.description,
                          'aplicada', m.applied_at) ORDER BY m.version)
                   FROM public.schema_migrations m) END
  ),

  -- D3 — ¿el hook alcanza a leer la tabla?
  'b4a_roles', (
    SELECT jsonb_agg(jsonb_build_object(
             'rol', rolname, 'superuser', rolsuper, 'bypassrls', rolbypassrls)
             ORDER BY rolname)
      FROM pg_roles
     WHERE rolname IN ('supabase_auth_admin','authenticated','anon','service_role')
  ),

  'b4b_privilegios_auth_admin', (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin')
           THEN NULL
           ELSE jsonb_build_object(
             'usage_public', has_schema_privilege('supabase_auth_admin','public','USAGE'),
             'select_usuario', has_table_privilege('supabase_auth_admin','public.usuario','SELECT'),
             'select_tenant', has_table_privilege('supabase_auth_admin','public.tenant','SELECT')) END
  ),

  'b4c_politicas_usuario', (
    SELECT jsonb_agg(jsonb_build_object(
             'politica', policyname, 'cmd', cmd, 'roles', roles, 'using', qual))
      FROM pg_policies WHERE schemaname='public' AND tablename='usuario'
  ),

  -- Poblacion de identidad
  'b5a_app_metadata_actual', (
    SELECT jsonb_agg(jsonb_build_object(
             'email', u.email,
             'meta_tenant_id', u.raw_app_meta_data ->> 'tenant_id',
             'meta_user_role', u.raw_app_meta_data ->> 'user_role',
             'meta_rol', u.raw_app_meta_data ->> 'rol',
             'confirmado', u.email_confirmed_at IS NOT NULL) ORDER BY u.email)
      FROM auth.users u
  ),

  -- filas con en_public=false rompen el hook: no tiene por donde entrar
  'b5b_correspondencia_auth_public', (
    SELECT jsonb_agg(jsonb_build_object(
             'email', a.email, 'en_public', p.id IS NOT NULL,
             'tenant_id', p.tenant_id, 'rol', p.rol, 'estado', p.estado)
             ORDER BY (p.id IS NULL) DESC, a.email)
      FROM auth.users a LEFT JOIN public.usuario p ON p.id = a.id
  ),

  'b5c_tenants', (
    SELECT jsonb_agg(jsonb_build_object('id', t.id, 'slug', t.slug, 'usuarios', t.n) ORDER BY t.slug)
      FROM (SELECT t.id, t.slug, count(u.id) AS n
              FROM public.tenant t LEFT JOIN public.usuario u ON u.tenant_id = t.id
             GROUP BY t.id, t.slug) t
  ),

  -- D4 — ¿es ejecutable el caso 6 de ADR-0015?
  'b6a_buckets', (
    SELECT CASE WHEN to_regclass('storage.buckets') IS NULL THEN NULL
           ELSE (SELECT jsonb_agg(jsonb_build_object(
                          'id', b.id, 'nombre', b.name, 'publico', b.public) ORDER BY b.name)
                   FROM storage.buckets b) END
  ),

  'b6b_politicas_storage', (
    SELECT jsonb_agg(jsonb_build_object(
             'politica', policyname, 'cmd', cmd, 'roles', roles,
             'using', qual, 'with_check', with_check) ORDER BY policyname)
      FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
  ),

  'b6c_documentos_kyc', (
    SELECT CASE WHEN to_regclass('public.documento_kyc') IS NULL THEN NULL
           ELSE (SELECT jsonb_agg(jsonb_build_object(
                          'tenant_id', d.tenant_id, 'documentos', d.n, 'con_ruta', d.con_ruta))
                   FROM (SELECT tenant_id, count(*) AS n,
                                count(*) FILTER (WHERE ruta_storage IS NOT NULL) AS con_ruta
                           FROM public.documento_kyc GROUP BY tenant_id) d) END
  ),

  'b7_extensiones', (
    SELECT jsonb_agg(jsonb_build_object('nombre', extname, 'version', extversion) ORDER BY extname)
      FROM pg_extension
  )

)) AS resumen_terreno_cfg12;
