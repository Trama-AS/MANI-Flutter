-- =====================================================================
-- 003 · US-03.1.1 — Crear categoría con flujo operativo (QS-07, RF-02/RF-10)
-- Catálogo de categorías de servicio administrado por el Admin del Tenant.
--
-- Seguridad (anti tenant-spoofing):
--   * Ninguna función recibe tenant_id: se deriva de auth.uid() contra usuario.
--   * Solo un ADMIN_TENANT activo puede listar (incluidas inactivas) y crear.
--
-- Flujos operativos (categoria_servicio.flujo_operativo):
--   COTIZACION_PREVIA  el aliado diagnostica y envía una cotización que el
--                      cliente acepta antes de ejecutar (RF-15/RF-17).
--   TARIFA_ESTANDAR    el servicio se cobra con la tarifa de referencia del
--                      tenant, sin cotización previa (RF-22).
--
-- Códigos de error (prefijo del mensaje, los traduce la app):
--   MANI-CAT-401  sin sesión
--   MANI-CAT-403  el usuario no es ADMIN_TENANT activo
--   MANI-CAT-409  ya existe una categoría con ese nombre en el tenant
--   MANI-CAT-422N nombre inválido (3 a 60 caracteres, al menos una letra)
--   MANI-CAT-422F flujo operativo inválido
-- =====================================================================

-- 0. Tabla de control (por si el entorno no corrió 001) ----------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Trazabilidad ------------------------------------------------------------
ALTER TABLE categoria_servicio ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE categoria_servicio ADD COLUMN IF NOT EXISTS creado_por UUID REFERENCES usuario(id) ON DELETE SET NULL;

-- 2. Integridad ----------------------------------------------------------------
-- Nombre único por tenant sin distinguir mayúsculas ni espacios extremos.
-- Si un entorno ya tiene duplicados, este índice falla: depurarlos antes.
CREATE UNIQUE INDEX IF NOT EXISTS ux_categoria_tenant_nombre
    ON categoria_servicio (tenant_id, lower(btrim(nombre)));

-- NOT VALID: se exige a filas nuevas sin romper datos históricos.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_categoria_estado') THEN
        ALTER TABLE categoria_servicio
            ADD CONSTRAINT ck_categoria_estado CHECK (estado IN ('ACTIVO', 'INACTIVO')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_categoria_flujo') THEN
        ALTER TABLE categoria_servicio
            ADD CONSTRAINT ck_categoria_flujo
            CHECK (flujo_operativo IN ('COTIZACION_PREVIA', 'TARIFA_ESTANDAR')) NOT VALID;
    END IF;
END $$;

-- 3. Contexto del administrador autenticado --------------------------------
CREATE OR REPLACE FUNCTION _cat_tenant_admin_actual()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_tenant UUID;
    v_rol TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'MANI-CAT-401: sesión requerida';
    END IF;

    SELECT tenant_id, rol INTO v_tenant, v_rol
    FROM usuario
    WHERE id = v_uid AND estado = 'ACTIVO';

    IF v_tenant IS NULL OR v_rol IS DISTINCT FROM 'ADMIN_TENANT' THEN
        RAISE EXCEPTION 'MANI-CAT-403: solo el administrador del tenant gestiona categorías';
    END IF;

    RETURN v_tenant;
END;
$$;

-- 4. Proyección JSON de una categoría ---------------------------------------
-- SECURITY INVOKER: no filtra por tenant; solo se usa desde las funciones de
-- abajo, que ya validaron al administrador.
CREATE OR REPLACE FUNCTION _cat_json(p_categoria_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', c.id,
        'nombre', c.nombre,
        'estado', c.estado,
        'flujo_operativo', c.flujo_operativo,
        'created_at', c.created_at,
        'aliados', (SELECT count(*) FROM aliado_categoria ac WHERE ac.categoria_id = c.id)
    )
    FROM categoria_servicio c
    WHERE c.id = p_categoria_id;
$$;

-- 5. Listado para el administrador (incluye inactivas) ----------------------
CREATE OR REPLACE FUNCTION listar_categorias_admin()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant UUID := _cat_tenant_admin_actual();
BEGIN
    RETURN COALESCE((
        SELECT jsonb_agg(_cat_json(c.id) ORDER BY lower(c.nombre))
        FROM categoria_servicio c
        WHERE c.tenant_id = v_tenant
    ), '[]'::jsonb);
END;
$$;

-- 6. Crear categoría ---------------------------------------------------------
CREATE OR REPLACE FUNCTION crear_categoria_servicio(
    p_nombre TEXT,
    p_flujo_operativo TEXT,
    p_activa BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant UUID := _cat_tenant_admin_actual();
    v_nombre TEXT := regexp_replace(btrim(COALESCE(p_nombre, '')), '\s+', ' ', 'g');
    v_flujo TEXT := upper(btrim(COALESCE(p_flujo_operativo, '')));
    v_id UUID;
BEGIN
    IF char_length(v_nombre) < 3 OR char_length(v_nombre) > 60 OR v_nombre !~ '[[:alpha:]]' THEN
        RAISE EXCEPTION 'MANI-CAT-422N: el nombre debe tener entre 3 y 60 caracteres y al menos una letra';
    END IF;

    IF v_flujo NOT IN ('COTIZACION_PREVIA', 'TARIFA_ESTANDAR') THEN
        RAISE EXCEPTION 'MANI-CAT-422F: flujo operativo inválido (%)', v_flujo;
    END IF;

    BEGIN
        INSERT INTO categoria_servicio (tenant_id, nombre, estado, flujo_operativo, creado_por)
        VALUES (
            v_tenant,
            v_nombre,
            CASE WHEN COALESCE(p_activa, true) THEN 'ACTIVO' ELSE 'INACTIVO' END,
            v_flujo,
            auth.uid()
        )
        RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        -- Doble toque o dos admins a la vez: el índice único decide.
        RAISE EXCEPTION 'MANI-CAT-409: ya existe la categoría "%"', v_nombre;
    END;

    RETURN _cat_json(v_id);
END;
$$;

-- 7. Permisos ----------------------------------------------------------------
-- Supabase concede EXECUTE a anon/authenticated en toda función nueva.
REVOKE ALL ON FUNCTION _cat_tenant_admin_actual() FROM PUBLIC;
REVOKE ALL ON FUNCTION _cat_json(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION listar_categorias_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION crear_categoria_servicio(TEXT, TEXT, BOOLEAN) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION _cat_tenant_admin_actual() FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _cat_json(UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION listar_categorias_admin() FROM anon;
        REVOKE ALL ON FUNCTION crear_categoria_servicio(TEXT, TEXT, BOOLEAN) FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION listar_categorias_admin() TO authenticated;
        GRANT EXECUTE ON FUNCTION crear_categoria_servicio(TEXT, TEXT, BOOLEAN) TO authenticated;
    END IF;
END $$;

-- 8. Registro de la migración ------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('003', 'US-03.1.1 categorias de servicio: RPCs de listado y creacion con flujo operativo')
ON CONFLICT (version) DO NOTHING;
