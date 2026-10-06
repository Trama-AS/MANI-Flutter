-- =====================================================================
-- MANI — Entradas para la medicion extremo a extremo con k6 (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-969
-- Ambiente: SOLO QA · Requiere 10, 20 y 30
--
-- POR QUE
--   k6 tiene que mandar los mismos puntos, zonas y categorias que midio
--   40_medir.sql. Los ids de zona y categoria cambian en cada sembrar(),
--   asi que no sirve un archivo fijo: k6 los lee en setup() con esta RPC,
--   despues de sembrar el nivel que se va a medir.
--
--   Devuelve solo las entradas del tenant del JWT (filtro explicito, la
--   tabla entrada no tiene RLS). La elimina 90_limpiar.sql.
--
-- COMO USARLO
--   Pegar entero en el SQL Editor y ejecutar. Idempotente.
-- =====================================================================

GRANT SELECT ON poc_cfg10.entrada TO authenticated;

CREATE OR REPLACE FUNCTION public.poc_cfg10_entradas()
RETURNS TABLE (n int, lat double precision, lon double precision, categoria_id uuid, zona_id uuid)
LANGUAGE sql STABLE AS $$
  SELECT e.n, e.lat, e.lon, e.categoria_id, e.zona_real
  FROM poc_cfg10.entrada e
  WHERE e.tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid
  ORDER BY e.n
$$;

REVOKE EXECUTE ON FUNCTION public.poc_cfg10_entradas() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.poc_cfg10_entradas() TO authenticated;
