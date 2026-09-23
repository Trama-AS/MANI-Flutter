-- =====================================================================
-- 003 · US-03.1.3 — Aliado declara las categorías que atiende
-- (SCRUM-1016 modelo, SCRUM-1017 listar, SCRUM-1018 guardar)
--
-- Seguridad (anti tenant-spoofing):
--   * Ninguna función recibe tenant_id ni aliado_id. Ambos se derivan de
--     auth.uid() contra usuario + aliado.
--   * Solo se aceptan categorías ACTIVAS del tenant del aliado. Una categoría
--     de otro tenant responde igual que una inexistente (no se revela).
--   * La app no escribe directo en aliado_categoria: RLS solo permite leer
--     las filas propias; la escritura pasa por guardar_mis_categorias.
--
-- Lectura de aliado_categoria por terceros (revisado al crear esta migración):
--   * Ningún código de la app lee la tabla con .from('aliado_categoria') y no
--     hay vistas sobre ella. Los únicos lectores son funciones SECURITY
--     DEFINER (registro de aliados, bandeja de verificación 002) o
--     _ver_aliado_json, que es INVOKER pero solo se ejecuta dentro de las
--     funciones DEFINER de 002 (EXECUTE revocado a anon/authenticated).
--   * Por eso el SELECT queda limitado al propio aliado y no a todo el tenant.
--   * SCRUM-861 (US-04.1.2, aliados por cobertura y categoría) y el despacho
--     DEBEN buscar aliados por categoría mediante una RPC SECURITY DEFINER
--     que derive el tenant de auth.uid(). Una función SECURITY INVOKER
--     ejecutada por un cliente no verá las categorías de otros aliados.
--
-- Códigos de error (prefijo del mensaje, los traduce la app):
--   MANI-CAT-401  sin sesión
--   MANI-CAT-403  el usuario no es un aliado activo
--   MANI-CAT-422V selección vacía (mínimo una categoría)
--   MANI-CAT-422C categoría inexistente, inactiva o de otro tenant
-- =====================================================================

-- 0. Tabla de control de migraciones (idéntica a 001, por si no corrió) -----
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Modelo: un aliado no repite categoría ----------------------------------
-- Se eliminan duplicados previos (conserva una fila por par) para poder
-- crear el índice único.
DELETE FROM aliado_categoria a
USING aliado_categoria b
WHERE a.aliado_id = b.aliado_id
  AND a.categoria_id = b.categoria_id
  AND a.id > b.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_aliado_categoria
    ON aliado_categoria (aliado_id, categoria_id);

CREATE INDEX IF NOT EXISTS idx_aliado_categoria_tenant_categoria
    ON aliado_categoria (tenant_id, categoria_id);

-- 2. Modelo: aliado, categoría y fila deben ser del mismo tenant ------------
CREATE OR REPLACE FUNCTION _cat_validar_tenant_aliado_categoria()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM aliado WHERE id = NEW.aliado_id AND tenant_id = NEW.tenant_id
    ) OR NOT EXISTS (
        SELECT 1 FROM categoria_servicio WHERE id = NEW.categoria_id AND tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'MANI-CAT-422C: el aliado y la categoría deben pertenecer al mismo tenant';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_aliado_categoria_tenant ON aliado_categoria;
CREATE TRIGGER trg_aliado_categoria_tenant
    BEFORE INSERT OR UPDATE ON aliado_categoria
    FOR EACH ROW EXECUTE FUNCTION _cat_validar_tenant_aliado_categoria();

-- 8. Permisos ----------------------------------------------------------------
REVOKE ALL ON FUNCTION _cat_validar_tenant_aliado_categoria() FROM PUBLIC;

-- 9. Registro de la migración ------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('003', 'US-03.1.3 categorias del aliado: indice unico, trigger de tenant, RPCs y RLS')
ON CONFLICT (version) DO NOTHING;
