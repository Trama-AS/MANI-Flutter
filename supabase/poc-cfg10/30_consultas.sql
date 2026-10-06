-- =====================================================================
-- MANI — Consulta "aliados validos por cobertura y categoria" (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtareas: SCRUM-966, SCRUM-967, SCRUM-968
-- Ambiente: SOLO QA · Requiere 10_esquema.sql
--
-- LAS CUATRO VARIANTES
--   zona     Linea base, ADR-0011 §2.4: el sitio ya trae su zona y el
--            match es igualdad de zona_id. Es lo que el MVP implementa.
--   postgis  Punto del sitio -> localidad con ST_Contains + GiST -> match.
--   bbox     Punto -> candidatas por bounding box (btree) -> refinado por
--            ray casting en SQL puro -> match. Sin PostGIS en consulta.
--   geohash  Punto -> geohash 6 -> zona_geohash (igualdad) -> match. Sin
--            PostGIS en consulta; aproximado en los bordes de celda.
--
--   Las tres geograficas son la evolucion aditiva de ADR-0011 §6: resuelven
--   la zona desde coordenadas y despues hacen exactamente el mismo match.
--   Asi la comparacion aisla el costo de resolver la zona.
--
-- TENANT
--   Ninguna funcion recibe tenant: lo pone RLS desde el JWT, como en
--   produccion. Todas son SECURITY INVOKER.
--
-- COMO USARLO
--   Pegar entero en el SQL Editor y ejecutar. Idempotente.
-- =====================================================================

-- Linea base (ADR-0011). SQL sin SET para que el planificador la pueda
-- inlinear dentro de la consulta que la llama.
CREATE OR REPLACE FUNCTION poc_cfg10.aliados_validos_zona(p_zona_id uuid, p_categoria_id uuid)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE sql STABLE AS $$
  SELECT a.id, a.nombre_razon_social
  FROM poc_cfg10.cobertura_aliado ca
  JOIN poc_cfg10.aliado_categoria ac ON ac.aliado_id = ca.aliado_id
  JOIN poc_cfg10.aliado a            ON a.id = ca.aliado_id
  WHERE ca.zona_id = p_zona_id
    AND ac.categoria_id = p_categoria_id
    AND a.estado_verificacion = 'aprobado'
$$;

-- Resolucion de zona -------------------------------------------------------

CREATE OR REPLACE FUNCTION poc_cfg10.zona_por_postgis(p_lat double precision, p_lon double precision)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT z.id
  FROM poc_cfg10.zona z
  WHERE z.nivel = 'localidad' AND z.estado = 'activa'
    AND extensions.st_contains(z.geom, extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326))
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.zona_por_bbox(p_lat double precision, p_lon double precision)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT z.id
  FROM poc_cfg10.zona z
  WHERE z.nivel = 'localidad' AND z.estado = 'activa'
    AND z.min_lat <= p_lat AND z.max_lat >= p_lat
    AND z.min_lon <= p_lon AND z.max_lon >= p_lon
    AND poc_cfg10.punto_en_poligono(p_lat, p_lon, z.anillo_lon, z.anillo_lat)
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.zona_por_geohash(p_lat double precision, p_lon double precision)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT g.zona_id
  FROM poc_cfg10.zona_geohash g
  JOIN poc_cfg10.zona z ON z.id = g.zona_id
  WHERE g.geohash = poc_cfg10.geohash_encode(p_lat, p_lon, 6)
    AND z.estado = 'activa'
$$;

-- Consulta completa por variante. PL/pgSQL para que la zona se resuelva una
-- sola vez y no por fila del match. Las cuatro tienen la misma forma.

CREATE OR REPLACE FUNCTION poc_cfg10.aliados_validos_por_zona(p_zona_id uuid, p_categoria_id uuid)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_zona(p_zona_id, p_categoria_id);
END
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.aliados_validos_postgis(p_lat double precision, p_lon double precision, p_categoria_id uuid)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_zona uuid := poc_cfg10.zona_por_postgis(p_lat, p_lon);
BEGIN
  RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_zona(v_zona, p_categoria_id);
END
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.aliados_validos_bbox(p_lat double precision, p_lon double precision, p_categoria_id uuid)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_zona uuid := poc_cfg10.zona_por_bbox(p_lat, p_lon);
BEGIN
  RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_zona(v_zona, p_categoria_id);
END
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.aliados_validos_geohash(p_lat double precision, p_lon double precision, p_categoria_id uuid)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_zona uuid := poc_cfg10.zona_por_geohash(p_lat, p_lon);
BEGIN
  RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_zona(v_zona, p_categoria_id);
END
$$;

-- RPC para k6 (SCRUM-969, extremo a extremo). Vive en public para que
-- PostgREST la exponga sin cambiar los esquemas expuestos del proyecto.
-- La elimina 90_limpiar.sql.
CREATE OR REPLACE FUNCTION public.poc_cfg10_aliados_validos(
  p_variante     text,
  p_categoria_id uuid,
  p_zona_id      uuid DEFAULT NULL,
  p_lat          double precision DEFAULT NULL,
  p_lon          double precision DEFAULT NULL)
RETURNS TABLE (aliado_id uuid, nombre text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  CASE p_variante
    WHEN 'zona'    THEN RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_por_zona(p_zona_id, p_categoria_id);
    WHEN 'postgis' THEN RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_postgis(p_lat, p_lon, p_categoria_id);
    WHEN 'bbox'    THEN RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_bbox(p_lat, p_lon, p_categoria_id);
    WHEN 'geohash' THEN RETURN QUERY SELECT * FROM poc_cfg10.aliados_validos_geohash(p_lat, p_lon, p_categoria_id);
    ELSE RAISE EXCEPTION 'variante desconocida: %', p_variante;
  END CASE;
END
$$;

REVOKE EXECUTE ON FUNCTION public.poc_cfg10_aliados_validos(text, uuid, uuid, double precision, double precision) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.poc_cfg10_aliados_validos(text, uuid, uuid, double precision, double precision) TO authenticated;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA poc_cfg10 TO authenticated;
