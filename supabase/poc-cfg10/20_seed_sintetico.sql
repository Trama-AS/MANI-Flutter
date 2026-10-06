-- =====================================================================
-- MANI — Volumen sintetico para la PoC de cobertura geografica (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-965
-- Ambiente: SOLO QA · Requiere 10_esquema.sql
--
-- VOLUMEN Y CRITERIO
--   No hay volumen confirmado por el cliente (SAD KI-09; QS-08 lo marca
--   "pendiente validar con volumen real"). Por eso no se fija un numero
--   sino tres niveles, para ver como escala cada variante:
--
--     sembrar(1000) · sembrar(10000) · sembrar(100000)
--
--   N es el numero de aliados del tenant grande. Hay tres tenants, los de
--   QA, para que los JWT reales pasen RLS:
--     grande  PoC Concurrencia CFG-09  ...900000000001  N aliados   ciudades 1-5
--     chico   ACME Servicios          ...000000000011  N/10        ciudad 1
--     chico   Nova Mantenimiento      ...000000000021  N/10        ciudades 2-3
--   Los chicos comparten ciudad con el grande a proposito: mide si el
--   volumen de un tenant vecino le cuesta al otro, que es lo que RLS con
--   indice solo por tenant_id deberia evitar.
--
--   Catalogo (fijo, no depende de N): 5 ciudades, 100 localidades (5 x 4
--   por ciudad, ~5.5 km), 1000 barrios sin geometria (10 por localidad;
--   existen en el catalogo pero ADR-0011 §2.2 no los usa para cobertura).
--   Por tenant, 15 categorias activas.
--   Por aliado: 1 a 5 localidades de una misma ciudad, 1 a 3 categorias,
--   80 % aprobado, 10 % pendiente, 10 % rechazado.
--
--   Con N = 10000: 12.000 aliados, ~36.000 coberturas, ~24.000 filas
--   aliado_categoria. Una localidad del tenant grande queda con ~300
--   aliados y la consulta devuelve ~32 por categoria (medido).
--
-- REPRODUCIBILIDAD
--   setseed fijo antes de generar aliados y otro antes de generar las
--   entradas. Las entradas (1050 puntos por tenant) son identicas en los
--   tres niveles: mismo punto y misma categoria (por posicion) en cada
--   corrida. La geometria no usa random(): sale de un hash de (ciudad, i, j).
--
-- COMO USARLO
--   SET statement_timeout = '15min';
--   SELECT poc_cfg10.sembrar(10000);
--   SELECT poc_cfg10.verificar_seed();
-- =====================================================================

CREATE OR REPLACE FUNCTION poc_cfg10.tenant_grande() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '10000000-0000-4000-8000-900000000001'::uuid $$;

CREATE OR REPLACE FUNCTION poc_cfg10.tenant_acme() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '10000000-0000-4000-8000-000000000011'::uuid $$;

CREATE OR REPLACE FUNCTION poc_cfg10.tenant_nova() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '10000000-0000-4000-8000-000000000021'::uuid $$;

CREATE OR REPLACE FUNCTION poc_cfg10.sembrar(p_n int) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  dlon constant double precision := 360.0 / 32768;  -- celda geohash 6: 15 bits de lon
  dlat constant double precision := 180.0 / 32768;  --                  15 bits de lat
  t0   timestamptz := clock_timestamp();
BEGIN
  -- Por si se siembra dos veces en la misma transaccion del SQL Editor.
  DROP TABLE IF EXISTS _tenant, _ciudad, _loc, _cat, _a;

  TRUNCATE poc_cfg10.aliado_categoria, poc_cfg10.cobertura_aliado, poc_cfg10.categoria_servicio,
           poc_cfg10.aliado, poc_cfg10.zona_geohash, poc_cfg10.zona, poc_cfg10.entrada;

  -- Los indices propuestos se crean en la medicion; al resembrar se parte
  -- siempre del estado del DDL.
  DROP INDEX IF EXISTS poc_cfg10.idx_poc_cobertura_tenant_zona;
  DROP INDEX IF EXISTS poc_cfg10.idx_poc_aliado_categoria_tenant_categoria;

  -- Tenants y sus ciudades ------------------------------------------------
  CREATE TEMP TABLE _tenant ON COMMIT DROP AS
  SELECT * FROM (VALUES
    (poc_cfg10.tenant_grande(), ARRAY[1, 2, 3, 4, 5], p_n),
    (poc_cfg10.tenant_acme(),   ARRAY[1],             greatest(p_n / 10, 1)),
    (poc_cfg10.tenant_nova(),   ARRAY[2, 3],          greatest(p_n / 10, 1))
  ) AS t(tenant_id, ciudades, n_aliados);

  -- Catalogo de zonas -----------------------------------------------------
  CREATE TEMP TABLE _ciudad ON COMMIT DROP AS
  SELECT c, gen_random_uuid() AS id FROM generate_series(1, 5) AS c;

  CREATE TEMP TABLE _loc ON COMMIT DROP AS
  SELECT c, i, j, i * 4 + j AS idx, gen_random_uuid() AS id,
         (poc_cfg10.celda_anillo(c, i, j)).*
  FROM generate_series(1, 5) AS c, generate_series(0, 4) AS i, generate_series(0, 3) AS j;

  INSERT INTO poc_cfg10.zona (id, nivel, nombre, zona_padre_id, estado)
  SELECT id, 'ciudad', format('Ciudad %s', c), NULL, 'activa' FROM _ciudad;

  INSERT INTO poc_cfg10.zona (id, nivel, nombre, zona_padre_id, estado, geom,
                              min_lat, max_lat, min_lon, max_lon, anillo_lon, anillo_lat)
  SELECT l.id, 'localidad', format('Ciudad %s / Localidad %s', l.c, lpad(l.idx::text, 2, '0')),
         ci.id, 'activa', poc_cfg10.anillo_a_poligono(l.xs, l.ys),
         (SELECT min(v) FROM unnest(l.ys) v), (SELECT max(v) FROM unnest(l.ys) v),
         (SELECT min(v) FROM unnest(l.xs) v), (SELECT max(v) FROM unnest(l.xs) v),
         l.xs, l.ys
  FROM _loc l JOIN _ciudad ci USING (c);

  INSERT INTO poc_cfg10.zona (nivel, nombre, zona_padre_id, estado)
  SELECT 'barrio', format('Ciudad %s / Localidad %s / Barrio %s', l.c, lpad(l.idx::text, 2, '0'), b),
         l.id, 'activa'
  FROM _loc l, generate_series(1, 10) AS b;

  -- Geohash: cada celda de precision 6 que toca una ciudad se asigna a la
  -- localidad que contiene su centro (o la mas cercana, para las celdas del
  -- borde cuyo centro cae fuera de la ciudad).
  INSERT INTO poc_cfg10.zona_geohash (geohash, zona_id)
  SELECT poc_cfg10.geohash_encode(cel.lat, cel.lon, 6),
         (SELECT z.id FROM poc_cfg10.zona z
          WHERE z.nivel = 'localidad'
          ORDER BY z.geom OPERATOR(extensions.<->)
                   extensions.st_setsrid(extensions.st_makepoint(cel.lon, cel.lat), 4326)
          LIMIT 1)
  FROM (
    SELECT DISTINCT -180 + (xi + 0.5) * dlon AS lon, -90 + (yi + 0.5) * dlat AS lat
    FROM generate_series(1, 5) AS c,
         generate_series(floor((poc_cfg10.lon0(c) + 180) / dlon)::int,
                         floor((poc_cfg10.lon0(c) + 5 * poc_cfg10.lado() + 180) / dlon)::int) AS xi,
         generate_series(floor((poc_cfg10.lat0(c) + 90) / dlat)::int,
                         floor((poc_cfg10.lat0(c) + 4 * poc_cfg10.lado() + 90) / dlat)::int) AS yi
  ) AS cel;

  -- Categorias ------------------------------------------------------------
  CREATE TEMP TABLE _cat ON COMMIT DROP AS
  SELECT t.tenant_id, k AS idx, gen_random_uuid() AS id
  FROM _tenant t, generate_series(0, 14) AS k;

  INSERT INTO poc_cfg10.categoria_servicio (id, tenant_id, nombre, estado)
  SELECT id, tenant_id, format('Categoria %s', lpad(idx::text, 2, '0')), 'activa' FROM _cat;

  -- Aliados ---------------------------------------------------------------
  PERFORM setseed(0.927);

  CREATE TEMP TABLE _a ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, x.tenant_id, x.k,
         x.ciudades[1 + floor(random() * array_length(x.ciudades, 1))::int] AS c,
         floor(random() * 20)::int      AS loc_base,
         1 + floor(random() * 5)::int   AS n_zonas,
         floor(random() * 15)::int      AS cat_base,
         1 + floor(random() * 3)::int   AS n_cat,
         random()                       AS r_estado
  FROM (SELECT t.tenant_id, t.ciudades, k
        FROM _tenant t, generate_series(1, t.n_aliados) AS k
        ORDER BY t.tenant_id, k) AS x;

  INSERT INTO poc_cfg10.aliado (id, tenant_id, nombre_razon_social, estado_verificacion)
  SELECT id, tenant_id, format('Aliado sintetico %s', k),
         CASE WHEN r_estado < 0.8 THEN 'aprobado'
              WHEN r_estado < 0.9 THEN 'pendiente'
              ELSE 'rechazado' END
  FROM _a;

  -- Localidades distintas: paso 7 sobre 20 (coprimos) con n_zonas <= 5.
  INSERT INTO poc_cfg10.cobertura_aliado (tenant_id, aliado_id, zona_id)
  SELECT a.tenant_id, a.id, l.id
  FROM _a a, generate_series(0, a.n_zonas - 1) AS s, _loc l
  WHERE l.c = a.c AND l.idx = (a.loc_base + 7 * s) % 20;

  -- Categorias distintas: paso 4 sobre 15 (coprimos) con n_cat <= 3.
  INSERT INTO poc_cfg10.aliado_categoria (tenant_id, aliado_id, categoria_id)
  SELECT a.tenant_id, a.id, ct.id
  FROM _a a, generate_series(0, a.n_cat - 1) AS s, _cat ct
  WHERE ct.tenant_id = a.tenant_id AND ct.idx = (a.cat_base + 4 * s) % 15;

  -- Entradas de la medicion -------------------------------------------------
  PERFORM setseed(0.1927);

  INSERT INTO poc_cfg10.entrada (tenant_id, n, lat, lon, categoria_id, zona_real)
  SELECT e.tenant_id, e.n, e.lat, e.lon, ct.id,
         (SELECT z.id FROM poc_cfg10.zona z
          WHERE z.nivel = 'localidad'
            AND extensions.st_contains(z.geom, extensions.st_setsrid(extensions.st_makepoint(e.lon, e.lat), 4326))
          LIMIT 1)
  FROM (
    SELECT p.tenant_id, p.n, p.cat_idx,
           poc_cfg10.lat0(p.c) + p.ry * 4 * poc_cfg10.lado() AS lat,
           poc_cfg10.lon0(p.c) + p.rx * 5 * poc_cfg10.lado() AS lon
    FROM (
      SELECT x.tenant_id, x.n,
             x.ciudades[1 + floor(random() * array_length(x.ciudades, 1))::int] AS c,
             random() AS rx, random() AS ry, floor(random() * 15)::int AS cat_idx
      FROM (SELECT t.tenant_id, t.ciudades, n
            FROM _tenant t, generate_series(1, 1050) AS n
            ORDER BY t.tenant_id, n) AS x
    ) AS p
  ) AS e
  JOIN _cat ct ON ct.tenant_id = e.tenant_id AND ct.idx = e.cat_idx;

  ANALYZE poc_cfg10.aliado, poc_cfg10.zona, poc_cfg10.zona_geohash, poc_cfg10.cobertura_aliado,
          poc_cfg10.categoria_servicio, poc_cfg10.aliado_categoria, poc_cfg10.entrada;

  RETURN jsonb_build_object(
    'volumen', p_n,
    'segundos', round(extract(epoch FROM clock_timestamp() - t0)::numeric, 1),
    'aliados', (SELECT count(*) FROM poc_cfg10.aliado),
    'coberturas', (SELECT count(*) FROM poc_cfg10.cobertura_aliado),
    'aliado_categoria', (SELECT count(*) FROM poc_cfg10.aliado_categoria),
    'zonas', (SELECT count(*) FROM poc_cfg10.zona),
    'celdas_geohash', (SELECT count(*) FROM poc_cfg10.zona_geohash),
    'entradas', (SELECT count(*) FROM poc_cfg10.entrada)
  );
END
$$;

-- Comprobaciones del seed. Todas las claves "ok_*" deben salir true.
CREATE OR REPLACE FUNCTION poc_cfg10.verificar_seed() RETURNS jsonb
LANGUAGE sql AS $$
  WITH loc AS (SELECT * FROM poc_cfg10.zona WHERE nivel = 'localidad'),
  area_ciudad AS (
    SELECT z.zona_padre_id, sum(extensions.st_area(z.geom)) AS area
    FROM loc z GROUP BY z.zona_padre_id
  ),
  solapes AS (
    SELECT count(*) AS n FROM loc a JOIN loc b ON a.id < b.id
    WHERE extensions.st_overlaps(a.geom, b.geom)
  ),
  gh AS (
    SELECT count(*) FILTER (WHERE poc_cfg10.geohash_encode(e.lat, e.lon, 6)
                                  <> extensions.st_geohash(extensions.st_setsrid(extensions.st_makepoint(e.lon, e.lat), 4326), 6))
           AS distintos
    FROM poc_cfg10.entrada e
  ),
  pip AS (
    SELECT count(*) FILTER (WHERE NOT poc_cfg10.punto_en_poligono(e.lat, e.lon, z.anillo_lon, z.anillo_lat))
           AS fallos
    FROM poc_cfg10.entrada e JOIN poc_cfg10.zona z ON z.id = e.zona_real
  )
  SELECT jsonb_build_object(
    'ok_localidades_100',      (SELECT count(*) FROM loc) = 100,
    'ok_geometrias_validas',   (SELECT bool_and(extensions.st_isvalid(geom)) FROM loc),
    'ok_sin_solapes',          (SELECT n FROM solapes) = 0,
    'ok_teselan_ciudad',       (SELECT bool_and(abs(area - 5 * 4 * poc_cfg10.lado() ^ 2) < 1e-9) FROM area_ciudad),
    'ok_entradas_con_zona',    (SELECT count(*) FROM poc_cfg10.entrada WHERE zona_real IS NULL) = 0,
    'ok_geohash_igual_postgis',(SELECT distintos FROM gh) = 0,
    'ok_ray_casting_igual_postgis', (SELECT fallos FROM pip) = 0,
    'aliados_por_tenant', (SELECT jsonb_object_agg(t.nombre, x.n)
                           FROM (SELECT tenant_id, count(*) AS n FROM poc_cfg10.aliado GROUP BY tenant_id) x
                           JOIN public.tenant t ON t.id = x.tenant_id),
    'coberturas_por_aliado', (SELECT round(avg(n), 2) FROM (SELECT count(*) AS n FROM poc_cfg10.cobertura_aliado GROUP BY aliado_id) x),
    'categorias_por_aliado', (SELECT round(avg(n), 2) FROM (SELECT count(*) AS n FROM poc_cfg10.aliado_categoria GROUP BY aliado_id) x),
    'aprobados_pct', (SELECT round(100.0 * count(*) FILTER (WHERE estado_verificacion = 'aprobado') / count(*), 1) FROM poc_cfg10.aliado),
    'aliados_por_localidad_tenant_grande', (
      SELECT jsonb_build_object('min', min(n), 'media', round(avg(n), 1), 'max', max(n))
      FROM (SELECT zona_id, count(*) AS n FROM poc_cfg10.cobertura_aliado
            WHERE tenant_id = poc_cfg10.tenant_grande() GROUP BY zona_id) x),
    'tamano_esquema', (SELECT pg_size_pretty(sum(pg_total_relation_size(c.oid)))
                       FROM pg_class c WHERE c.relnamespace = 'poc_cfg10'::regnamespace AND c.relkind = 'r'),
    'tamano_db', pg_size_pretty(pg_database_size(current_database()))
  )
$$;
