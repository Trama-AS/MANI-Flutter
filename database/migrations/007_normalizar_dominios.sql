-- =====================================================================
-- 007 · SCRUM-1057 — Normalizar los valores de dominio al formato del código
-- Los datos que el seed de CFG-04 (supabase/seed/seed_qa_multitenant.sql)
-- dejó en QA usan minúscula y en parte inglés (`aliado`, `activo`,
-- `aprobado`, `assigned`...), pero 002–006 y la app comparan contra
-- MAYÚSCULA en español (`ALIADO`, `ACTIVO`, `VERIFICADO`, `ASIGNADA`...).
-- Con esa diferencia, la bandeja del aliado y el catálogo responden 403 y
-- cualquier UPDATE a una categoría existente choca con ck_categoria_estado.
--
-- Orden de la migración (todo en una transacción: entra completa o nada):
--   1. Compatibilidad de las PoC, ANTES de tocar datos, para que no haya un
--      instante en que el token o la política de KYC dependan de mayúsculas:
--        * Custom Access Token Hook (CFG-12): emite `lower(rol)`. El claim
--          sigue en minúscula, que es el contrato de ADR-0018
--          ("user_role": "aliado") y lo que verifica la suite Newman.
--        * kyc_isolation (CFG-13): compara el rol del token sin depender de
--          mayúscula o minúscula.
--      Ambos se reemplazan solo si ya existen: esta migración no los crea.
--   2. Un UPDATE por cada valor viejo (tabla aprobada en SCRUM-1057).
--   3. Valida los CHECK de 003 que quedaron NOT VALID.
--   4. Aborta si queda algún valor viejo.
--
-- Fuera de alcance, a propósito:
--   * categoria_servicio.flujo_operativo NULL se deja NULL (el CHECK lo
--     permite; asignarle un flujo sería inventar el dato).
--   * auth.users.raw_app_meta_data no se toca: es el esquema de GoTrue y el
--     hook sobrescribe esos claims al emitir el token.
--   * La PoC CFG-09 (supabase/poc-cfg09) usa su propio dominio en inglés
--     (`pending`/`assigned`) en su RPC y su reset; no se modifica.
--
-- Idempotente: cada UPDATE filtra por el valor viejo, así que la segunda
-- corrida no cambia nada.
-- =====================================================================

BEGIN;

-- 0. Tabla de control (por si el entorno no corrió 001) ----------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1a. CFG-12: el hook emite el rol en minúscula ----------------------------------
-- Mismo cuerpo que supabase/poc-cfg12/10_hook_claims_tenant.sql salvo el
-- lower(). CREATE OR REPLACE conserva los GRANT/REVOKE existentes.
DO $compat$
BEGIN
    IF to_regprocedure('public.custom_access_token_hook(jsonb)') IS NOT NULL THEN
        EXECUTE $hook$
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $fn$
DECLARE
  v_claims   jsonb;
  v_tenant   uuid;
  v_rol      text;
BEGIN
  SELECT u.tenant_id, lower(u.rol)
    INTO v_tenant, v_rol
    FROM public.usuario u
   WHERE u.id = (event ->> 'user_id')::uuid
   LIMIT 1;

  v_claims := coalesce(event -> 'claims', '{}'::jsonb);

  IF v_claims -> 'app_metadata' IS NULL THEN
    v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb);
  END IF;

  -- El coalesce es el fail closed: sin él, un usuario sin fila devuelve
  -- NULL entero en vez de claims presentes y nulos (ver CFG-12, V4).
  v_claims := jsonb_set(v_claims, '{app_metadata,tenant_id}',
                        coalesce(to_jsonb(v_tenant::text), 'null'::jsonb));
  v_claims := jsonb_set(v_claims, '{app_metadata,user_role}',
                        coalesce(to_jsonb(v_rol), 'null'::jsonb));
  v_claims := jsonb_set(v_claims, '{app_metadata,rol}',
                        coalesce(to_jsonb(v_rol), 'null'::jsonb));

  RETURN jsonb_set(event, '{claims}', v_claims);
END;
$fn$
$hook$;
    END IF;
END $compat$;

-- 1b. CFG-13: kyc_isolation compara el rol sin depender de mayúsculas ----------
DO $compat$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname = 'storage' AND tablename = 'objects'
                 AND policyname = 'kyc_isolation') THEN
        EXECUTE 'DROP POLICY kyc_isolation ON storage.objects';
        EXECUTE $pol$
CREATE POLICY kyc_isolation ON storage.objects
  TO authenticated
  USING (
    bucket_id = 'kyc-documentos'
    AND (storage.foldername(name))[1] = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')
    AND (
      (storage.foldername(name))[2] = auth.uid()::text
      OR lower(auth.jwt() -> 'app_metadata' ->> 'user_role') = 'admin_tenant'
    )
  )
$pol$;
    END IF;
END $compat$;

-- 2. Valores viejos -> valores del código -------------------------------------
-- usuario
UPDATE usuario SET rol = 'ADMIN_TENANT' WHERE rol = 'admin_tenant';
UPDATE usuario SET rol = 'ALIADO'       WHERE rol = 'aliado';
UPDATE usuario SET rol = 'CLIENTE'      WHERE rol = 'cliente';
UPDATE usuario SET estado = 'ACTIVO'    WHERE estado = 'activo';

-- tenant
UPDATE tenant SET estado = 'ACTIVO' WHERE estado = 'activo';

-- aliado
UPDATE aliado SET estado_verificacion = 'VERIFICADO' WHERE estado_verificacion = 'aprobado';
UPDATE aliado SET tipo = 'PERSONA_NATURAL'  WHERE tipo = 'persona_natural';
UPDATE aliado SET tipo = 'PERSONA_JURIDICA' WHERE tipo = 'empresa';

-- cliente
UPDATE cliente SET tipo = 'PERSONA_NATURAL'  WHERE tipo = 'persona_natural';
UPDATE cliente SET tipo = 'PERSONA_JURIDICA' WHERE tipo = 'empresa';

-- categoria_servicio
UPDATE categoria_servicio SET estado = 'ACTIVO' WHERE estado = 'activa';

-- documento_kyc (002 escribe VERIFICADO/RECHAZADO al resolver la verificación)
UPDATE documento_kyc SET estado = 'VERIFICADO'               WHERE estado = 'aprobado';
UPDATE documento_kyc SET tipo_documento = 'CEDULA_CIUDADANIA' WHERE tipo_documento = 'cedula';

-- solicitud
UPDATE solicitud SET estado = 'ASIGNADA' WHERE estado = 'assigned';

-- zona
UPDATE zona SET estado = 'ACTIVO'    WHERE estado = 'activa';
UPDATE zona SET nivel  = 'CIUDAD'    WHERE nivel = 'ciudad';
UPDATE zona SET nivel  = 'LOCALIDAD' WHERE nivel = 'localidad';

-- 3. Validar los CHECK que 003 dejó NOT VALID ---------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_categoria_estado' AND NOT convalidated) THEN
        ALTER TABLE categoria_servicio VALIDATE CONSTRAINT ck_categoria_estado;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_categoria_flujo' AND NOT convalidated) THEN
        ALTER TABLE categoria_servicio VALIDATE CONSTRAINT ck_categoria_flujo;
    END IF;
END $$;

-- 4. Ningún valor viejo debe sobrevivir ---------------------------------------
DO $$
DECLARE
    v_restantes BIGINT;
BEGIN
    SELECT
        (SELECT count(*) FROM usuario WHERE rol IN ('admin_tenant', 'aliado', 'cliente') OR estado = 'activo')
      + (SELECT count(*) FROM tenant WHERE estado = 'activo')
      + (SELECT count(*) FROM aliado WHERE estado_verificacion = 'aprobado' OR tipo IN ('persona_natural', 'empresa'))
      + (SELECT count(*) FROM cliente WHERE tipo IN ('persona_natural', 'empresa'))
      + (SELECT count(*) FROM categoria_servicio WHERE estado = 'activa')
      + (SELECT count(*) FROM documento_kyc WHERE estado = 'aprobado' OR tipo_documento = 'cedula')
      + (SELECT count(*) FROM solicitud WHERE estado = 'assigned')
      + (SELECT count(*) FROM zona WHERE estado = 'activa' OR nivel IN ('ciudad', 'localidad'))
    INTO v_restantes;

    IF v_restantes > 0 THEN
        RAISE EXCEPTION '007: quedan % valores de dominio sin normalizar', v_restantes;
    END IF;
END $$;

-- 5. Registro de la migración -------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('007', 'SCRUM-1057 normaliza dominios a MAYUSCULA; hook CFG-12 emite lower(rol); kyc_isolation insensible a mayusculas')
ON CONFLICT (version) DO NOTHING;

COMMIT;
