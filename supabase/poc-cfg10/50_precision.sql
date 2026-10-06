-- =====================================================================
-- MANI — Precision de la resolucion de zona por variante (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-969
-- Ambiente: SOLO QA · Requiere 10, 20 y 30
--
-- POR QUE
--   La latencia no alcanza para comparar: bbox sin refinar y geohash son
--   aproximaciones. Si resuelven mal la zona, la consulta devuelve rapido
--   los aliados de otra localidad. Aqui se mide cuantas veces pasa.
--
-- REFERENCIA
--   "entrada.zona_real", calculada con PostGIS ST_Contains al sembrar. Por
--   construccion PostGIS acierta el 100 %; se reporta igual como control.
--   Las entradas son independientes del volumen de aliados, asi que basta
--   correrlo una vez.
--
-- COMO USARLO
--   SELECT poc_cfg10.precision();
-- =====================================================================

CREATE OR REPLACE FUNCTION poc_cfg10.precision() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH r AS (
    SELECT e.zona_real,
           poc_cfg10.zona_por_postgis(e.lat, e.lon) AS z_postgis,
           poc_cfg10.zona_por_bbox(e.lat, e.lon)    AS z_bbox,
           poc_cfg10.zona_por_geohash(e.lat, e.lon) AS z_geohash,
           (SELECT count(*) FROM poc_cfg10.zona z
            WHERE z.nivel = 'localidad' AND z.estado = 'activa'
              AND z.min_lat <= e.lat AND z.max_lat >= e.lat
              AND z.min_lon <= e.lon AND z.max_lon >= e.lon) AS candidatos_bbox
    FROM poc_cfg10.entrada e
  )
  SELECT jsonb_build_object(
    'puntos', count(*),
    'acierto_pct', jsonb_build_object(
      'postgis',         round(100.0 * count(*) FILTER (WHERE z_postgis = zona_real) / count(*), 2),
      'bbox_refinado',   round(100.0 * count(*) FILTER (WHERE z_bbox    = zona_real) / count(*), 2),
      'geohash_6',       round(100.0 * count(*) FILTER (WHERE z_geohash = zona_real) / count(*), 2)
    ),
    'bbox_sin_refinar', jsonb_build_object(
      'candidatos_media', round(avg(candidatos_bbox), 2),
      'candidatos_max',   max(candidatos_bbox),
      'puntos_ambiguos_pct', round(100.0 * count(*) FILTER (WHERE candidatos_bbox > 1) / count(*), 2)
    ),
    'geohash_6_sin_zona', count(*) FILTER (WHERE z_geohash IS NULL)
  )
  FROM r
$$;
