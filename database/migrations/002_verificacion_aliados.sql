-- =====================================================================
-- 002 · US-02.1.3 — Aprobar / rechazar registro de aliado (QS-04, RF-05/RF-06)
-- Bandeja de verificación del Administrador del Tenant.
--
-- Seguridad (anti tenant-spoofing):
--   * Ninguna función recibe tenant_id. El tenant y el rol del administrador
--     se derivan de auth.uid() contra la tabla usuario.
--   * Un aliado de otro tenant responde 404 (no se revela su existencia).
--   * resolver_verificacion_aliado bloquea la fila (FOR UPDATE): si dos
--     administradores deciden a la vez, solo el primero gana; el otro recibe 409.
--
-- Códigos de error (prefijo del mensaje, los traduce la app):
--   MANI-VER-401  sin sesión
--   MANI-VER-403  el usuario no es ADMIN_TENANT activo
--   MANI-VER-404  aliado inexistente o de otro tenant
--   MANI-VER-409  la solicitud ya fue resuelta
--   MANI-VER-422D decisión inválida
--   MANI-VER-422M motivo de rechazo inválido (10 a 500 caracteres)
--   MANI-VER-422K no se puede aprobar un aliado sin documentos KYC
--
-- Estados de aliado.estado_verificacion: PENDIENTE | VERIFICADO | RECHAZADO
-- =====================================================================

-- 0. Tabla de control de migraciones -----------------------------------------
-- Normalmente la crea 001_initial_schema.sql. Se repite aquí (idéntica,
-- IF NOT EXISTS) por si este entorno tiene las tablas de negocio pero nunca
-- corrió esa migración base — evita que el paso 8 falle con "relation
-- schema_migrations does not exist".
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Trazabilidad de la decisión -------------------------------------------
ALTER TABLE aliado ADD COLUMN IF NOT EXISTS motivo_rechazo TEXT;
ALTER TABLE aliado ADD COLUMN IF NOT EXISTS verificado_por UUID REFERENCES usuario(id) ON DELETE SET NULL;
ALTER TABLE aliado ADD COLUMN IF NOT EXISTS fecha_verificacion TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_aliado_tenant_estado
    ON aliado (tenant_id, estado_verificacion, created_at);

-- 2. Contexto del administrador autenticado --------------------------------
CREATE OR REPLACE FUNCTION _ver_tenant_admin_actual()
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
        RAISE EXCEPTION 'MANI-VER-401: sesión requerida';
    END IF;

    SELECT tenant_id, rol INTO v_tenant, v_rol
    FROM usuario
    WHERE id = v_uid AND estado = 'ACTIVO';

    IF v_tenant IS NULL OR v_rol IS DISTINCT FROM 'ADMIN_TENANT' THEN
        RAISE EXCEPTION 'MANI-VER-403: solo el administrador del tenant puede verificar aliados';
    END IF;

    RETURN v_tenant;
END;
$$;

-- 3. Proyección JSON de un aliado con sus documentos ------------------------
-- SECURITY INVOKER a propósito: no filtra por tenant, así que solo debe correr
-- dentro de las funciones públicas de abajo (que ya validaron el tenant).
CREATE OR REPLACE FUNCTION _ver_aliado_json(p_aliado_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', a.id,
        'tipo', a.tipo,
        'nombre', a.nombre_razon_social,
        'email', u.email,
        'estado_verificacion', a.estado_verificacion,
        'fecha_registro', a.created_at,
        'motivo_rechazo', a.motivo_rechazo,
        'fecha_verificacion', a.fecha_verificacion,
        'categorias', COALESCE((
            SELECT jsonb_agg(c.nombre ORDER BY c.nombre)
            FROM aliado_categoria ac
            JOIN categoria_servicio c ON c.id = ac.categoria_id
            WHERE ac.aliado_id = a.id
        ), '[]'::jsonb),
        'documentos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', d.id,
                'tipo_documento', d.tipo_documento,
                'ruta_storage', d.ruta_storage,
                'estado', d.estado,
                'fecha_carga', d.fecha_carga
            ) ORDER BY d.fecha_carga)
            FROM documento_kyc d
            WHERE d.aliado_id = a.id
        ), '[]'::jsonb)
    )
    FROM aliado a
    JOIN usuario u ON u.id = a.usuario_id
    WHERE a.id = p_aliado_id;
$$;

-- 4. Bandeja: aliados del tenant del administrador --------------------------
CREATE OR REPLACE FUNCTION listar_aliados_verificacion()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant UUID := _ver_tenant_admin_actual();
BEGIN
    RETURN COALESCE((
        SELECT jsonb_agg(_ver_aliado_json(a.id) ORDER BY a.created_at)
        FROM aliado a
        WHERE a.tenant_id = v_tenant
    ), '[]'::jsonb);
END;
$$;

-- 5. Detalle (lectura fresca antes de decidir) ------------------------------
CREATE OR REPLACE FUNCTION obtener_aliado_verificacion(p_aliado_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant UUID := _ver_tenant_admin_actual();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM aliado WHERE id = p_aliado_id AND tenant_id = v_tenant) THEN
        RAISE EXCEPTION 'MANI-VER-404: aliado no encontrado';
    END IF;
    RETURN _ver_aliado_json(p_aliado_id);
END;
$$;

-- 6. Aprobar / rechazar ------------------------------------------------------
CREATE OR REPLACE FUNCTION resolver_verificacion_aliado(
    p_aliado_id UUID,
    p_decision TEXT,
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant UUID := _ver_tenant_admin_actual();
    v_decision TEXT := upper(trim(COALESCE(p_decision, '')));
    v_motivo TEXT := NULLIF(trim(COALESCE(p_motivo, '')), '');
    v_aliado aliado%ROWTYPE;
BEGIN
    IF v_decision NOT IN ('VERIFICADO', 'RECHAZADO') THEN
        RAISE EXCEPTION 'MANI-VER-422D: decisión inválida (%)', v_decision;
    END IF;

    IF v_decision = 'RECHAZADO'
       AND (v_motivo IS NULL OR char_length(v_motivo) < 10 OR char_length(v_motivo) > 500) THEN
        RAISE EXCEPTION 'MANI-VER-422M: el motivo de rechazo debe tener entre 10 y 500 caracteres';
    END IF;

    SELECT * INTO v_aliado
    FROM aliado
    WHERE id = p_aliado_id AND tenant_id = v_tenant
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'MANI-VER-404: aliado no encontrado';
    END IF;

    IF v_aliado.estado_verificacion <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'MANI-VER-409: la solicitud ya fue resuelta (%)', v_aliado.estado_verificacion;
    END IF;

    IF v_decision = 'VERIFICADO'
       AND NOT EXISTS (SELECT 1 FROM documento_kyc WHERE aliado_id = p_aliado_id) THEN
        RAISE EXCEPTION 'MANI-VER-422K: el aliado no tiene documentos KYC';
    END IF;

    UPDATE aliado
    SET estado_verificacion = v_decision,
        motivo_rechazo = CASE WHEN v_decision = 'RECHAZADO' THEN v_motivo END,
        verificado_por = auth.uid(),
        fecha_verificacion = now()
    WHERE id = p_aliado_id;

    UPDATE documento_kyc
    SET estado = v_decision
    WHERE aliado_id = p_aliado_id AND estado = 'PENDIENTE';

    -- QS-04: el aliado ve el resultado sin tener que preguntar.
    INSERT INTO notificacion (tenant_id, usuario_id, tipo, canal, payload)
    VALUES (
        v_tenant,
        v_aliado.usuario_id,
        'VERIFICACION_ALIADO',
        'IN_APP',
        jsonb_build_object('decision', v_decision, 'motivo', v_motivo)
    );

    RETURN _ver_aliado_json(p_aliado_id);
END;
$$;

-- 7. Permisos ----------------------------------------------------------------
-- Supabase concede EXECUTE a anon/authenticated en toda función nueva (default
-- privileges); revocar solo de PUBLIC no basta. Los helpers _ver_* no deben
-- poder invocarse por RPC, y la bandeja exige sesión (nunca anon).
REVOKE ALL ON FUNCTION _ver_tenant_admin_actual() FROM PUBLIC;
REVOKE ALL ON FUNCTION _ver_aliado_json(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION listar_aliados_verificacion() FROM PUBLIC;
REVOKE ALL ON FUNCTION obtener_aliado_verificacion(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION resolver_verificacion_aliado(UUID, TEXT, TEXT) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION _ver_tenant_admin_actual() FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _ver_aliado_json(UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION listar_aliados_verificacion() FROM anon;
        REVOKE ALL ON FUNCTION obtener_aliado_verificacion(UUID) FROM anon;
        REVOKE ALL ON FUNCTION resolver_verificacion_aliado(UUID, TEXT, TEXT) FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION listar_aliados_verificacion() TO authenticated;
        GRANT EXECUTE ON FUNCTION obtener_aliado_verificacion(UUID) TO authenticated;
        GRANT EXECUTE ON FUNCTION resolver_verificacion_aliado(UUID, TEXT, TEXT) TO authenticated;
    END IF;
END $$;

-- 8. Registro de la migración ------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('002', 'US-02.1.3 verificacion de aliados: columnas de decision y RPCs de bandeja')
ON CONFLICT (version) DO NOTHING;
