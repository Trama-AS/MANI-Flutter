-- =====================================================================
-- US-03.1.3 (SCRUM-1021): pruebas de backend de la migración 004
-- Guardado/consulta de categorías del aliado y aislamiento por tenant.
--
-- Uso: pegar completo en el SQL Editor de Supabase DESPUÉS de aplicar
-- 004_aliado_categorias.sql. Corre dentro de una transacción que termina en
-- ROLLBACK: crea sus propios datos de prueba y no deja nada guardado.
-- Si alguna aserción falla, se detiene con "FALLO: ...". Si todo pasa,
-- el último mensaje es "OK: 12 pruebas de categorías del aliado".
-- =====================================================================

BEGIN;

-- Datos de prueba: dos tenants, un aliado en cada uno y un cliente.
INSERT INTO tenant (id, nombre, slug, estado) VALUES
    ('7e570000-0000-4000-8000-0000000000a1', 'TEST cat T1', 'test-cat-t1', 'ACTIVO'),
    ('7e570000-0000-4000-8000-0000000000a2', 'TEST cat T2', 'test-cat-t2', 'ACTIVO');
INSERT INTO categoria_servicio (id, tenant_id, nombre, estado) VALUES
    ('7e570000-0000-4000-8000-0000000000c1', '7e570000-0000-4000-8000-0000000000a1', 'TEST Plomería', 'ACTIVO'),
    ('7e570000-0000-4000-8000-0000000000c2', '7e570000-0000-4000-8000-0000000000a1', 'TEST Electricidad', 'ACTIVO'),
    ('7e570000-0000-4000-8000-0000000000c3', '7e570000-0000-4000-8000-0000000000a1', 'TEST Inactiva', 'INACTIVO'),
    ('7e570000-0000-4000-8000-0000000000c9', '7e570000-0000-4000-8000-0000000000a2', 'TEST Cerrajería', 'ACTIVO');
INSERT INTO usuario (id, tenant_id, email, rol, estado) VALUES
    ('7e570000-0000-4000-8000-0000000000b1', '7e570000-0000-4000-8000-0000000000a1', 'test-cat-a1@mani.test', 'ALIADO', 'ACTIVO'),
    ('7e570000-0000-4000-8000-0000000000b2', '7e570000-0000-4000-8000-0000000000a2', 'test-cat-a2@mani.test', 'ALIADO', 'ACTIVO'),
    ('7e570000-0000-4000-8000-0000000000b3', '7e570000-0000-4000-8000-0000000000a1', 'test-cat-cli@mani.test', 'CLIENTE', 'ACTIVO');
INSERT INTO aliado (id, tenant_id, usuario_id, tipo, nombre_razon_social, estado_verificacion) VALUES
    ('7e570000-0000-4000-8000-0000000000d1', '7e570000-0000-4000-8000-0000000000a1', '7e570000-0000-4000-8000-0000000000b1', 'PERSONA_NATURAL', 'TEST A1', 'VERIFICADO'),
    ('7e570000-0000-4000-8000-0000000000d2', '7e570000-0000-4000-8000-0000000000a2', '7e570000-0000-4000-8000-0000000000b2', 'PERSONA_NATURAL', 'TEST A2', 'PENDIENTE');

DO $$
DECLARE
    c1 CONSTANT UUID := '7e570000-0000-4000-8000-0000000000c1';
    c2 CONSTANT UUID := '7e570000-0000-4000-8000-0000000000c2';
    c3 CONSTANT UUID := '7e570000-0000-4000-8000-0000000000c3';
    c9 CONSTANT UUID := '7e570000-0000-4000-8000-0000000000c9';
    v JSONB;
    n INT := 0;
BEGIN
    -- La sesión se simula con request.jwt.claims, de donde Supabase
    -- lee auth.uid().

    -- 1. Sin sesión -> 401
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    BEGIN
        PERFORM listar_categorias_tenant();
        RAISE EXCEPTION 'FALLO: sin sesión debió responder 401';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-401%' THEN RAISE EXCEPTION 'FALLO 1: %', SQLERRM; END IF;
    END;
    n := n + 1;

    -- 2. Un cliente no puede guardar -> 403
    PERFORM set_config('request.jwt.claims', '{"sub":"7e570000-0000-4000-8000-0000000000b3","role":"authenticated"}', true);
    PERFORM set_config('request.jwt.claim.sub', '7e570000-0000-4000-8000-0000000000b3', true);
    BEGIN
        PERFORM guardar_mis_categorias(ARRAY[c1]);
        RAISE EXCEPTION 'FALLO: un cliente no debe poder guardar';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-403%' THEN RAISE EXCEPTION 'FALLO 2: %', SQLERRM; END IF;
    END;
    n := n + 1;

    -- Sesión del aliado de T1
    PERFORM set_config('request.jwt.claims', '{"sub":"7e570000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
    PERFORM set_config('request.jwt.claim.sub', '7e570000-0000-4000-8000-0000000000b1', true);

    -- 3. Listar: solo categorías ACTIVAS del propio tenant
    v := listar_categorias_tenant();
    IF jsonb_array_length(v) <> 2
       OR NOT v @> jsonb_build_array(jsonb_build_object('id', c1))
       OR NOT v @> jsonb_build_array(jsonb_build_object('id', c2)) THEN
        RAISE EXCEPTION 'FALLO 3: listado inesperado %', v;
    END IF;
    n := n + 1;

    -- 4. Sin categorías declaradas -> []
    IF obtener_mis_categorias() <> '[]'::jsonb THEN RAISE EXCEPTION 'FALLO 4'; END IF;
    n := n + 1;

    -- 5. Lista vacía -> 422V
    BEGIN
        PERFORM guardar_mis_categorias(ARRAY[]::UUID[]);
        RAISE EXCEPTION 'FALLO: lista vacía aceptada';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-422V%' THEN RAISE EXCEPTION 'FALLO 5: %', SQLERRM; END IF;
    END;
    n := n + 1;

    -- 6. Categoría de otro tenant -> 422C
    BEGIN
        PERFORM guardar_mis_categorias(ARRAY[c9]);
        RAISE EXCEPTION 'FALLO: categoría de otro tenant aceptada';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-422C%' THEN RAISE EXCEPTION 'FALLO 6: %', SQLERRM; END IF;
    END;
    n := n + 1;

    -- 7. Categoría inactiva -> 422C
    BEGIN
        PERFORM guardar_mis_categorias(ARRAY[c3]);
        RAISE EXCEPTION 'FALLO: categoría inactiva aceptada';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-422C%' THEN RAISE EXCEPTION 'FALLO 7: %', SQLERRM; END IF;
    END;
    n := n + 1;

    -- 8. Guardar dos (con un repetido) -> quedan exactamente dos
    v := guardar_mis_categorias(ARRAY[c1, c2, c2]);
    IF jsonb_array_length(v) <> 2 THEN RAISE EXCEPTION 'FALLO 8: %', v; END IF;
    n := n + 1;

    -- 9. Reemplazo: guardar solo c2 quita c1
    v := guardar_mis_categorias(ARRAY[c2]);
    IF v <> jsonb_build_array(c2) OR obtener_mis_categorias() <> jsonb_build_array(c2) THEN
        RAISE EXCEPTION 'FALLO 9: %', v;
    END IF;
    n := n + 1;

    -- 10. Las filas quedan con el tenant del aliado
    IF EXISTS (
        SELECT 1 FROM aliado_categoria
        WHERE aliado_id = '7e570000-0000-4000-8000-0000000000d1'
          AND tenant_id <> '7e570000-0000-4000-8000-0000000000a1'
    ) THEN RAISE EXCEPTION 'FALLO 10: fila con tenant ajeno'; END IF;
    n := n + 1;

    -- 11. El aliado de T2 no ve nada de T1
    PERFORM set_config('request.jwt.claims', '{"sub":"7e570000-0000-4000-8000-0000000000b2","role":"authenticated"}', true);
    PERFORM set_config('request.jwt.claim.sub', '7e570000-0000-4000-8000-0000000000b2', true);
    IF listar_categorias_tenant() <> jsonb_build_array(jsonb_build_object('id', c9, 'nombre', 'TEST Cerrajería'))
       OR obtener_mis_categorias() <> '[]'::jsonb THEN
        RAISE EXCEPTION 'FALLO 11: fuga entre tenants';
    END IF;
    n := n + 1;

    -- 12. El trigger impide mezclar tenants incluso con INSERT directo
    BEGIN
        INSERT INTO aliado_categoria (tenant_id, aliado_id, categoria_id)
        VALUES ('7e570000-0000-4000-8000-0000000000a2', '7e570000-0000-4000-8000-0000000000d2', c1);
        RAISE EXCEPTION 'FALLO: el trigger dejó pasar una categoría de otro tenant';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'MANI-CAT-422C%' THEN RAISE EXCEPTION 'FALLO 12: %', SQLERRM; END IF;
    END;
    n := n + 1;

    RAISE NOTICE 'OK: % pruebas de categorías del aliado', n;
END $$;

ROLLBACK;
