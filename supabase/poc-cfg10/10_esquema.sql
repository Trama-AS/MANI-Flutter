-- =====================================================================
-- MANI — Esquema aislado para la PoC de cobertura geografica (CFG-10)
-- =====================================================================
-- Ticket: SCRUM-927 (CFG-10) · Subtarea: SCRUM-965
-- Ambiente: SOLO QA (proyecto Supabase MANI-QA)
--
-- QUE HACE
--   1. Habilita PostGIS en el esquema "extensions" (aprobado por Santiago
--      el 2026-09-22; 00_verificar_terreno.sql lo mostro disponible,
--      3.3.7, no instalado). 90_limpiar.sql decide si se retira.
--   2. Crea el esquema "poc_cfg10" con copias de las tablas de la consulta
--      de despacho (DDL_MANI.sql), para no tocar los datos de QA que usa
--      US-04.1.2. Mismas columnas relevantes, mismas restricciones UNIQUE,
--      mismos indices por tenant_id y mismas politicas RLS.
--   3. Agrega a "zona" las columnas que necesita cada alternativa. Esto es
--      la "evolucion aditiva" que ADR-0011 §6 deja prevista: asociar
--      geometria a la zona para resolver la zona de un sitio desde
--      coordenadas, sin tocar la relacion aliado <-> zona ni el match.
--        PostGIS   -> geom + indice GiST
--        Bbox      -> min/max lat/lon + btree, refinado con el anillo en
--                     arreglos y ray casting en SQL puro (sin PostGIS)
--        Geohash   -> tabla zona_geohash (celda de precision 6 -> zona)
--   4. Funciones auxiliares sin dependencia de PostGIS: hash determinista,
--      codificador geohash y punto-en-poligono.
--
-- DIFERENCIAS CONSCIENTES CON DDL_MANI.sql
--   - aliado sin usuario_id ni tipo: no participan en la consulta y
--     obligarian a crear 120k usuarios reales en auth.
--   - tenant_id referencia public.tenant: la PoC reutiliza los 3 tenants
--     de QA para que los JWT reales (k6) pasen RLS sin tocar auth.
--
-- COMO USARLO
--   Pegar entero en el SQL Editor y ejecutar. Idempotente salvo por las
--   tablas: si ya existe poc_cfg10, correr 90_limpiar.sql antes.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

CREATE SCHEMA poc_cfg10;

-- ---------------------------------------------------------------------
-- Tablas (copias de DDL_MANI.sql)
-- ---------------------------------------------------------------------

CREATE TABLE poc_cfg10.aliado (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES public.tenant(id),
    nombre_razon_social   text NOT NULL,
    estado_verificacion   text NOT NULL CHECK (estado_verificacion IN ('pendiente', 'aprobado', 'rechazado')),
    created_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_aliado_tenant_id ON poc_cfg10.aliado(tenant_id);

-- ZONA: catalogo global (ADR-0011 §2.6). Las columnas despues de "estado"
-- existen solo en la PoC: son la evolucion aditiva de ADR-0011 §6.
CREATE TABLE poc_cfg10.zona (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nivel          text NOT NULL,
    nombre         text NOT NULL,
    zona_padre_id  uuid NULL REFERENCES poc_cfg10.zona(id),
    estado         text NOT NULL CHECK (estado IN ('activa', 'desactivada')),
    geom           extensions.geometry(Polygon, 4326) NULL,
    min_lat        double precision NULL,
    max_lat        double precision NULL,
    min_lon        double precision NULL,
    max_lon        double precision NULL,
    anillo_lon     double precision[] NULL,
    anillo_lat     double precision[] NULL
);
CREATE INDEX idx_zona_geom ON poc_cfg10.zona USING gist (geom);
CREATE INDEX idx_zona_bbox ON poc_cfg10.zona (min_lat, max_lat, min_lon, max_lon)
    WHERE nivel = 'localidad' AND estado = 'activa';

-- Celda geohash de precision 6 (~1.2 km x 0.6 km) -> localidad a la que
-- pertenece su centro. Se precalcula al sembrar.
CREATE TABLE poc_cfg10.zona_geohash (
    geohash  text PRIMARY KEY,
    zona_id  uuid NOT NULL REFERENCES poc_cfg10.zona(id)
);

CREATE TABLE poc_cfg10.cobertura_aliado (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          uuid NOT NULL REFERENCES public.tenant(id),
    aliado_id          uuid NOT NULL REFERENCES poc_cfg10.aliado(id),
    zona_id            uuid NOT NULL REFERENCES poc_cfg10.zona(id),
    fecha_declaracion  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (aliado_id, zona_id)
);
CREATE INDEX idx_cobertura_aliado_tenant_id ON poc_cfg10.cobertura_aliado(tenant_id);

CREATE TABLE poc_cfg10.categoria_servicio (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        uuid NOT NULL REFERENCES public.tenant(id),
    nombre           text NOT NULL,
    estado           text NOT NULL,
    flujo_operativo  text NULL
);
CREATE INDEX idx_categoria_servicio_tenant_id ON poc_cfg10.categoria_servicio(tenant_id);

CREATE TABLE poc_cfg10.aliado_categoria (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     uuid NOT NULL REFERENCES public.tenant(id),
    aliado_id     uuid NOT NULL REFERENCES poc_cfg10.aliado(id),
    categoria_id  uuid NOT NULL REFERENCES poc_cfg10.categoria_servicio(id),
    UNIQUE (aliado_id, categoria_id)
);
CREATE INDEX idx_aliado_categoria_tenant_id ON poc_cfg10.aliado_categoria(tenant_id);

-- Entradas de la medicion: los mismos puntos y categorias para todas las
-- variantes y todos los volumenes. "zona_real" es la localidad que contiene
-- el punto segun PostGIS; la variante "zona" (ADR-0011) la recibe directo,
-- como la recibiria del sitio del cliente.
CREATE TABLE poc_cfg10.entrada (
    tenant_id     uuid NOT NULL,
    n             int NOT NULL,
    lat           double precision NOT NULL,
    lon           double precision NOT NULL,
    categoria_id  uuid NOT NULL,
    zona_real     uuid NULL,
    PRIMARY KEY (tenant_id, n)
);

CREATE TABLE poc_cfg10.medicion (
    id                  bigserial PRIMARY KEY,
    corrida             text NOT NULL,
    volumen             int NOT NULL,
    variante            text NOT NULL,
    indices_propuestos  boolean NOT NULL,
    tenant_id           uuid NOT NULL,
    n                   int NOT NULL,
    p50_ms              numeric NOT NULL,
    p95_ms              numeric NOT NULL,
    p99_ms              numeric NOT NULL,
    media_ms            numeric NOT NULL,
    max_ms              numeric NOT NULL,
    filas_media         numeric NOT NULL,
    medido_en           timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- RLS: mismas politicas que DDL_MANI.sql. Zona y zona_geohash son
-- catalogo global de solo lectura (ADR-0011 §2.6).
-- ---------------------------------------------------------------------

ALTER TABLE poc_cfg10.aliado ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_aliado ON poc_cfg10.aliado
  USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

ALTER TABLE poc_cfg10.cobertura_aliado ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_cobertura_aliado ON poc_cfg10.cobertura_aliado
  USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

ALTER TABLE poc_cfg10.categoria_servicio ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_categoria_servicio ON poc_cfg10.categoria_servicio
  USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

ALTER TABLE poc_cfg10.aliado_categoria ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_aliado_categoria ON poc_cfg10.aliado_categoria
  USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

ALTER TABLE poc_cfg10.zona ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalogo_global_lectura ON poc_cfg10.zona FOR SELECT USING (true);

ALTER TABLE poc_cfg10.zona_geohash ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalogo_global_lectura ON poc_cfg10.zona_geohash FOR SELECT USING (true);

GRANT USAGE ON SCHEMA poc_cfg10 TO authenticated;
GRANT SELECT ON poc_cfg10.aliado, poc_cfg10.zona, poc_cfg10.zona_geohash,
                poc_cfg10.cobertura_aliado, poc_cfg10.categoria_servicio,
                poc_cfg10.aliado_categoria
  TO authenticated;

-- ---------------------------------------------------------------------
-- Funciones auxiliares (sin PostGIS)
-- ---------------------------------------------------------------------

-- Numero en [0, 1) derivado de un texto. Hace la geometria reproducible sin
-- depender del orden en que Postgres llame a random().
CREATE FUNCTION poc_cfg10.hrand(p text) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (('x' || substr(md5(p), 1, 8))::bit(32)::bigint)::double precision / 4294967296.0
$$;

-- Geohash estandar (base32 de Niemeyer), implementado en PL/pgSQL para que
-- la variante geohash no dependa de PostGIS en tiempo de consulta.
-- 20_seed_sintetico.sql lo verifica contra ST_GeoHash.
CREATE FUNCTION poc_cfg10.geohash_encode(p_lat double precision, p_lon double precision, p_precision int)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  base32  constant text := '0123456789bcdefghjkmnpqrstuvwxyz';
  lat_lo  double precision := -90;
  lat_hi  double precision := 90;
  lon_lo  double precision := -180;
  lon_hi  double precision := 180;
  medio   double precision;
  es_lon  boolean := true;
  n_bits  int := 0;
  valor   int := 0;
  res     text := '';
BEGIN
  WHILE length(res) < p_precision LOOP
    IF es_lon THEN
      medio := (lon_lo + lon_hi) / 2;
      IF p_lon >= medio THEN valor := valor * 2 + 1; lon_lo := medio;
      ELSE valor := valor * 2; lon_hi := medio; END IF;
    ELSE
      medio := (lat_lo + lat_hi) / 2;
      IF p_lat >= medio THEN valor := valor * 2 + 1; lat_lo := medio;
      ELSE valor := valor * 2; lat_hi := medio; END IF;
    END IF;
    es_lon := NOT es_lon;
    n_bits := n_bits + 1;
    IF n_bits = 5 THEN
      res := res || substr(base32, valor + 1, 1);
      n_bits := 0;
      valor := 0;
    END IF;
  END LOOP;
  RETURN res;
END
$$;

-- Punto en poligono por ray casting. El anillo va sin el punto de cierre.
CREATE FUNCTION poc_cfg10.punto_en_poligono(p_lat double precision, p_lon double precision,
                                            xs double precision[], ys double precision[])
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  dentro  boolean := false;
  n       int := array_length(xs, 1);
  i       int;
  j       int;
BEGIN
  j := n;
  FOR i IN 1..n LOOP
    IF ((ys[i] > p_lat) <> (ys[j] > p_lat))
       AND (p_lon < (xs[j] - xs[i]) * (p_lat - ys[i]) / (ys[j] - ys[i]) + xs[i]) THEN
      dentro := NOT dentro;
    END IF;
    j := i;
  END LOOP;
  RETURN dentro;
END
$$;

-- ---------------------------------------------------------------------
-- Geografia sintetica
-- ---------------------------------------------------------------------
-- 5 ciudades separadas. Cada una es una cuadricula de 5 x 4 localidades de
-- 0.05 grados (~5.5 km) de lado. Los vertices interiores y los puntos
-- medios de las aristas interiores se desplazan hasta 0.2 celdas, asi que
-- las localidades son octogonos irregulares que teselan la ciudad sin
-- huecos ni solapes. Con rectangulos el bounding box seria exacto y la
-- comparacion quedaria sesgada a su favor.

CREATE FUNCTION poc_cfg10.lado() RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$ SELECT 0.05::double precision $$;

CREATE FUNCTION poc_cfg10.lon0(c int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$ SELECT -75.0 + (c - 1) * 0.5 $$;

CREATE FUNCTION poc_cfg10.lat0(c int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$ SELECT 4.0 + (c - 1) * 0.5 $$;

-- Vertice (i, j) de la ciudad c; i en 0..5, j en 0..4.
CREATE FUNCTION poc_cfg10.vx(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT poc_cfg10.lon0(c) + i * poc_cfg10.lado()
       + CASE WHEN i BETWEEN 1 AND 4 AND j BETWEEN 1 AND 3
              THEN (poc_cfg10.hrand(format('vx/%s/%s/%s', c, i, j)) - 0.5) * 0.4 * poc_cfg10.lado()
              ELSE 0 END
$$;

CREATE FUNCTION poc_cfg10.vy(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT poc_cfg10.lat0(c) + j * poc_cfg10.lado()
       + CASE WHEN i BETWEEN 1 AND 4 AND j BETWEEN 1 AND 3
              THEN (poc_cfg10.hrand(format('vy/%s/%s/%s', c, i, j)) - 0.5) * 0.4 * poc_cfg10.lado()
              ELSE 0 END
$$;

-- Punto medio de la arista horizontal (i,j)-(i+1,j): se desplaza en lat
-- solo si la arista es interior (j en 1..3).
CREATE FUNCTION poc_cfg10.hmx(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (poc_cfg10.vx(c, i, j) + poc_cfg10.vx(c, i + 1, j)) / 2
$$;

CREATE FUNCTION poc_cfg10.hmy(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (poc_cfg10.vy(c, i, j) + poc_cfg10.vy(c, i + 1, j)) / 2
       + CASE WHEN j BETWEEN 1 AND 3
              THEN (poc_cfg10.hrand(format('h/%s/%s/%s', c, i, j)) - 0.5) * 0.4 * poc_cfg10.lado()
              ELSE 0 END
$$;

-- Punto medio de la arista vertical (i,j)-(i,j+1): se desplaza en lon solo
-- si la arista es interior (i en 1..4).
CREATE FUNCTION poc_cfg10.vmx(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (poc_cfg10.vx(c, i, j) + poc_cfg10.vx(c, i, j + 1)) / 2
       + CASE WHEN i BETWEEN 1 AND 4
              THEN (poc_cfg10.hrand(format('m/%s/%s/%s', c, i, j)) - 0.5) * 0.4 * poc_cfg10.lado()
              ELSE 0 END
$$;

CREATE FUNCTION poc_cfg10.vmy(c int, i int, j int) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (poc_cfg10.vy(c, i, j) + poc_cfg10.vy(c, i, j + 1)) / 2
$$;

-- Anillo de la celda (i, j), i en 0..4, j en 0..3, antihorario, 8 puntos
-- sin el de cierre: esquina, medio inferior, esquina, medio derecho,
-- esquina, medio superior, esquina, medio izquierdo.
CREATE FUNCTION poc_cfg10.celda_anillo(c int, i int, j int,
                                       OUT xs double precision[], OUT ys double precision[])
LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[poc_cfg10.vx(c, i, j),     poc_cfg10.hmx(c, i, j),     poc_cfg10.vx(c, i + 1, j),
               poc_cfg10.vmx(c, i + 1, j), poc_cfg10.vx(c, i + 1, j + 1), poc_cfg10.hmx(c, i, j + 1),
               poc_cfg10.vx(c, i, j + 1),  poc_cfg10.vmx(c, i, j)],
         ARRAY[poc_cfg10.vy(c, i, j),     poc_cfg10.hmy(c, i, j),     poc_cfg10.vy(c, i + 1, j),
               poc_cfg10.vmy(c, i + 1, j), poc_cfg10.vy(c, i + 1, j + 1), poc_cfg10.hmy(c, i, j + 1),
               poc_cfg10.vy(c, i, j + 1),  poc_cfg10.vmy(c, i, j)]
$$;

CREATE FUNCTION poc_cfg10.anillo_a_poligono(xs double precision[], ys double precision[])
RETURNS extensions.geometry LANGUAGE sql IMMUTABLE AS $$
  SELECT extensions.st_setsrid(
           extensions.st_makepolygon(
             extensions.st_makeline(ARRAY(
               SELECT extensions.st_makepoint(xs[1 + (k - 1) % array_length(xs, 1)],
                                              ys[1 + (k - 1) % array_length(ys, 1)])
               FROM generate_series(1, array_length(xs, 1) + 1) AS k
               ORDER BY k))),
           4326)
$$;
