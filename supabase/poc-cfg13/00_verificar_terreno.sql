-- =====================================================================
-- MANI — Verificacion de terreno para la PoC de Storage KYC (CFG-13)
-- =====================================================================
-- Ticket: SCRUM-930 (CFG-13) · Antes de SCRUM-977
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
--
-- SOLO LECTURA. No modifica datos ni esquema.
--
-- QUE RESPONDE
--   T1. ¿Sigue QA sin buckets ni politicas sobre storage.objects?
--       (SCRUM-1053 lo verifico el 2026-09-22: 0 y 0.) Si ya hay algo,
--       alguien aprovisiono Storage por fuera y hay que saber que antes
--       de pisarlo.
--   T2. ¿Esta montado el hook de CFG-12? La politica kyc_isolation lee
--       `app_metadata.tenant_id` y `app_metadata.user_role` del JWT; sin
--       el hook, las cuentas @cfg12 salen sin tenant y todo da denegado
--       por la razon equivocada.
--   T3. ¿Existen las cuentas que usa la suite, con el rol esperado?
--   T4. ¿Que `ruta_storage` tienen los documento_kyc sembrados por
--       CFG-12? (Hallazgo 3 del plan: se espera el formato viejo
--       `kyc/<tenant>/...`, que no cumple ADR-0013.)
--
-- COMO USARLO
--   Pegar entero en el SQL Editor, ejecutar, copiar la celda. Correrlo
--   otra vez despues de 10_bucket_kyc.sql: t1 debe pasar a 1 bucket y 1
--   politica.
--
--   Las tablas storage.* existen en QA (sondeo de CFG-12,
--   01_resumen_terreno.sql, 2026-09-22), asi que aqui se nombran
--   directamente.
-- =====================================================================

SELECT jsonb_pretty(jsonb_build_object(

  't1a_buckets', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', b.id, 'publico', b.public,
             'limite_bytes', b.file_size_limit,
             'mime', b.allowed_mime_types) ORDER BY b.id), '[]'::jsonb)
      FROM storage.buckets b
  ),

  't1b_politicas_storage_objects', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'politica', policyname, 'cmd', cmd, 'roles', roles,
             'using', qual, 'with_check', with_check) ORDER BY policyname), '[]'::jsonb)
      FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
  ),

  't1c_objetos_por_bucket', (
    SELECT coalesce(jsonb_object_agg(o.bucket_id, o.n), '{}'::jsonb)
      FROM (SELECT bucket_id, count(*) AS n FROM storage.objects GROUP BY bucket_id) o
  ),

  -- La funcion existe no basta: tiene que estar registrada en
  -- Authentication > Hooks. Eso no se ve desde SQL; lo confirma la
  -- peticion de login de la suite ("el token trae tenant_id") con
  -- las cuentas @cfg12, que no tienen claims propios.
  't2_funcion_hook', (
    SELECT coalesce(jsonb_agg(n.nspname || '.' || p.proname), '[]'::jsonb)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname ILIKE '%access_token%'
  ),

  't3_cuentas_suite', (
    SELECT jsonb_agg(jsonb_build_object(
             'email', a.email, 'uid', a.id,
             'tenant', u.tenant_id, 'rol', u.rol) ORDER BY a.email)
      FROM auth.users a LEFT JOIN public.usuario u ON u.id = a.id
     WHERE a.email IN ('aliado.t1@qa.mani.test', 'admin.t1@qa.mani.test',
                       'cliente.t1@qa.mani.test', 'aliado.t2@qa.mani.test',
                       'admin.t2@qa.mani.test', 'hook.t1@cfg12.mani.test')
  ),

  -- aliado.id vs usuario_id: la diferencia que motiva el hallazgo 2.
  't3b_aliados', (
    SELECT jsonb_agg(jsonb_build_object(
             'aliado_id', al.id, 'usuario_id', al.usuario_id,
             'tenant', al.tenant_id) ORDER BY al.tenant_id)
      FROM public.aliado al
  ),

  't4_documentos_kyc', (
    SELECT jsonb_agg(jsonb_build_object(
             'id', d.id, 'tenant', d.tenant_id, 'aliado_id', d.aliado_id,
             'ruta_storage', d.ruta_storage) ORDER BY d.id)
      FROM public.documento_kyc d
  )

)) AS terreno_cfg13;
