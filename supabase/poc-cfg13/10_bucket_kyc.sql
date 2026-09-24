-- =====================================================================
-- MANI — Bucket privado de KYC y politica kyc_isolation (ADR-0013)
-- =====================================================================
-- Ticket: SCRUM-930 (CFG-13) · Subtarea: SCRUM-977
-- Resuelve en QA: SCRUM-1053 (ADR-0013 sin implementar)
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: hook de CFG-12 (supabase/poc-cfg12/10_hook_claims_tenant.sql)
--   aplicado y registrado.
--
-- ESTE ARCHIVO CAMBIA ESQUEMA. Es transaccional e idempotente.
--
-- QUE HACE
--   1. Crea el bucket `kyc-documentos`: privado, 10 MB por archivo,
--      solo PDF/JPEG/PNG (documentos escaneados o fotografiados).
--   2. Crea la politica `kyc_isolation` sobre storage.objects, copiada
--      del DDL (Product/DDL_MANI.sql en Trama-AS/MANI-docs) con un solo
--      cambio: `TO authenticated`. Sin ese TO la politica aplica al rol
--      `public`; el resultado seria el mismo (anon no tiene tenant en el
--      JWT y el predicado da NULL), pero declararlo deja explicito que
--      Storage de KYC nunca es anonimo.
--
-- LO QUE LA POLITICA HACE, Y LO QUE NO
--   * Sin clausula FOR es FOR ALL: SELECT, INSERT, UPDATE y DELETE. Como
--     no trae WITH CHECK, Postgres usa el USING tambien como WITH CHECK,
--     asi que la subida queda sujeta al mismo predicado que la lectura.
--   * El segundo segmento de la ruta se compara con auth.uid(), es decir
--     usuario.id. ADR-0013 lo llama `aliado_id`, pero aliado.id es otra
--     columna con otro valor (50000000-... vs 30000000-... en QA). La PoC
--     adopta auth.uid() (decision del 2026-09-22) y deja la discrepancia
--     como hallazgo para corregir el texto del ADR.
--   * admin_tenant puede leer Y escribir/borrar cualquier carpeta de su
--     tenant, porque es FOR ALL. Se documenta; no se cambia en la PoC.
--   * NO controla las URLs firmadas ya emitidas. La descarga por
--     /object/sign/... valida el token de la URL, no RLS. La politica
--     decide quien puede EMITIR la URL; quien la tenga despues, la usa
--     hasta que expire. Es el hallazgo 1 del plan.
--
-- CONTROL NEGATIVO
--   Quitar la politica NO sirve de control: storage.objects tiene RLS, y
--   sin politicas se deniega TODO. Los negativos seguirian en verde y lo
--   que caeria serian los positivos. Es la trampa que SCRUM-1039 encontro
--   en las tablas de public.
--
--   El control correcto es el bloque del final: reemplazar kyc_isolation
--   por una politica que solo mira el bucket, sin tenant ni usuario. Con
--   ella los positivos siguen en verde y los negativos de acceso cruzado
--   tienen que ponerse en ROJO. Restaurar corriendo este archivo de nuevo.
-- =====================================================================

BEGIN;

DO $guardas$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'No existe el esquema storage. ¿Es un Postgres sin Supabase Storage?';
  END IF;

  -- Otro bucket con nombre parecido indicaria que alguien aprovisiono
  -- KYC por fuera de este script. Mejor parar que duplicar.
  IF EXISTS (SELECT 1 FROM storage.buckets
              WHERE id <> 'kyc-documentos' AND id ILIKE '%kyc%') THEN
    RAISE EXCEPTION 'Ya existe otro bucket de KYC: revisalo antes de seguir.';
  END IF;
END $guardas$;

-- 1. Bucket --------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('kyc-documentos', 'kyc-documentos', false, 10485760,
        ARRAY['application/pdf', 'image/jpeg', 'image/png'])
ON CONFLICT (id) DO UPDATE
   SET public             = false,
       file_size_limit    = EXCLUDED.file_size_limit,
       allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Politica ------------------------------------------------------------
DROP POLICY IF EXISTS kyc_isolation ON storage.objects;

CREATE POLICY kyc_isolation ON storage.objects
  TO authenticated
  USING (
    bucket_id = 'kyc-documentos'
    AND (storage.foldername(name))[1] = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')
    AND (
      (storage.foldername(name))[2] = auth.uid()::text
      -- lower(): no depende de como venga escrito el rol (SCRUM-1057).
      OR lower(auth.jwt() -> 'app_metadata' ->> 'user_role') = 'admin_tenant'
    )
  );

COMMIT;

-- ---------------------------------------------------------------------
-- VERIFICACION — esperado: 1 bucket privado, 1 politica cmd=ALL
-- ---------------------------------------------------------------------
-- SELECT id, public, file_size_limit, allowed_mime_types
--   FROM storage.buckets WHERE id = 'kyc-documentos';
-- SELECT policyname, cmd, roles, qual, with_check
--   FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects';

-- ---------------------------------------------------------------------
-- CONTROL NEGATIVO — politica sin aislamiento (restaurar corriendo el archivo)
-- ---------------------------------------------------------------------
-- BEGIN;
-- DROP POLICY IF EXISTS kyc_isolation ON storage.objects;
-- CREATE POLICY kyc_isolation ON storage.objects
--   TO authenticated
--   USING (bucket_id = 'kyc-documentos');
-- COMMIT;

-- ---------------------------------------------------------------------
-- ROLLBACK COMPLETO — solo si se quiere dejar QA como estaba
-- ---------------------------------------------------------------------
-- Borrar los objetos de storage.objects por SQL deja huerfanos los
-- archivos en el backend de Storage: vaciar el bucket desde el dashboard
-- (o la API) primero, y despues:
-- DROP POLICY IF EXISTS kyc_isolation ON storage.objects;
-- DELETE FROM storage.buckets WHERE id = 'kyc-documentos';
