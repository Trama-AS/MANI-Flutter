-- =====================================================================
-- MANI — Medicion de latencia p95 en base de datos (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-969
-- Ambiente: SOLO QA · Requiere 10, 20 y 30
--
-- METODO (igual para las cuatro variantes)
--   - Mismas entradas: poc_cfg10.entrada, 1050 por tenant, generadas con
--     semilla fija. Las primeras 50 son calentamiento y no se cuentan; se
--     miden las 1000 siguientes, en el mismo orden para todas.
--   - Se mide dentro de Postgres con clock_timestamp() alrededor de cada
--     llamada: tiempo de ejecucion de la consulta, sin red ni PostgREST.
--     El extremo a extremo lo mide k6 (qa/k6/latencia_cobertura.js).
--   - Se ejecuta como "authenticated" con el tenant en
--     request.jwt.claims, asi RLS aplica igual que con un JWT real.
--   - Cache caliente: las tablas caben en shared_buffers. Es el escenario
--     de hora pico de QS-08, no el de arranque en frio.
--
-- UMBRAL (fijado antes de ejecutar y publicado en SCRUM-927)
--   En base de datos, variante zona (ADR-0011): p95 < 50 ms  <- decide
--   Las demas variantes se reportan contra el mismo umbral.
--
-- COMO USARLO
--   Un nivel de volumen por ejecucion, para no chocar con el timeout del
--   SQL Editor:
--     SET statement_timeout = '15min';
--     SELECT poc_cfg10.sembrar(10000);
--     SELECT poc_cfg10.correr_nivel('10k');
--     SELECT * FROM poc_cfg10.resumen;
-- =====================================================================

-- Indices propuestos para la consulta de despacho. El DDL solo tiene indice
-- por tenant_id en cobertura_aliado; buscar por zona obliga a recorrer toda
-- la cobertura del tenant. Estos permiten ir directo a (tenant, zona).
CREATE OR REPLACE FUNCTION poc_cfg10.indices_propuestos(p_activar boolean) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  IF p_activar THEN
    CREATE INDEX IF NOT EXISTS idx_poc_cobertura_tenant_zona
      ON poc_cfg10.cobertura_aliado (tenant_id, zona_id) INCLUDE (aliado_id);
    CREATE INDEX IF NOT EXISTS idx_poc_aliado_categoria_tenant_categoria
      ON poc_cfg10.aliado_categoria (tenant_id, categoria_id) INCLUDE (aliado_id);
    ANALYZE poc_cfg10.cobertura_aliado, poc_cfg10.aliado_categoria;
    RETURN 'indices propuestos: creados';
  ELSE
    DROP INDEX IF EXISTS poc_cfg10.idx_poc_cobertura_tenant_zona;
    DROP INDEX IF EXISTS poc_cfg10.idx_poc_aliado_categoria_tenant_categoria;
    ANALYZE poc_cfg10.cobertura_aliado, poc_cfg10.aliado_categoria;
    RETURN 'indices propuestos: eliminados';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION poc_cfg10.medir(
  p_variante      text,
  p_tenant        uuid,
  p_corrida       text,
  p_n             int DEFAULT 1000,
  p_calentamiento int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  lats     double precision[];
  lons     double precision[];
  cats     uuid[];
  zonas    uuid[];
  tiempos  double precision[] := '{}';
  filas    int[] := '{}';
  t0       timestamptz;
  f        int;
  k        int;
  total    int;
  volumen  int;
  con_idx  boolean;
  res      jsonb;
BEGIN
  IF p_variante NOT IN ('zona', 'postgis', 'bbox', 'geohash') THEN
    RAISE EXCEPTION 'variante desconocida: %', p_variante;
  END IF;

  SELECT array_agg(lat ORDER BY n), array_agg(lon ORDER BY n),
         array_agg(categoria_id ORDER BY n), array_agg(zona_real ORDER BY n)
  INTO lats, lons, cats, zonas
  FROM poc_cfg10.entrada
  WHERE tenant_id = p_tenant AND n <= p_calentamiento + p_n;

  total := coalesce(array_length(lats, 1), 0);
  IF total < p_calentamiento + p_n THEN
    RAISE EXCEPTION 'faltan entradas para el tenant %: hay %, se piden %', p_tenant, total, p_calentamiento + p_n;
  END IF;

  SELECT count(*) INTO volumen FROM poc_cfg10.aliado WHERE tenant_id = poc_cfg10.tenant_grande();
  con_idx := EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'poc_cfg10'
                     AND indexname = 'idx_poc_cobertura_tenant_zona');

  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'authenticated',
                      'app_metadata', json_build_object('tenant_id', p_tenant))::text, true);
  SET LOCAL ROLE authenticated;

  FOR k IN 1..total LOOP
    t0 := clock_timestamp();
    IF p_variante = 'zona' THEN
      SELECT count(*) INTO f FROM poc_cfg10.aliados_validos_por_zona(zonas[k], cats[k]);
    ELSIF p_variante = 'postgis' THEN
      SELECT count(*) INTO f FROM poc_cfg10.aliados_validos_postgis(lats[k], lons[k], cats[k]);
    ELSIF p_variante = 'bbox' THEN
      SELECT count(*) INTO f FROM poc_cfg10.aliados_validos_bbox(lats[k], lons[k], cats[k]);
    ELSE
      SELECT count(*) INTO f FROM poc_cfg10.aliados_validos_geohash(lats[k], lons[k], cats[k]);
    END IF;
    IF k > p_calentamiento THEN
      tiempos := tiempos || extract(epoch FROM clock_timestamp() - t0) * 1000;
      filas := filas || f;
    END IF;
  END LOOP;

  RESET ROLE;

  INSERT INTO poc_cfg10.medicion (corrida, volumen, variante, indices_propuestos, tenant_id, n,
                                  p50_ms, p95_ms, p99_ms, media_ms, max_ms, filas_media)
  SELECT p_corrida, volumen, p_variante, con_idx, p_tenant, p_n,
         round(percentile_cont(0.50) WITHIN GROUP (ORDER BY t)::numeric, 3),
         round(percentile_cont(0.95) WITHIN GROUP (ORDER BY t)::numeric, 3),
         round(percentile_cont(0.99) WITHIN GROUP (ORDER BY t)::numeric, 3),
         round(avg(t)::numeric, 3),
         round(max(t)::numeric, 3),
         (SELECT round(avg(x), 1) FROM unnest(filas) x)
  FROM unnest(tiempos) t
  RETURNING to_jsonb(medicion.*) INTO res;

  RETURN res;
END
$$;

-- Un nivel de volumen completo: 4 variantes x {DDL, DDL + indices
-- propuestos} x {tenant grande, tenant chico vecino (ACME)}.
CREATE OR REPLACE FUNCTION poc_cfg10.correr_nivel(p_corrida text) RETURNS SETOF poc_cfg10.medicion
LANGUAGE plpgsql AS $$
DECLARE
  v_idx      boolean;
  v_tenant   uuid;
  v_variante text;
  primer_id  bigint;
BEGIN
  SELECT coalesce(max(id), 0) INTO primer_id FROM poc_cfg10.medicion;
  FOREACH v_idx IN ARRAY ARRAY[false, true] LOOP
    PERFORM poc_cfg10.indices_propuestos(v_idx);
    FOREACH v_tenant IN ARRAY ARRAY[poc_cfg10.tenant_grande(), poc_cfg10.tenant_acme()] LOOP
      FOREACH v_variante IN ARRAY ARRAY['zona', 'postgis', 'bbox', 'geohash'] LOOP
        PERFORM poc_cfg10.medir(v_variante, v_tenant, p_corrida);
      END LOOP;
    END LOOP;
  END LOOP;
  RETURN QUERY SELECT * FROM poc_cfg10.medicion WHERE id > primer_id ORDER BY id;
END
$$;

-- Plan de ejecucion de una consulta representativa, como evidencia de que
-- cada variante usa el indice que dice usar. Devuelve el texto del plan.
CREATE OR REPLACE FUNCTION poc_cfg10.explicar(p_variante text, p_tenant uuid, p_n int DEFAULT 51)
RETURNS SETOF text LANGUAGE plpgsql AS $$
DECLARE
  e    poc_cfg10.entrada;
  sql  text;
  linea text;
BEGIN
  SELECT * INTO e FROM poc_cfg10.entrada WHERE tenant_id = p_tenant AND n = p_n;

  sql := CASE p_variante
    WHEN 'zona' THEN format(
      'SELECT * FROM poc_cfg10.aliados_validos_zona(%L::uuid, %L::uuid)', e.zona_real, e.categoria_id)
    WHEN 'postgis' THEN format(
      'SELECT z.id FROM poc_cfg10.zona z WHERE z.nivel = ''localidad'' AND z.estado = ''activa''
         AND extensions.st_contains(z.geom, extensions.st_setsrid(extensions.st_makepoint(%s, %s), 4326)) LIMIT 1',
      e.lon, e.lat)
    WHEN 'bbox' THEN format(
      'SELECT z.id FROM poc_cfg10.zona z WHERE z.nivel = ''localidad'' AND z.estado = ''activa''
         AND z.min_lat <= %1$s AND z.max_lat >= %1$s AND z.min_lon <= %2$s AND z.max_lon >= %2$s
         AND poc_cfg10.punto_en_poligono(%1$s, %2$s, z.anillo_lon, z.anillo_lat) LIMIT 1',
      e.lat, e.lon)
    WHEN 'geohash' THEN format(
      'SELECT g.zona_id FROM poc_cfg10.zona_geohash g JOIN poc_cfg10.zona z ON z.id = g.zona_id
         WHERE g.geohash = %L AND z.estado = ''activa''',
      poc_cfg10.geohash_encode(e.lat, e.lon, 6))
  END;

  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'authenticated',
                      'app_metadata', json_build_object('tenant_id', p_tenant))::text, true);
  SET LOCAL ROLE authenticated;
  RETURN NEXT format('-- %s · tenant %s · entrada %s', p_variante, p_tenant, p_n);
  FOR linea IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) ' || sql LOOP
    RETURN NEXT linea;
  END LOOP;
  RESET ROLE;
END
$$;

CREATE OR REPLACE VIEW poc_cfg10.resumen AS
SELECT m.corrida, m.volumen, t.nombre AS tenant, m.variante,
       CASE WHEN m.indices_propuestos THEN 'DDL + propuestos' ELSE 'DDL' END AS indices,
       m.p50_ms, m.p95_ms, m.p99_ms, m.max_ms, m.filas_media,
       m.p95_ms < 50 AS cumple_umbral_db
FROM poc_cfg10.medicion m
JOIN public.tenant t ON t.id = m.tenant_id
ORDER BY m.volumen, m.indices_propuestos, t.nombre, m.variante;
