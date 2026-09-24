-- =====================================================================
-- 005 · US-04.1.4 — Aceptar/rechazar solicitud sin doble asignación
-- RF-14 · QS-09 (exactamente 1 asignación válida, respuesta < 500 ms)
-- QS-06 (reglas del sitio visibles antes de aceptar) · QS-12 (evento)
--
-- Modelo: la solicitud se ofrece a la vez a todos los aliados válidos
-- (verificados, con la categoría y con cobertura en la zona). El primero que
-- acepta se la queda; los demás reciben "ya no disponible".
--
-- Exclusión (DD-MANI §7.1): la asignación es UN solo UPDATE condicional
--     UPDATE solicitud SET aliado_id = ?, estado = 'ASIGNADA'
--     WHERE id = ? AND estado = 'PENDIENTE' AND aliado_id IS NULL
-- PostgreSQL bloquea la fila: si dos transacciones compiten, la segunda
-- reevalúa el WHERE cuando la primera confirma, no encuentra filas y
-- responde 409. No hay ventana entre "leer" y "escribir".
--
-- Rechazar NO cambia la solicitud (sigue disponible para los demás): solo la
-- oculta para ese aliado y deja el motivo para análisis del tenant.
--
-- Seguridad: ninguna función recibe tenant_id ni aliado_id; ambos salen de
-- auth.uid(). Una solicitud de otro tenant responde 404.
--
-- Códigos de error (prefijo del mensaje, los traduce la app):
--   MANI-SOL-401  sin sesión
--   MANI-SOL-403  el usuario no es un aliado activo
--   MANI-SOL-403V el aliado aún no está verificado (US-02.1.3)
--   MANI-SOL-403E el aliado no atiende esa categoría o zona
--   MANI-SOL-404  solicitud inexistente o de otro tenant
--   MANI-SOL-409  otro aliado ya tomó la solicitud (ya_no_disponible)
--   MANI-SOL-409A la solicitud ya es tuya (no se puede rechazar aquí)
--   MANI-SOL-422M motivo de rechazo inválido
-- =====================================================================

-- 0. Tabla de control (por si el entorno no corrió 001) ----------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Rechazos por aliado -------------------------------------------------------
CREATE TABLE IF NOT EXISTS solicitud_rechazo (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    solicitud_id UUID NOT NULL REFERENCES solicitud(id) ON DELETE CASCADE,
    aliado_id UUID NOT NULL REFERENCES aliado(id) ON DELETE CASCADE,
    motivo TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ux_solicitud_rechazo UNIQUE (solicitud_id, aliado_id),
    CONSTRAINT ck_solicitud_rechazo_motivo CHECK (
        motivo IS NULL OR motivo IN ('FUERA_DE_ZONA', 'SIN_DISPONIBILIDAD', 'NO_ES_MI_ESPECIALIDAD', 'OTRO')
    )
);

ALTER TABLE solicitud_rechazo ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo se accede por las funciones SECURITY DEFINER de abajo.

CREATE INDEX IF NOT EXISTS idx_solicitud_tenant_estado
    ON solicitud (tenant_id, estado, created_at);
CREATE INDEX IF NOT EXISTS idx_solicitud_aliado
    ON solicitud (aliado_id) WHERE aliado_id IS NOT NULL;

-- 2. Contexto del aliado autenticado ----------------------------------------
CREATE OR REPLACE FUNCTION _sol_aliado_actual(
    OUT o_tenant UUID,
    OUT o_aliado UUID,
    OUT o_verificado BOOLEAN
)
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

    SELECT a.tenant_id, a.id, a.estado_verificacion = 'VERIFICADO'
    INTO o_tenant, o_aliado, o_verificado
    FROM aliado a
    JOIN usuario u ON u.id = a.usuario_id
    WHERE a.usuario_id = v_uid AND u.estado = 'ACTIVO';

    IF o_aliado IS NULL THEN
        RAISE EXCEPTION 'MANI-SOL-403: solo un aliado activo puede gestionar solicitudes';
    END IF;
END;
$$;

-- 3. ¿La zona de la solicitud cae en la cobertura del aliado? ----------------
-- Declarar una zona cubre sus descendientes (ADR-0011): se sube por la
-- jerarquía desde la zona de la solicitud buscando una zona declarada.
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
        WHERE c.aliado_id = p_aliado_id AND z.estado = 'activa'
    );
$$;

-- 4. ¿El aliado puede tomar esta solicitud? (categoría + cobertura) ---------
CREATE OR REPLACE FUNCTION _sol_aliado_elegible(p_aliado_id UUID, p_solicitud_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM solicitud s
        JOIN aliado_categoria ac ON ac.aliado_id = p_aliado_id AND ac.categoria_id = s.categoria_id
        WHERE s.id = p_solicitud_id
          AND _sol_zona_cubierta(p_aliado_id, s.zona_id)
    );
$$;

-- 5. Proyección JSON (la dirección exacta solo se revela al aliado asignado)
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

-- 6. Bandeja del aliado: disponibles para él + las que ya son suyas ---------
CREATE OR REPLACE FUNCTION listar_solicitudes_aliado()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
BEGIN
    SELECT * INTO v_ctx FROM _sol_aliado_actual();
    IF NOT v_ctx.o_verificado THEN
        RAISE EXCEPTION 'MANI-SOL-403V: tu registro como aliado aún no está verificado';
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(_sol_json(s.id, v_ctx.o_aliado) ORDER BY s.created_at)
        FROM solicitud s
        WHERE s.tenant_id = v_ctx.o_tenant
          AND (
                s.aliado_id = v_ctx.o_aliado
             OR (
                    s.estado = 'PENDIENTE'
                AND s.aliado_id IS NULL
                AND _sol_aliado_elegible(v_ctx.o_aliado, s.id)
                AND NOT EXISTS (
                    SELECT 1 FROM solicitud_rechazo r
                    WHERE r.solicitud_id = s.id AND r.aliado_id = v_ctx.o_aliado
                )
             )
          )
    ), '[]'::jsonb);
END;
$$;

-- 7. Aceptar (asignación atómica, idempotente para el mismo aliado) ---------
CREATE OR REPLACE FUNCTION aceptar_solicitud(p_solicitud_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
    v_aliado_actual UUID;
    v_filas INT;
BEGIN
    SELECT * INTO v_ctx FROM _sol_aliado_actual();
    IF NOT v_ctx.o_verificado THEN
        RAISE EXCEPTION 'MANI-SOL-403V: tu registro como aliado aún no está verificado';
    END IF;

    SELECT aliado_id INTO v_aliado_actual
    FROM solicitud
    WHERE id = p_solicitud_id AND tenant_id = v_ctx.o_tenant;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MANI-SOL-404: solicitud no encontrada';
    END IF;

    -- Reintento (doble toque / red inestable): mismo resultado, sin efectos.
    IF v_aliado_actual = v_ctx.o_aliado THEN
        RETURN _sol_json(p_solicitud_id, v_ctx.o_aliado);
    END IF;

    IF NOT _sol_aliado_elegible(v_ctx.o_aliado, p_solicitud_id) THEN
        RAISE EXCEPTION 'MANI-SOL-403E: no atiendes la categoría o la zona de esta solicitud';
    END IF;

    -- Único punto de decisión: el UPDATE condicional (ver cabecera).
    UPDATE solicitud
    SET aliado_id = v_ctx.o_aliado,
        estado = 'ASIGNADA',
        updated_at = now()
    WHERE id = p_solicitud_id
      AND tenant_id = v_ctx.o_tenant
      AND estado = 'PENDIENTE'
      AND aliado_id IS NULL;
    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas = 0 THEN
        -- Otro aliado confirmó primero (o la solicitud dejó de estar pendiente).
        RAISE EXCEPTION 'MANI-SOL-409: ya_no_disponible';
    END IF;

    -- QS-12: el cambio de estado queda en la línea de tiempo del servicio.
    INSERT INTO evento_servicio (tenant_id, solicitud_id, actor_id, tipo_evento, descripcion)
    VALUES (v_ctx.o_tenant, p_solicitud_id, auth.uid(), 'SOLICITUD_ASIGNADA', 'El aliado aceptó el servicio.');

    -- El cliente se entera sin tener que preguntar.
    INSERT INTO notificacion (tenant_id, usuario_id, tipo, canal, payload)
    SELECT v_ctx.o_tenant, cl.usuario_id, 'SOLICITUD_ASIGNADA', 'IN_APP',
           jsonb_build_object('solicitud_id', p_solicitud_id)
    FROM solicitud s JOIN cliente cl ON cl.id = s.cliente_id
    WHERE s.id = p_solicitud_id;

    RETURN _sol_json(p_solicitud_id, v_ctx.o_aliado);
END;
$$;

-- 8. Rechazar (solo para este aliado; idempotente) --------------------------
CREATE OR REPLACE FUNCTION rechazar_solicitud(p_solicitud_id UUID, p_motivo TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ctx RECORD;
    v_motivo TEXT := NULLIF(upper(btrim(COALESCE(p_motivo, ''))), '');
    v_aliado_actual UUID;
BEGIN
    SELECT * INTO v_ctx FROM _sol_aliado_actual();

    IF v_motivo IS NOT NULL
       AND v_motivo NOT IN ('FUERA_DE_ZONA', 'SIN_DISPONIBILIDAD', 'NO_ES_MI_ESPECIALIDAD', 'OTRO') THEN
        RAISE EXCEPTION 'MANI-SOL-422M: motivo inválido (%)', v_motivo;
    END IF;

    SELECT aliado_id INTO v_aliado_actual
    FROM solicitud
    WHERE id = p_solicitud_id AND tenant_id = v_ctx.o_tenant;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MANI-SOL-404: solicitud no encontrada';
    END IF;

    IF v_aliado_actual = v_ctx.o_aliado THEN
        RAISE EXCEPTION 'MANI-SOL-409A: la solicitud ya es tuya';
    END IF;

    INSERT INTO solicitud_rechazo (tenant_id, solicitud_id, aliado_id, motivo)
    VALUES (v_ctx.o_tenant, p_solicitud_id, v_ctx.o_aliado, v_motivo)
    ON CONFLICT (solicitud_id, aliado_id) DO NOTHING;

    RETURN jsonb_build_object('id', p_solicitud_id, 'rechazada', true);
END;
$$;

-- 9. Permisos ----------------------------------------------------------------
-- Supabase concede EXECUTE a anon/authenticated en toda función nueva.
REVOKE ALL ON FUNCTION _sol_aliado_actual() FROM PUBLIC;
REVOKE ALL ON FUNCTION _sol_zona_cubierta(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION _sol_aliado_elegible(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION _sol_json(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION listar_solicitudes_aliado() FROM PUBLIC;
REVOKE ALL ON FUNCTION aceptar_solicitud(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION rechazar_solicitud(UUID, TEXT) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION _sol_aliado_actual() FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _sol_zona_cubierta(UUID, UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _sol_aliado_elegible(UUID, UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION _sol_json(UUID, UUID) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION listar_solicitudes_aliado() FROM anon;
        REVOKE ALL ON FUNCTION aceptar_solicitud(UUID) FROM anon;
        REVOKE ALL ON FUNCTION rechazar_solicitud(UUID, TEXT) FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION listar_solicitudes_aliado() TO authenticated;
        GRANT EXECUTE ON FUNCTION aceptar_solicitud(UUID) TO authenticated;
        GRANT EXECUTE ON FUNCTION rechazar_solicitud(UUID, TEXT) TO authenticated;
    END IF;
END $$;

-- 10. Registro de la migración -----------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('005', 'US-04.1.4 aceptar/rechazar solicitud: asignacion atomica, rechazos por aliado')
ON CONFLICT (version) DO NOTHING;
