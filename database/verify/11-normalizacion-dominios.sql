-- =====================================================================
-- SCRUM-1057: verificación de la migración 007 (normalización de dominios)
-- Comprueba que no quedan valores viejos, que la bandeja del aliado y el
-- catálogo responden, que el CHECK de categorías quedó validado, y que las
-- PoC CFG-12 (claims del hook) y CFG-13 (kyc_isolation) siguen aislando.
--
-- Uso: pegar completo en el SQL Editor de Supabase QA DESPUÉS de aplicar
-- 007_normalizar_dominios.sql. Solo lee: las sesiones se simulan con
-- set_config y los objetos auxiliares son temporales de la sesión.
-- El resultado es una tabla PASA/FALLA; la última fila da el total.
-- Depende de las identidades de los seeds de CFG-04, CFG-09 y CFG-12.
-- =====================================================================

SET client_min_messages = warning;

DROP TABLE IF EXISTS pg_temp.resultado;
CREATE TEMP TABLE resultado (orden serial, prueba text, obtenido text, esperado text);

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

-- 1. Valores viejos que quedan (tabla aprobada en SCRUM-1057)
INSERT INTO resultado (prueba, obtenido, esperado)
SELECT '1. valores viejos restantes', (
  (SELECT count(*) FROM usuario WHERE rol IN ('admin_tenant','aliado','cliente') OR estado = 'activo') +
  (SELECT count(*) FROM tenant WHERE estado = 'activo') +
  (SELECT count(*) FROM aliado WHERE estado_verificacion = 'aprobado' OR tipo IN ('persona_natural','empresa')) +
  (SELECT count(*) FROM cliente WHERE tipo IN ('persona_natural','empresa')) +
  (SELECT count(*) FROM categoria_servicio WHERE estado = 'activa') +
  (SELECT count(*) FROM documento_kyc WHERE estado = 'aprobado' OR tipo_documento = 'cedula') +
  (SELECT count(*) FROM solicitud WHERE estado = 'assigned') +
  (SELECT count(*) FROM zona WHERE estado = 'activa' OR nivel IN ('ciudad','localidad')))::text, '0';

-- 2. Bandeja del aliado (US-04.1.4): aliado de CFG-09 con la solicitud asignada
INSERT INTO resultado VALUES (DEFAULT, '2. bandeja aliado.poc.1 listar_solicitudes_aliado',
  pg_temp.rpc('aliado.poc.1@poc.mani.test', 'SELECT public.listar_solicitudes_aliado()'), 'filas=1');

-- 3. Catalogo (US-03.1.1, US-03.1.3, US-04.1.1)
INSERT INTO resultado VALUES (DEFAULT, '3a. catalogo aliado.t1 listar_categorias_tenant',
  pg_temp.rpc('aliado.t1@qa.mani.test', 'SELECT public.listar_categorias_tenant()'), 'filas=1');
INSERT INTO resultado VALUES (DEFAULT, '3b. catalogo admin.t1 listar_categorias_admin',
  pg_temp.rpc('admin.t1@qa.mani.test', 'SELECT public.listar_categorias_admin()'), 'filas=1');
INSERT INTO resultado VALUES (DEFAULT, '3c. catalogo cliente.t1 listar_categorias_cliente',
  pg_temp.rpc('cliente.t1@qa.mani.test', 'SELECT public.listar_categorias_cliente()'), 'filas=1');

-- 4. UPDATE a una categoria existente contra el CHECK de 003
DO $t$
BEGIN
  BEGIN
    UPDATE categoria_servicio SET nombre = nombre WHERE tenant_id = '10000000-0000-4000-8000-000000000011';
    INSERT INTO resultado (prueba, obtenido, esperado) VALUES ('4. UPDATE categoria existente', 'ok', 'ok');
    RAISE EXCEPTION 'rollback_intencional';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'rollback_intencional' THEN
      INSERT INTO resultado (prueba, obtenido, esperado) VALUES ('4. UPDATE categoria existente', 'error: ' || SQLERRM, 'ok');
    ELSE
      INSERT INTO resultado (prueba, obtenido, esperado) VALUES ('4. UPDATE categoria existente', 'ok', 'ok');
    END IF;
  END;
END $t$;
INSERT INTO resultado (prueba, obtenido, esperado)
SELECT '4b. ck_categoria_estado validado', coalesce((SELECT convalidated::text FROM pg_constraint WHERE conname = 'ck_categoria_estado'), 'no existe'), 'true';

-- 5. CFG-12: claims del hook (contrato ADR-0018, en minuscula)
INSERT INTO resultado (prueba, obtenido, esperado)
SELECT '5. hook user_role/rol ' || e, (c->'app_metadata'->>'user_role') || '/' || (c->'app_metadata'->>'rol'), esp
FROM (VALUES ('admin.t1@qa.mani.test','admin_tenant/admin_tenant'), ('aliado.t1@qa.mani.test','aliado/aliado'),
             ('cliente.t1@qa.mani.test','cliente/cliente'), ('hook.t1@cfg12.mani.test','aliado/aliado'),
             ('hook.t2@cfg12.mani.test','cliente/cliente')) v(e, esp),
     LATERAL (SELECT pg_temp.sesion(e) c) s;
INSERT INTO resultado (prueba, obtenido, esperado)
SELECT '5b. hook tenant_id admin.t1', pg_temp.sesion('admin.t1@qa.mani.test')->'app_metadata'->>'tenant_id', '10000000-0000-4000-8000-000000000011';
INSERT INTO resultado (prueba, obtenido, esperado)
SELECT '5c. hook V4 fail closed (user inexistente)', (h->'claims'->'app_metadata')::text, '{"rol": null, "tenant_id": null, "user_role": null}'
FROM (SELECT public.custom_access_token_hook(jsonb_build_object('user_id','00000000-0000-4000-8000-000000000000','claims',jsonb_build_object('role','authenticated'))) h) x;

-- 6. CFG-13: kyc_isolation (ADR-0015 caso 6), con rol authenticated y claims del hook
CREATE OR REPLACE FUNCTION pg_temp.kyc(p_email text, p_filtro text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int;
BEGIN
  PERFORM pg_temp.sesion(p_email);
  SET LOCAL ROLE authenticated;
  EXECUTE 'SELECT count(*) FROM storage.objects WHERE bucket_id = ''kyc-documentos'' AND ' || p_filtro INTO n;
  RESET ROLE;
  RETURN n::text;
END $f$;
INSERT INTO resultado VALUES (DEFAULT, '6a. aliado.t1 ve su propio KYC', pg_temp.kyc('aliado.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000011/%'''), '>=1');
INSERT INTO resultado VALUES (DEFAULT, '6b. aliado.t1 no ve KYC de otro tenant', pg_temp.kyc('aliado.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '0');
INSERT INTO resultado VALUES (DEFAULT, '6c. admin.t1 ve KYC de su tenant', pg_temp.kyc('admin.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000011/%'''), '>=1');
INSERT INTO resultado VALUES (DEFAULT, '6d. admin.t1 no ve KYC de otro tenant', pg_temp.kyc('admin.t1@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '0');
INSERT INTO resultado VALUES (DEFAULT, '6e. cliente.t1 no ve KYC de su tenant', pg_temp.kyc('cliente.t1@qa.mani.test', 'true'), '0');
INSERT INTO resultado VALUES (DEFAULT, '6f. admin.t2 ve KYC de su tenant', pg_temp.kyc('admin.t2@qa.mani.test', 'name LIKE ''10000000-0000-4000-8000-000000000021/%'''), '>=1');

SELECT resultado, prueba, obtenido, esperado FROM (
  SELECT orden, CASE WHEN (obtenido = esperado OR (esperado = '>=1' AND obtenido ~ '^[0-9]+$' AND obtenido::int >= 1)) THEN 'PASA' ELSE 'FALLA' END AS resultado, prueba, obtenido, esperado FROM resultado
  UNION ALL
  SELECT 999, 'TOTAL', count(*) FILTER (WHERE (obtenido = esperado OR (esperado = '>=1' AND obtenido ~ '^[0-9]+$' AND obtenido::int >= 1))) || '/' || count(*) || ' pasan', NULL, NULL FROM resultado
) r ORDER BY orden;
