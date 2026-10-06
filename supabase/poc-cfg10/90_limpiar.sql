-- =====================================================================
-- MANI — Limpieza de la PoC de cobertura geografica (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10)
-- Ambiente: SOLO QA
--
-- ANTES DE CORRERLO
--   Exportar la evidencia: "SELECT * FROM poc_cfg10.resumen" y
--   "SELECT poc_cfg10.precision()" ya deben estar copiadas en
--   supabase/poc-cfg10/evidencia/. Esto borra la tabla medicion.
--
-- QUE HACE
--   Elimina las dos RPC publicas y el esquema poc_cfg10 completo. No toca
--   ninguna tabla de public ni los tenants de QA.
--
-- POSTGIS
--   La extension se habilito solo para esta PoC y ADR-0011 no la adopta.
--   Se retira al final (ultimo bloque). Si el equipo decide conservarla,
--   comentar ese bloque y dejarlo escrito en el informe.
-- =====================================================================

DROP FUNCTION IF EXISTS public.poc_cfg10_aliados_validos(text, uuid, uuid, double precision, double precision);
DROP FUNCTION IF EXISTS public.poc_cfg10_entradas();
DROP SCHEMA IF EXISTS poc_cfg10 CASCADE;

-- Retirar PostGIS (falla si otro objeto fuera de poc_cfg10 la usa, que es
-- justo lo que se quiere saber antes de quitarla).
DROP EXTENSION IF EXISTS postgis;

SELECT json_build_object(
  'esquema_poc_cfg10', EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'poc_cfg10'),
  'rpc_publicas', EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('poc_cfg10_aliados_validos', 'poc_cfg10_entradas')),
  'postgis_instalado', EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis')
) AS limpieza;
