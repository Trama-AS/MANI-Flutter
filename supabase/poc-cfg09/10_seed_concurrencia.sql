-- =====================================================================
-- MANI — Seed de concurrencia para la PoC de exclusion concurrente
-- =====================================================================
-- Ticket: SCRUM-926 (CFG-09) · Subtarea: SCRUM-961 (insumo del harness)
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Complementa (NO reemplaza): supabase/seed/seed_qa_multitenant.sql (CFG-04)
-- Terreno verificado: supabase/poc-cfg09/00_verificar_terreno.sql, 2026-09-21
--
-- ⚠️ ESTE SCRIPT ESCRIBE. Todo lo anterior de CFG-09 era de solo lectura.
--    Es transaccional: o entra todo, o no entra nada.
--
-- QUE HACE
--   Crea un TERCER tenant desechable, `poc-concurrencia`, con:
--     * N aliados aprobados (N configurable abajo), todos en la misma zona
--       y la misma categoria, cada uno con su usuario de Supabase Auth
--     * 1 cliente con su sitio
--     * 1 solicitud en estado 'PENDIENTE' con UUID fijo
--   Los N aliados compiten por ESA solicitud. Es la poblacion minima para
--   que la pregunta de la PoC tenga sentido: con 1 aliado no hay carrera.
--
-- POR QUE UN TENANT APARTE
--   El seed de CFG-04 deja exactamente 1 aliado por tenant, y la suite de
--   aislamiento de ADR-0015 y CFG-12 cuentan con ese numero. Meter 50
--   aliados en `acme-servicios` romperia sus aserciones. Este tenant es
--   propiedad de CFG-09 y se puede borrar entero sin consecuencias.
--
-- ⚠️ LO QUE BORRA
--   Solo lo que cuelga del tenant `poc-concurrencia` y los usuarios de
--   Auth con dominio @poc.mani.test. NO toca los 2 tenants de CFG-04, NO
--   toca `zona` (catalogo global compartido).
--
-- ⚠️ CREDENCIALES
--   Password fijo y en claro, igual que el seed de CFG-04: usuarios
--   desechables de un ambiente QA sin datos reales. NO reutilizar en
--   produccion.
--
-- DERIVA QUE ESTE SCRIPT ABSORBE (ver informe de SCRUM-959)
--   D1: `solicitud.estado` NO tiene DEFAULT en QA aunque el DDL lo declare,
--       asi que el INSERT escribe 'PENDIENTE' de forma explicita.
--   D2: tampoco hay CHECK sobre `estado`, asi que nada en la base valida
--       el vocabulario — el valor correcto es responsabilidad del script.
--
-- UUIDs FIJOS — convencion derivada de la de CFG-04
--   Prefijo de entidad + relleno con `9` (tenant PoC) + indice del aliado.
--     1…-900000000001  tenant poc-concurrencia
--     3…-900000000000  usuario del cliente     · 3…-9<i>  usuario aliado i
--     4…-900000000000  cliente                 · 5…-9<i>  aliado i
--     6…-900000000000  categoria               · 8…-9<i>  aliado_categoria i
--     7…-900000000000  sitio                   · 9…-9<i>  cobertura i
--     a…-900000000001  LA SOLICITUD EN DISPUTA  ← la que usa el harness
--   Zona: se REUSA Chapinero (20000000-0000-4000-8000-000000000002) del
--   seed de CFG-04, porque `zona` es catalogo global y no se duplica.
--
--   CUENTAS  cliente.poc@poc.mani.test · aliado.poc.<i>@poc.mani.test
--   PASSWORD (todas): QaSeed2026!
-- =====================================================================

BEGIN;

-- pgcrypto vive en el esquema `extensions` en Supabase (verificado: 1.3).
SET LOCAL search_path = public, extensions;

DO $$
DECLARE
  -- ---------------------------------------------------------------
  -- N — cuantos aliados compiten. Cambiar SOLO aqui.
  -- Verificado en QA: max_connections = 60. Por encima de eso el motor
  -- no puede darte transacciones realmente solapadas, y el pool de
  -- PostgREST esta aun mas abajo. N mayor no es mas concurrencia: es
  -- mas cola. Sembrar 50 y variar la carga desde k6.
  -- ---------------------------------------------------------------
  v_n        constant int  := 50;

  v_tenant   constant uuid := '10000000-0000-4000-8000-900000000001';
  v_zona     constant uuid := '20000000-0000-4000-8000-000000000002'; -- Chapinero, global
  v_usr_cli  constant uuid := '30000000-0000-4000-8000-900000000000';
  v_cliente  constant uuid := '40000000-0000-4000-8000-900000000000';
  v_categoria constant uuid := '60000000-0000-4000-8000-900000000000';
  v_sitio    constant uuid := '70000000-0000-4000-8000-900000000000';
  v_solicitud constant uuid := 'a0000000-0000-4000-8000-900000000001';
  v_instance constant uuid := '00000000-0000-0000-0000-000000000000';

  v_hash     text;
  v_faltante text;
  v_tiene_provider_id boolean;
  v_id_es_uuid        boolean;
BEGIN
  -- -----------------------------------------------------------------
  -- PARTE 0 — Guardas
  -- -----------------------------------------------------------------
  SELECT string_agg(t, ', ')
    INTO v_faltante
    FROM unnest(ARRAY['tenant','zona','usuario','cliente','aliado',
                      'categoria_servicio','sitio','aliado_categoria',
                      'cobertura_aliado','solicitud']) AS t
   WHERE to_regclass('public.' || t) IS NULL;
  IF v_faltante IS NOT NULL THEN
    RAISE EXCEPTION 'Faltan tablas en el esquema: %.', v_faltante;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'Falta la extension pgcrypto (crypt()/gen_salt()).';
  END IF;

  -- La zona es del catalogo global: este script la USA, no la crea. Si no
  -- existe, corre antes el seed de CFG-04.
  IF NOT EXISTS (SELECT 1 FROM zona WHERE id = v_zona) THEN
    RAISE EXCEPTION
      'No existe la zona Chapinero (%). Corre supabase/seed/seed_qa_multitenant.sql primero.',
      v_zona;
  END IF;

  -- Colision de slug con otro id: ON CONFLICT (id) no la atrapa.
  IF EXISTS (SELECT 1 FROM tenant
              WHERE slug = 'poc-concurrencia' AND id <> v_tenant) THEN
    RAISE EXCEPTION
      'Ya existe un tenant con slug poc-concurrencia y otro id. Borralo a mano.';
  END IF;

  -- Mismo caso para auth.users: el email es UNIQUE.
  SELECT string_agg(email, ', ') INTO v_faltante
    FROM auth.users
   WHERE email LIKE '%@poc.mani.test'
     AND id <> v_usr_cli
     AND id NOT IN (SELECT ('30000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid
                      FROM generate_series(1, v_n) AS i);
  IF v_faltante IS NOT NULL THEN
    RAISE EXCEPTION
      'Usuario(s) de Auth con dominio @poc.mani.test fuera de la convencion: %. Borralos desde Authentication > Users.',
      v_faltante;
  END IF;

  -- -----------------------------------------------------------------
  -- PARTE A — Limpieza controlada (orden inverso de FK)
  -- -----------------------------------------------------------------
  DELETE FROM calificacion      WHERE tenant_id = v_tenant;
  DELETE FROM mensaje           WHERE tenant_id = v_tenant;
  DELETE FROM notificacion      WHERE tenant_id = v_tenant;
  DELETE FROM evento_servicio   WHERE tenant_id = v_tenant;
  DELETE FROM cotizacion        WHERE tenant_id = v_tenant;
  DELETE FROM solicitud         WHERE tenant_id = v_tenant;
  DELETE FROM cobertura_aliado  WHERE tenant_id = v_tenant;
  DELETE FROM aliado_categoria  WHERE tenant_id = v_tenant;
  DELETE FROM tarifa_referencia WHERE tenant_id = v_tenant;
  DELETE FROM documento_kyc     WHERE tenant_id = v_tenant;
  DELETE FROM sitio             WHERE tenant_id = v_tenant;
  DELETE FROM categoria_servicio WHERE tenant_id = v_tenant;
  DELETE FROM aliado            WHERE tenant_id = v_tenant;
  DELETE FROM cliente           WHERE tenant_id = v_tenant;
  DELETE FROM usuario           WHERE tenant_id = v_tenant;
  DELETE FROM tenant            WHERE id        = v_tenant;

  DELETE FROM auth.identities
   WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@poc.mani.test');
  DELETE FROM auth.users WHERE email LIKE '%@poc.mani.test';

  -- -----------------------------------------------------------------
  -- PARTE B — Usuarios de Supabase Auth
  -- -----------------------------------------------------------------
  -- Un solo hash para todas las cuentas: bcrypt por fila multiplicaria el
  -- costo por N sin ganar nada en un ambiente desechable.
  v_hash := crypt('QaSeed2026!', gen_salt('bf'));

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous)
  VALUES (
    v_usr_cli, v_instance, 'authenticated', 'authenticated',
    'cliente.poc@poc.mani.test', v_hash, now(),
    jsonb_build_object('provider','email','providers',jsonb_build_array('email'),
                       'tenant_id', v_tenant::text, 'user_role','cliente','rol','cliente'),
    jsonb_build_object('nombre','Cliente PoC'), now(), now(), false, false);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous)
  SELECT ('30000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_instance, 'authenticated', 'authenticated',
         'aliado.poc.' || i || '@poc.mani.test', v_hash, now(),
         jsonb_build_object('provider','email','providers',jsonb_build_array('email'),
                            'tenant_id', v_tenant::text, 'user_role','aliado','rol','aliado'),
         jsonb_build_object('nombre','Aliado PoC ' || i), now(), now(), false, false
    FROM generate_series(1, v_n) AS i;

  -- GoTrue lee las columnas de token como string de Go: en NULL el login
  -- falla con "converting NULL to string is unsupported". Sin esto los
  -- usuarios existen pero no pueden autenticarse, que es justo lo que el
  -- harness necesita (mismo tratamiento que el seed de CFG-04).
  UPDATE auth.users
     SET confirmation_token         = COALESCE(confirmation_token, ''),
         recovery_token             = COALESCE(recovery_token, ''),
         email_change               = COALESCE(email_change, ''),
         email_change_token_new     = COALESCE(email_change_token_new, ''),
         email_change_token_current = COALESCE(email_change_token_current, ''),
         reauthentication_token     = COALESCE(reauthentication_token, ''),
         phone_change               = COALESCE(phone_change, ''),
         phone_change_token         = COALESCE(phone_change_token, '')
   WHERE email LIKE '%@poc.mani.test';

  -- auth.identities cambio de forma entre versiones de GoTrue. Se detecta
  -- en vez de asumirse: un INSERT fijo aqui es la causa mas comun de que
  -- un seed de Auth reviente al cambiar de proyecto.
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='identities'
                    AND column_name='provider_id') INTO v_tiene_provider_id;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='identities'
                    AND column_name='id' AND data_type='uuid') INTO v_id_es_uuid;

  IF v_tiene_provider_id AND v_id_es_uuid THEN
    INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT gen_random_uuid(), u.id, u.id::text, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u WHERE u.email LIKE '%@poc.mani.test';
  ELSIF NOT v_tiene_provider_id THEN
    INSERT INTO auth.identities (id, user_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT u.id::text, u.id, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u WHERE u.email LIKE '%@poc.mani.test';
  ELSE
    RAISE EXCEPTION 'Forma inesperada de auth.identities (provider_id=%, id uuid=%).',
      v_tiene_provider_id, v_id_es_uuid;
  END IF;

  -- -----------------------------------------------------------------
  -- PARTE C — Datos de dominio (orden de FK)
  -- -----------------------------------------------------------------
  INSERT INTO tenant (id, nombre, slug, estado)
  VALUES (v_tenant, 'PoC Concurrencia CFG-09', 'poc-concurrencia', 'ACTIVO');

  INSERT INTO usuario (id, tenant_id, email, rol, estado)
  VALUES (v_usr_cli, v_tenant, 'cliente.poc@poc.mani.test', 'CLIENTE', 'ACTIVO');

  INSERT INTO usuario (id, tenant_id, email, rol, estado)
  SELECT ('30000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_tenant, 'aliado.poc.' || i || '@poc.mani.test', 'ALIADO', 'ACTIVO'
    FROM generate_series(1, v_n) AS i;

  INSERT INTO cliente (id, tenant_id, usuario_id, tipo)
  VALUES (v_cliente, v_tenant, v_usr_cli, 'PERSONA_NATURAL');

  -- 'VERIFICADO' es obligatorio: un aliado 'PENDIENTE' no puede operar y no
  -- deberia entrar a la carrera.
  INSERT INTO aliado (id, tenant_id, usuario_id, tipo, nombre_razon_social, estado_verificacion)
  SELECT ('50000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_tenant,
         ('30000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         'PERSONA_NATURAL', 'Aliado PoC ' || i, 'VERIFICADO'
    FROM generate_series(1, v_n) AS i;

  INSERT INTO categoria_servicio (id, tenant_id, nombre, estado, flujo_operativo)
  VALUES (v_categoria, v_tenant, 'Plomeria PoC', 'ACTIVO', NULL);

  INSERT INTO sitio (id, tenant_id, cliente_id, zona_id, direccion, reglas)
  VALUES (v_sitio, v_tenant, v_cliente, v_zona,
          'Calle 72 #10-34, Chapinero (PoC CFG-09)', NULL);

  -- Los N aliados comparten categoria Y zona con el sitio: si no, el
  -- despacho de ADR-0016 no los considerarian validos y la carrera seria
  -- artificial.
  INSERT INTO aliado_categoria (id, tenant_id, aliado_id, categoria_id)
  SELECT ('80000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_tenant,
         ('50000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_categoria
    FROM generate_series(1, v_n) AS i;

  INSERT INTO cobertura_aliado (id, tenant_id, aliado_id, zona_id)
  SELECT ('90000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_tenant,
         ('50000000-0000-4000-8000-9' || lpad(i::text, 11, '0'))::uuid,
         v_zona
    FROM generate_series(1, v_n) AS i;

  -- LA solicitud en disputa. `estado` explicito por la deriva D1 (QA no
  -- tiene DEFAULT) y `aliado_id` nulo: es lo que el UPDATE condicional de
  -- ADR-0021 debe llenar exactamente una vez.
  INSERT INTO solicitud (id, tenant_id, cliente_id, sitio_id, categoria_id,
                         zona_id, aliado_id, estado)
  VALUES (v_solicitud, v_tenant, v_cliente, v_sitio, v_categoria,
          v_zona, NULL, 'PENDIENTE');

  RAISE NOTICE 'Seed PoC listo: % aliados aprobados compiten por la solicitud %',
    v_n, v_solicitud;
END $$;

COMMIT;

-- =====================================================================
-- VERIFICACION (solo lectura — correr despues del COMMIT)
-- =====================================================================
-- Esperado: aliados_aprobados = N, solicitudes_pending = 1, aliado_id NULL,
-- y cobertura/categoria = N. Si aliados_listos < aliados_aprobados, algun
-- aliado no cubre la zona o la categoria del sitio y no deberia competir.
SELECT t.slug,
       (SELECT count(*) FROM aliado a
         WHERE a.tenant_id = t.id AND a.estado_verificacion = 'VERIFICADO') AS aliados_aprobados,
       (SELECT count(*) FROM aliado a
          JOIN cobertura_aliado ca ON ca.aliado_id = a.id AND ca.zona_id = s.zona_id
          JOIN aliado_categoria ac ON ac.aliado_id = a.id AND ac.categoria_id = s.categoria_id
         WHERE a.tenant_id = t.id AND a.estado_verificacion = 'VERIFICADO')  AS aliados_listos,
       s.id AS solicitud, s.estado, s.aliado_id
  FROM tenant t
  JOIN solicitud s ON s.tenant_id = t.id
 WHERE t.slug = 'poc-concurrencia';

-- Los usuarios de Auth deben poder autenticarse: sin identity, el login
-- por password falla y el harness no consigue JWT.
SELECT count(*) AS cuentas_auth,
       count(*) FILTER (WHERE email_confirmed_at IS NOT NULL) AS confirmadas,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM auth.identities i WHERE i.user_id = u.id)) AS con_identity
  FROM auth.users u WHERE u.email LIKE '%@poc.mani.test';
