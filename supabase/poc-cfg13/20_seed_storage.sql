-- =====================================================================
-- MANI — Alinear documento_kyc.ruta_storage con ADR-0013 (CFG-13)
-- =====================================================================
-- Ticket: SCRUM-930 (CFG-13) · Subtarea: SCRUM-978
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: supabase/poc-cfg12/20_seed_identidad.sql (siembra las dos
--   filas) y de 10_bucket_kyc.sql.
--
-- ESTE ARCHIVO ESCRIBE DATOS. Transaccional e idempotente.
--
-- POR QUE
--   CFG-12 sembro un documento_kyc por tenant con
--   `ruta_storage = 'kyc/<tenant>/cedula-tN.pdf'`, cuando todavia no habia
--   bucket (lo dice su propio comentario: apuntaba a un objeto que no
--   existia, a proposito). Ese formato no cumple la politica:
--     * `kyc/` ocupa el primer segmento, donde kyc_isolation espera el
--       tenant_id: ningun usuario lo puede leer, ni el dueño.
--     * Falta el segundo segmento, el del usuario.
--   Aqui se reescribe a `<tenant_id>/<usuario_id del aliado>/cedula.pdf`.
--   El segundo segmento es usuario_id (= auth.uid()), no aliado.id: es
--   lo que la politica compara (decision del 2026-09-22, hallazgo 2).
--
--   `ruta_storage` es relativa al bucket: el bucket no forma parte de la
--   ruta, igual que en storage.objects.name.
--
-- QUE NO HACE
--   No sube los archivos. Un objeto de Storage tiene que entrar por la API
--   (qa/storage/cargar_kyc.mjs), con el JWT del aliado, para que la
--   politica se ejercite en la subida. Insertar en storage.objects por
--   SQL crearia metadatos sin archivo y saltaria RLS.
--
-- ORDEN
--   Si se vuelve a correr el seed de CFG-12, este archivo hay que
--   correrlo despues: aquel reinserta las rutas viejas.
-- =====================================================================

BEGIN;

DO $seed$
DECLARE
  v_n int;
BEGIN
  UPDATE public.documento_kyc d
     SET ruta_storage = d.tenant_id::text || '/' || al.usuario_id::text || '/cedula.pdf'
    FROM public.aliado al
   WHERE al.id = d.aliado_id
     AND d.id IN ('a0000000-0000-4000-8000-c00000000011',
                  'a0000000-0000-4000-8000-c00000000021');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n <> 2 THEN
    RAISE EXCEPTION
      'Se esperaban 2 documento_kyc de CFG-12 y se actualizaron %. ¿Se corrio 20_seed_identidad.sql?', v_n;
  END IF;

  RAISE NOTICE 'ruta_storage alineada con ADR-0013 en % documentos.', v_n;
END $seed$;

COMMIT;

-- VERIFICACION — esperado: 2 filas, `<tenant>/<30000000-...-0000000000T3>/cedula.pdf`
-- SELECT d.id, d.tenant_id, al.usuario_id, d.ruta_storage
--   FROM public.documento_kyc d JOIN public.aliado al ON al.id = d.aliado_id
--  ORDER BY d.tenant_id;
