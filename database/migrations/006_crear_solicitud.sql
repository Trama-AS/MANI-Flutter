-- =====================================================================
-- 006 · US-04.1.1 — Crear solicitud (cliente)
-- El cliente publica su problema locativo (descripción + fotos) en una
-- categoría y un sitio; queda PENDIENTE y los aliados válidos la ven en su
-- bandeja (US-04.1.4) para aceptarla y cotizar.
--
-- Seguridad (anti tenant-spoofing):
--   * Ninguna función recibe tenant_id ni cliente_id: salen de auth.uid().
--   * Las fotos viven en el bucket privado `solicitudes`, bajo la carpeta
--     <auth.uid()>/...; la RPC rechaza rutas de otra carpeta.
--
-- Idempotencia: la app envía una clave única por intento de publicación. Si
-- la misma clave llega dos veces (doble toque, reintento de red) se devuelve
-- la solicitud ya creada en vez de duplicarla.
--
-- Códigos de error (prefijo del mensaje, los traduce la app):
--   MANI-SOL-401  sin sesión
--   MANI-SOL-403C el usuario no es un cliente activo
--   MANI-SOL-422C categoría inexistente, inactiva o de otro tenant
--   MANI-SOL-422D descripción inválida (20 a 1000 caracteres)
--   MANI-SOL-422F fotos inválidas (máx. 5, dentro de la carpeta del usuario)
--   MANI-SOL-422S sitio inexistente o de otro cliente / dirección inválida
--   MANI-SOL-422Z zona inexistente o inactiva
-- =====================================================================

-- 0. Tabla de control (por si el entorno no corrió 001) ----------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Detalle del problema e idempotencia ---------------------------------------
ALTER TABLE solicitud ADD COLUMN IF NOT EXISTS descripcion TEXT;
ALTER TABLE solicitud ADD COLUMN IF NOT EXISTS clave_idempotencia UUID;

CREATE UNIQUE INDEX IF NOT EXISTS ux_solicitud_cliente_clave
    ON solicitud (cliente_id, clave_idempotencia)
    WHERE clave_idempotencia IS NOT NULL;

CREATE TABLE IF NOT EXISTS solicitud_foto (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    solicitud_id UUID NOT NULL REFERENCES solicitud(id) ON DELETE CASCADE,
    ruta_storage TEXT NOT NULL,
    orden SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ux_solicitud_foto_orden UNIQUE (solicitud_id, orden)
);
ALTER TABLE solicitud_foto ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo se accede por las funciones SECURITY DEFINER.

-- 2. Estado activo de una zona -------------------------------------------------
-- Los seeds guardan zona.estado = 'ACTIVO' y la feature de cobertura usa
-- 'activa'. Un único criterio para ambos formatos.
CREATE OR REPLACE FUNCTION _zona_activa(p_estado TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT upper(btrim(COALESCE(p_estado, ''))) IN ('ACTIVA', 'ACTIVO');
$$;

-- Corrige 005: comparaba solo contra 'activa' y, con los datos de los seeds,
-- ningún aliado resultaba elegible. Se reemplaza (005 ya está mergeada).
CREATE OR REPLACE FUNCTION _sol_zona_cubierta(p_aliado_id UUID, p_zona_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH RECURSIVE ascendencia AS (
        SELECT z.id, z.zona_padre_id, 1 AS nivel FROM zona z WHERE z.id = p_zona_id
        UNION ALL
        SELECT z.id, z.zona_padre_id, a.nivel + 1
        FROM zona z JOIN ascendencia a ON z.id = a.zona_padre_id
        WHERE a.nivel < 10
    )
    SELECT EXISTS (
        SELECT 1
        FROM cobertura_aliado c
        JOIN ascendencia a ON a.id = c.zona_id
        JOIN zona z ON z.id = c.zona_id
        WHERE c.aliado_id = p_aliado_id AND _zona_activa(z.estado)
    );
$$;

-- 3. Contexto del cliente autenticado ----------------------------------------
CREATE OR REPLACE FUNCTION _solc_cliente_actual(OUT o_tenant UUID, OUT o_cliente UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'MANI-SOL-401: sesión requerida';
    END IF;

    SELECT c.tenant_id, c.id INTO o_tenant, o_cliente
    FROM cliente c
    JOIN usuario u ON u.id = c.usuario_id
    WHERE c.usuario_id = v_uid AND u.estado = 'ACTIVO';

    IF o_cliente IS NULL THEN
        RAISE EXCEPTION 'MANI-SOL-403C: solo un cliente activo puede publicar solicitudes';
    END IF;
END;
$$;

-- 4. Catálogo visible para el cliente: categorías ACTIVAS de su tenant -------
CREATE OR REPLACE FUNCTION listar_categorias_cliente()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
BEGIN
    SELECT * INTO v_ctx FROM _solc_cliente_actual();
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', c.id,
            'nombre', c.nombre,
            'flujo_operativo', c.flujo_operativo
        ) ORDER BY lower(c.nombre))
        FROM categoria_servicio c
        WHERE c.tenant_id = v_ctx.o_tenant AND c.estado = 'ACTIVO'
    ), '[]'::jsonb);
END;
$$;

-- 5. Sitios (direcciones) del cliente -----------------------------------------
CREATE OR REPLACE FUNCTION listar_mis_sitios()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
BEGIN
    SELECT * INTO v_ctx FROM _solc_cliente_actual();
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'direccion', s.direccion,
            'zona', z.nombre,
            'zona_padre', zp.nombre
        ) ORDER BY s.created_at DESC)
        FROM sitio s
        JOIN zona z ON z.id = s.zona_id
        LEFT JOIN zona zp ON zp.id = z.zona_padre_id
        WHERE s.cliente_id = v_ctx.o_cliente
    ), '[]'::jsonb);
END;
$$;

-- 6. Búsqueda de barrios/localidades para una dirección nueva ---------------
-- El catálogo de zonas es global (ADR-0011).
CREATE OR REPLACE FUNCTION buscar_zonas_cliente(p_texto TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
    v_texto TEXT := btrim(COALESCE(p_texto, ''));
BEGIN
    SELECT * INTO v_ctx FROM _solc_cliente_actual();
    IF char_length(v_texto) < 2 THEN
        RETURN '[]'::jsonb;
    END IF;
    RETURN COALESCE((
        SELECT jsonb_agg(fila ORDER BY fila->>'nombre')
        FROM (
            SELECT jsonb_build_object('id', z.id, 'nombre', z.nombre, 'zona_padre', zp.nombre) AS fila
            FROM zona z
            LEFT JOIN zona zp ON zp.id = z.zona_padre_id
            WHERE _zona_activa(z.estado)
              AND z.zona_padre_id IS NOT NULL
              AND z.nombre ILIKE '%' || v_texto || '%'
            LIMIT 20
        ) t
    ), '[]'::jsonb);
END;
$$;

-- 7. Crear solicitud -----------------------------------------------------------
CREATE OR REPLACE FUNCTION crear_solicitud(
    p_categoria_id UUID,
    p_descripcion TEXT,
    p_sitio_id UUID DEFAULT NULL,
    p_direccion TEXT DEFAULT NULL,
    p_zona_id UUID DEFAULT NULL,
    p_fotos TEXT[] DEFAULT '{}',
    p_clave_idempotencia UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
    v_descripcion TEXT := btrim(COALESCE(p_descripcion, ''));
    v_direccion TEXT := regexp_replace(btrim(COALESCE(p_direccion, '')), '\s+', ' ', 'g');
    v_fotos TEXT[] := COALESCE(p_fotos, '{}');
    v_prefijo TEXT := auth.uid()::text || '/';
    v_sitio UUID;
    v_zona UUID;
    v_id UUID;
    v_i INT;
BEGIN
    SELECT * INTO v_ctx FROM _solc_cliente_actual();

    -- Idempotencia: la misma clave devuelve la solicitud ya creada.
    IF p_clave_idempotencia IS NOT NULL THEN
        SELECT id INTO v_id FROM solicitud
        WHERE cliente_id = v_ctx.o_cliente AND clave_idempotencia = p_clave_idempotencia;
        IF FOUND THEN
            RETURN _solc_json(v_id);
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM categoria_servicio
        WHERE id = p_categoria_id AND tenant_id = v_ctx.o_tenant AND estado = 'ACTIVO'
    ) THEN
        RAISE EXCEPTION 'MANI-SOL-422C: categoría no disponible';
    END IF;

    IF char_length(v_descripcion) < 20 OR char_length(v_descripcion) > 1000 THEN
        RAISE EXCEPTION 'MANI-SOL-422D: la descripción debe tener entre 20 y 1000 caracteres';
    END IF;

    IF cardinality(v_fotos) > 5 OR EXISTS (
        SELECT 1 FROM unnest(v_fotos) f WHERE left(f, char_length(v_prefijo)) <> v_prefijo
    ) THEN
        RAISE EXCEPTION 'MANI-SOL-422F: fotos inválidas';
    END IF;

    -- Ubicación: un sitio existente del cliente o una dirección nueva.
    IF p_sitio_id IS NOT NULL THEN
        SELECT id, zona_id INTO v_sitio, v_zona
        FROM sitio WHERE id = p_sitio_id AND cliente_id = v_ctx.o_cliente;
        IF v_sitio IS NULL THEN
            RAISE EXCEPTION 'MANI-SOL-422S: el sitio no existe';
        END IF;
    ELSE
        IF char_length(v_direccion) < 5 OR char_length(v_direccion) > 200 THEN
            RAISE EXCEPTION 'MANI-SOL-422S: la dirección debe tener entre 5 y 200 caracteres';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM zona WHERE id = p_zona_id AND _zona_activa(estado)) THEN
            RAISE EXCEPTION 'MANI-SOL-422Z: zona no disponible';
        END IF;
    END IF;

    -- El sitio nuevo se crea dentro del bloque: si otro envío con la misma
    -- clave gana la carrera, se deshace junto con la solicitud (sin huérfanos).
    BEGIN
        IF v_sitio IS NULL THEN
            INSERT INTO sitio (tenant_id, cliente_id, zona_id, direccion, reglas)
            VALUES (v_ctx.o_tenant, v_ctx.o_cliente, p_zona_id, v_direccion, '{}'::jsonb)
            RETURNING id, zona_id INTO v_sitio, v_zona;
        END IF;

        INSERT INTO solicitud (
            tenant_id, cliente_id, sitio_id, categoria_id, zona_id,
            estado, descripcion, clave_idempotencia
        )
        VALUES (
            v_ctx.o_tenant, v_ctx.o_cliente, v_sitio, p_categoria_id, v_zona,
            'PENDIENTE', v_descripcion, p_clave_idempotencia
        )
        RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        -- Dos envíos con la misma clave a la vez: gana el primero.
        SELECT id INTO v_id FROM solicitud
        WHERE cliente_id = v_ctx.o_cliente AND clave_idempotencia = p_clave_idempotencia;
        RETURN _solc_json(v_id);
    END;

    FOR v_i IN 1 .. cardinality(v_fotos) LOOP
        INSERT INTO solicitud_foto (tenant_id, solicitud_id, ruta_storage, orden)
        VALUES (v_ctx.o_tenant, v_id, v_fotos[v_i], v_i);
    END LOOP;

    -- QS-12: la creación abre la línea de tiempo del servicio.
    INSERT INTO evento_servicio (tenant_id, solicitud_id, actor_id, tipo_evento, descripcion)
    VALUES (v_ctx.o_tenant, v_id, auth.uid(), 'SOLICITUD_CREADA', left(v_descripcion, 200));

    RETURN _solc_json(v_id);
END;
$$;

-- 8. Proyección JSON de la solicitud creada (se resuelve en tiempo de
-- ejecución, por eso puede definirse después de crear_solicitud) -----------
CREATE OR REPLACE FUNCTION _solc_json(p_solicitud_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', s.id,
        'estado', s.estado,
        'categoria', c.nombre,
        'flujo_operativo', c.flujo_operativo,
        'descripcion', s.descripcion,
        'direccion', si.direccion,
        'zona', z.nombre,
        'zona_padre', zp.nombre,
        'fotos', (SELECT count(*) FROM solicitud_foto f WHERE f.solicitud_id = s.id),
        'created_at', s.created_at
    )
    FROM solicitud s
    JOIN categoria_servicio c ON c.id = s.categoria_id
    JOIN sitio si ON si.id = s.sitio_id
    JOIN zona z ON z.id = s.zona_id
    LEFT JOIN zona zp ON zp.id = z.zona_padre_id
    WHERE s.id = p_solicitud_id;
$$;

-- 8b. Bandeja del aliado (005): ahora también muestra el problema descrito
-- por el cliente y cuántas fotos adjuntó, para que pueda decidir y cotizar.
CREATE OR REPLACE FUNCTION _sol_json(p_solicitud_id UUID, p_aliado_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', s.id,
        'estado', s.estado,
        'es_mia', s.aliado_id IS NOT DISTINCT FROM p_aliado_id,
        'categoria', c.nombre,
        'flujo_operativo', c.flujo_operativo,
        'descripcion', s.descripcion,
        'fotos', (SELECT count(*) FROM solicitud_foto f WHERE f.solicitud_id = s.id),
        'zona', z.nombre,
        'zona_padre', zp.nombre,
        'reglas_sitio', COALESCE(si.reglas, '{}'::jsonb),
        'direccion', CASE WHEN s.aliado_id = p_aliado_id THEN si.direccion END,
        'created_at', s.created_at,
        'asignada_at', CASE WHEN s.aliado_id = p_aliado_id THEN s.updated_at END
    )
    FROM solicitud s
    JOIN categoria_servicio c ON c.id = s.categoria_id
    JOIN zona z ON z.id = s.zona_id
    LEFT JOIN zona zp ON zp.id = z.zona_padre_id
    LEFT JOIN sitio si ON si.id = s.sitio_id
    WHERE s.id = p_solicitud_id;
$$;

-- 9. Storage: bucket privado de fotos, cada usuario en su carpeta -----------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'storage') THEN
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('solicitudes', 'solicitudes', false)
        ON CONFLICT (id) DO NOTHING;

        DROP POLICY IF EXISTS "solicitudes_subir_propias" ON storage.objects;
        CREATE POLICY "solicitudes_subir_propias" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id = 'solicitudes' AND (storage.foldername(name))[1] = auth.uid()::text);

        DROP POLICY IF EXISTS "solicitudes_actualizar_propias" ON storage.objects;
        CREATE POLICY "solicitudes_actualizar_propias" ON storage.objects
            FOR UPDATE TO authenticated
            USING (bucket_id = 'solicitudes' AND (storage.foldername(name))[1] = auth.uid()::text);

        DROP POLICY IF EXISTS "solicitudes_borrar_propias" ON storage.objects;
        CREATE POLICY "solicitudes_borrar_propias" ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id = 'solicitudes' AND (storage.foldername(name))[1] = auth.uid()::text);

        DROP POLICY IF EXISTS "solicitudes_leer_propias" ON storage.objects;
        CREATE POLICY "solicitudes_leer_propias" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id = 'solicitudes' AND (storage.foldername(name))[1] = auth.uid()::text);
    END IF;
END $$;

-- 10. Permisos -----------------------------------------------------------------
REVOKE ALL ON FUNCTION _zona_activa(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION _solc_cliente_actual() FROM PUBLIC;
REVOKE ALL ON FUNCTION _solc_json(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION listar_categorias_cliente() FROM PUBLIC;
REVOKE ALL ON FUNCTION listar_mis_sitios() FROM PUBLIC;
REVOKE ALL ON FUNCTION buscar_zonas_cliente(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION crear_solicitud(UUID, TEXT, UUID, TEXT, UUID, TEXT[], UUID) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION _zona_activa(TEXT) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _solc_cliente_actual() FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _solc_json(UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION listar_categorias_cliente() FROM anon;
        REVOKE ALL ON FUNCTION listar_mis_sitios() FROM anon;
        REVOKE ALL ON FUNCTION buscar_zonas_cliente(TEXT) FROM anon;
        REVOKE ALL ON FUNCTION crear_solicitud(UUID, TEXT, UUID, TEXT, UUID, TEXT[], UUID) FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION listar_categorias_cliente() TO authenticated;
        GRANT EXECUTE ON FUNCTION listar_mis_sitios() TO authenticated;
        GRANT EXECUTE ON FUNCTION buscar_zonas_cliente(TEXT) TO authenticated;
        GRANT EXECUTE ON FUNCTION crear_solicitud(UUID, TEXT, UUID, TEXT, UUID, TEXT[], UUID) TO authenticated;
    END IF;
END $$;

-- 11. Registro de la migración -------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('006', 'US-04.1.1 crear solicitud: descripcion, fotos, idempotencia; corrige zona activa de 005')
ON CONFLICT (version) DO NOTHING;
