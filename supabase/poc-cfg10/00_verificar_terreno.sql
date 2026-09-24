-- =====================================================================
-- MANI — Verificacion de terreno para la PoC de cobertura geografica (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Antes de SCRUM-965
-- Ambiente: SOLO QA (proyecto Supabase MANI-QA)
--
-- SOLO LECTURA. No modifica datos ni esquema.
--
-- QUE RESPONDE
--   T1. ¿PostGIS esta disponible en QA? ¿Ya esta instalado? Decide si las
--       cuatro variantes se miden en QA o en un Postgres local con PostGIS.
--   T2. ¿Que extensiones hay instaladas y en que esquema? (Supabase las
--       pone en "extensions"; la PoC tiene que referenciarlas ahi.)
--   T3. ¿Que indices tienen hoy las tablas de la consulta de despacho?
--       El DDL solo declara indice por "tenant_id" en "cobertura_aliado" y
--       "aliado_categoria"; "UNIQUE (aliado_id, zona_id)" no sirve para
--       buscar por zona. Es el hallazgo que la linea base tiene que medir.
--   T4. ¿Cuantas filas hay hoy? (El seed QA multitenant deja 3 zonas y 2
--       coberturas; la PoC no los toca, trabaja en el esquema poc_cfg10.)
--   T5. ¿RLS activo en esas tablas? La PoC replica las mismas politicas.
--   T6. ¿Existe ya el esquema poc_cfg10? Si si, alguien corrio la PoC antes.
--
-- COMO USARLO
--   Pegar entero en el SQL Editor, ejecutar, copiar la celda.
-- =====================================================================

SELECT json_build_object(
  't1_postgis', (
    SELECT json_agg(json_build_object(
             'name', name,
             'default_version', default_version,
             'installed_version', installed_version))
    FROM pg_available_extensions
    WHERE name IN ('postgis', 'btree_gist')
  ),
  't2_extensiones', (
    SELECT json_agg(e.extname || ' ' || e.extversion || ' @' || n.nspname ORDER BY e.extname)
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  ),
  't2_pg_version', version(),
  't3_indices', (
    SELECT json_agg(tablename || ': ' || indexdef ORDER BY tablename, indexname)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('zona', 'cobertura_aliado', 'aliado_categoria',
                        'aliado', 'categoria_servicio')
  ),
  't4_filas', json_build_object(
    'tenant',             (SELECT count(*) FROM public.tenant),
    'aliado',             (SELECT count(*) FROM public.aliado),
    'zona',               (SELECT count(*) FROM public.zona),
    'cobertura_aliado',   (SELECT count(*) FROM public.cobertura_aliado),
    'categoria_servicio', (SELECT count(*) FROM public.categoria_servicio),
    'aliado_categoria',   (SELECT count(*) FROM public.aliado_categoria)
  ),
  't5_rls', (
    SELECT json_agg(c.relname || '=' || c.relrowsecurity ORDER BY c.relname)
    FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relname IN ('zona', 'cobertura_aliado', 'aliado_categoria',
                        'aliado', 'categoria_servicio')
  ),
  't5_columnas_categoria_servicio', (
    SELECT json_agg(column_name || ' ' || data_type ORDER BY ordinal_position)
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'categoria_servicio'
  ),
  't6_esquema_poc_cfg10', EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'poc_cfg10')
) AS terreno;
