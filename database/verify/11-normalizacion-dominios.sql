-- =====================================================================
-- SCRUM-1057: verificación de la migración 007 (normalización de dominios)
-- Comprueba que no quedan valores viejos, que la bandeja del aliado y el
-- catálogo responden, que el CHECK de categorías quedó validado, y que las
-- PoC CFG-12 (claims del hook) y CFG-13 (kyc_isolation) siguen aislando.
--
-- Uso: pegar completo en el SQL Editor de Supabase QA DESPUÉS de aplicar
-- 007_normalizar_dominios.sql. Es de solo lectura: un único SELECT, sin
-- tablas ni escrituras (el SQL Editor no pide confirmar operaciones
-- destructivas). Las sesiones se simulan con set_config y las funciones
-- auxiliares viven en pg_temp, que desaparece al cerrar la conexión.
-- Devuelve una sola celda JSON con PASA/FALLA por prueba y el total.
-- Depende de las identidades de los seeds de CFG-04, CFG-09 y CFG-12.
-- =====================================================================

-- Sesion simulada: los claims son EXACTAMENTE los que emite el hook de CFG-12.
CREATE OR REPLACE FUNCTION pg_temp.sesion(p_email text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_id uuid; v_claims jsonb;
BEGIN
  SELECT id INTO v_id FROM public.usuario WHERE email = p_email;
  v_claims := public.custom_access_token_hook(jsonb_build_object('user_id', v_id,
                'claims', jsonb_build_object('role','authenticated','sub', v_id))) -> 'claims';
  PERFORM set_config('request.jwt.claims', v_claims::text, false);
  PERFORM set_config('request.jwt.claim.sub', v_id::text, false);
  RETURN v_claims;
END $f$;

CREATE OR REPLACE FUNCTION pg_temp.rpc(p_email text, p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.sesion(p_email);
  EXECUTE p_sql INTO v;
  RETURN 'filas=' || jsonb_array_length(v);
EXCEPTION WHEN OTHERS THEN
  RETURN 'error: ' || split_part(SQLERRM, ':', 1);
END $f$;

CREATE OR REPLACE FUNCTION pg_temp.claims(p_email text) RETURNS text LANGUAGE sql AS $f$
  SELECT (c->'app_metadata'->>'user_role') || '/' || (c->'app_metadata'->>'rol')
  FROM (SELECT pg_temp.sesion(p_email) c) x
$f$;

-- CFG-13: cuenta los objetos de KYC visibles con rol authenticated y los claims del hook.
CREATE OR REPLACE FUNCTION pg_temp.kyc(p_email text, p_filtro text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int;
BEGIN
  PERFORM pg_temp.sesion(p_email);
  SET LOCAL ROLE authenticated;
  EXECUTE 'SELECT count(*) FROM storage.objects WHERE bucket_id = ''kyc-documentos'' AND ' || p_filtro INTO n;
  RESET ROLE;
  RETURN n::text;
END $f$;

WITH r(orden, prueba, obtenido, esperado) AS (
  SELECT 0, '0. schema_migrations incluye 007',
         (SELECT (count(*) FILTER (WHERE version = '007'))::text FROM public.schema_migrations), '1'

  -- 1. Valores viejos que quedan (tabla aprobada en SCRUM-1057)
  UNION ALL SELECT 1, '1. valores viejos restantes', (
    (SELECT count(*) FROM usuario WHERE rol IN ('admin_tenant','aliado','cliente') OR estado = 'activo') +
    (SELECT count(*) FROM tenant WHERE estado = 'activo') +
    (SELECT count(*) FROM aliado WHERE estado_verificacion = 'aprobado' OR tipo IN ('persona_natural','empresa')) +
    (SELECT count(*) FROM cliente WHERE tipo IN ('persona_natural','empresa')) +
    (SELECT count(*) FROM categoria_servicio WHERE estado = 'activa') +
    (SELECT count(*) FROM documento_kyc WHERE estado = 'aprobado' OR tipo_documento = 'cedula') +
    (SELECT count(*) FROM solicitud WHERE estado = 'assigned') +
    (SELECT count(*) FROM zona WHERE estado = 'activa' OR nivel IN ('ciudad','localidad')))::text, '0'

  -- 2. Bandeja del aliado (US-04.1.4). Si la solicitud de CFG-09 esta
  --    asignada, la ve su aliado; si esta pendiente, la ve aliado.poc.1
  --    como elegible.
  UNION ALL SELECT 2, '2. bandeja del aliado de la solicitud CFG-09',
         pg_temp.rpc(coalesce(
           (SELECT u.email FROM solicitud s JOIN aliado a ON a.id = s.aliado_id JOIN usuario u ON u.id = a.usuario_id
             WHERE s.id = 'a0000000-0000-4000-8000-900000000001'),
           'aliado.poc.1@poc.mani.test'), 'SELECT public.listar_solicitudes_aliado()'), 'filas=1'

  -- 3. Catalogo (US-03.1.1, US-03.1.3, US-04.1.1)
  UNION ALL SELECT 3, '3a. catalogo aliado.t1 listar_categorias_tenant',
         pg_temp.rpc('aliado.t1@qa.mani.test', 'SELECT public.listar_categorias_tenant()'), 'filas=1'
  UNION ALL SELECT 4, '3b. catalogo admin.t1 listar_categorias_admin',
         pg_temp.rpc('admin.t1@qa.mani.test', 'SELECT public.listar_categorias_admin()'), 'filas=1'
  UNION ALL SELECT 5, '3c. catalogo cliente.t1 listar_categorias_cliente',
         pg_temp.rpc('cliente.t1@qa.mani.test', 'SELECT public.listar_categorias_cliente()'), 'filas=1'

  -- 4. CHECK de 003: ninguna fila lo viola y quedo validado, asi que un
  --    UPDATE a una categoria existente ya no puede fallar por el.
  UNION ALL SELECT 6, '4. categorias que violan ck_categoria_estado',
         (SELECT count(*) FROM categoria_servicio WHERE estado NOT IN ('ACTIVO','INACTIVO'))::text, '0'
  UNION ALL SELECT 7, '4b. ck_categoria_estado validado',
         coalesce((SELECT convalidated::text FROM pg_constraint WHERE conname = 'ck_categoria_estado'), 'no existe'), 'true'

  -- 5. CFG-12: claims del hook (contrato ADR-0018, en minuscula)
  UNION ALL SELECT 8,  '5. hook admin.t1',  pg_temp.claims('admin.t1@qa.mani.test'),   'admin_tenant/admin_tenant'
  UNION ALL SELECT 9,  '5. hook aliado.t1', pg_temp.claims('aliado.t1@qa.mani.test'),  'aliado/aliado'
  UNION ALL SELECT 10, '5. hook cliente.t1', pg_temp.claims('cliente.t1@qa.mani.test'), 'cliente/cliente'
  UNION ALL SELECT 11, '5. hook hook.t1 (CFG-12)', pg_temp.claims('hook.t1@cfg12.mani.test'), 'aliado/aliado'
  UNION ALL SELECT 12, '5. hook hook.t2 (CFG-12)', pg_temp.claims('hook.t2@cfg12.mani.test'), 'cliente/cliente'
  UNION ALL SELECT 13, '5b. hook tenant_id admin.t1',
         pg_temp.sesion('admin.t1@qa.mani.test')->'app_metadata'->>'tenant_id', '10000000-0000-4000-8000-000000000011'
  UNION ALL SELECT 14, '5c. hook V4 fail closed (user inexistente)',
         (public.custom_access_token_hook(jsonb_build_object('user_id','00000000-0000-4000-8000-000000000000',
            'claims', jsonb_build_object('role','authenticated')))->'claims'->'app_metadata')::text,
         '{"rol": null, "tenant_id": null, "user_role": null}'

  -- 6. CFG-13: kyc_isolation (ADR-0015 caso 6)
  UNION ALL SELECT 15, '6a. aliado.t1 ve su propio KYC',
         pg_temp.kyc('aliado.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000011/%'''), '>=1'
  UNION ALL SELECT 16, '6b. aliado.t1 no ve KYC de otro tenant',
         pg_temp.kyc('aliado.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '0'
  UNION ALL SELECT 17, '6c. admin.t1 ve KYC de su tenant',
         pg_temp.kyc('admin.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000011/%'''), '>=1'
  UNION ALL SELECT 18, '6d. admin.t1 no ve KYC de otro tenant',
         pg_temp.kyc('admin.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '0'
  UNION ALL SELECT 19, '6e. cliente.t1 no ve KYC',
         pg_temp.kyc('cliente.t1@qa.mani.test', 'true'), '0'
  UNION ALL SELECT 20, '6f. admin.t2 ve KYC de su tenant',
         pg_temp.kyc('admin.t2@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '>=1'
), evaluado AS (
  SELECT orden, prueba, obtenido, esperado,
         (obtenido = esperado OR (esperado = '>=1' AND obtenido ~ '^[0-9]+$' AND obtenido::int >= 1)) AS pasa
  FROM r
)
SELECT jsonb_build_object(
  'total', count(*) FILTER (WHERE pasa) || '/' || count(*) || ' pasan',
  'pruebas', jsonb_agg(jsonb_build_object('resultado', CASE WHEN pasa THEN 'PASA' ELSE 'FALLA' END,
                                          'prueba', prueba, 'obtenido', obtenido, 'esperado', esperado)
                       ORDER BY orden)
) AS verificacion
FROM evaluado;
