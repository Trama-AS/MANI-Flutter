-- =====================================================================
-- MANI — Seed de datos multi-tenant para QA
-- =====================================================================
-- Ticket: SCRUM-921 (CFG-04) · Subtareas: SCRUM-1001..SCRUM-1006
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Esquema de referencia: Product/DDL_MANI.sql de Trama-AS/MANI-docs
--
-- Verificado contra QA el 2026-09-21 (bloque 0 de verificar_aislamiento.sql):
--   * auth.identities trae provider_id NOT NULL e id uuid -> rama moderna.
--   * auth.users: todas las columnas usadas aqui existen.
--   * zona estaba VACIA (0 activas): las 3 zonas de este seed son las
--     primeras del ambiente. SCRUM-1002 queda respondido con eso.
--
-- QUE HACE
--   Deja QA con 2 tenants completos y aislados entre si, cada uno con:
--   admin_tenant + cliente + aliado aprobado + categoria activa + sitio +
--   vinculo aliado-categoria + cobertura. Mas los 6 usuarios de Supabase
--   Auth correspondientes, para poder probar RLS con una sesion real y no
--   solo con el bypass de service_role.
--
-- COMO SE CORRE
--   SQL Editor del dashboard de Supabase (corre como `postgres`, que
--   bypassa RLS — es lo correcto para sembrar). Pegar el archivo entero y
--   ejecutar. Es transaccional: o entra todo, o no entra nada.
--
-- IDEMPOTENCIA (SCRUM-1003)
--   Limpieza controlada + UUIDs fijos. Correrlo N veces deja exactamente
--   el mismo estado. Verificar con supabase/seed/verificar_aislamiento.sql.
--
-- ⚠️ ADVERTENCIA — LO QUE BORRA
--   La Parte A borra TODA fila que cuelgue de los 2 tenants seed, no solo
--   las que creo este script. Si alguien creo solicitudes, cotizaciones o
--   mensajes de prueba bajo esos tenants, se pierden. Es intencional: los
--   tenants seed son propiedad de este script. NO toca otros tenants, y
--   NO toca `zona` (es catalogo global compartido).
--
-- ⚠️ CREDENCIALES
--   El password de los 6 usuarios es fijo y esta en claro mas abajo. Es
--   aceptable porque son usuarios desechables de un ambiente QA sin datos
--   reales. NO reutilizar este archivo ni este password en produccion.
--
-- UUIDs FIJOS — convencion <E>0000000-0000-4000-8000-0000000000<T><I>
--   E = entidad · T = tenant (1/2, 0 = global) · I = indice
--   E: 1 tenant · 2 zona · 3 usuario · 4 cliente · 5 aliado
--      6 categoria · 7 sitio · 8 aliado_categoria · 9 cobertura
--   Son fijos a proposito: la coleccion Postman de ADR-0015 y las pruebas
--   manuales del DoR pueden citarlos directamente.
--
--   TENANTS
--     10000000-0000-4000-8000-000000000011  acme-servicios      (Tenant 1)
--     10000000-0000-4000-8000-000000000021  nova-mantenimiento  (Tenant 2)
--   ZONAS (globales, compartidas por ambos tenants)
--     20000000-0000-4000-8000-000000000001  Bogota    (ciudad)
--     20000000-0000-4000-8000-000000000002  Chapinero (localidad)
--     20000000-0000-4000-8000-000000000003  Suba      (localidad)
--   USUARIOS  (usuario.id == auth.users.id)
--     30000000-0000-4000-8000-0000000000{11,12,13}  T1 admin/cliente/aliado
--     30000000-0000-4000-8000-0000000000{21,22,23}  T2 admin/cliente/aliado
--   CUENTAS
--     admin.t1@qa.mani.test  cliente.t1@qa.mani.test  aliado.t1@qa.mani.test
--     admin.t2@qa.mani.test  cliente.t2@qa.mani.test  aliado.t2@qa.mani.test
--     password (los 6): QaSeed2026!
--
-- DECISIONES DE DISENO
--   * Ambos tenants comparten la zona Chapinero A PROPOSITO. Si el
--     aislamiento se rompe, se ve de inmediato: una consulta de cobertura
--     del Tenant 1 devolveria al aliado del Tenant 2. Separarlos por zona
--     esconderia el bug detras de un filtro geografico.
--   * Cada aliado cubre la misma zona que el sitio de SU cliente, para que
--     el despacho (ADR-0016) haga match dentro del tenant.
--   * `app_metadata` lleva `tenant_id`, `user_role` Y `rol`. ADR-0018 y la
--     politica kyc_isolation leen `user_role`; el comentario del DDL dice
--     `rol`. Escribir ambas cuesta una linea y evita fallos silenciosos.
--   * `usuario.id = auth.users.id`. El esquema no tiene columna que una las
--     dos tablas, y kyc_isolation compara contra auth.uid(). Sin esta
--     convencion el seed no sirve para probar RLS con sesion real.
-- =====================================================================

BEGIN;

-- pgcrypto vive en el esquema `extensions` en Supabase: lo agregamos al
-- search_path para que crypt()/gen_salt() resuelvan sin calificar.
-- `public` va primero para que las tablas del modelo resuelvan normal.
SET LOCAL search_path = public, extensions;

-- ---------------------------------------------------------------------
-- PARTE 0 — Guardas
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_faltantes text;
BEGIN
  SELECT string_agg(t, ', ')
    INTO v_faltantes
    FROM unnest(ARRAY[
      'tenant','zona','usuario','cliente','aliado',
      'categoria_servicio','sitio','aliado_categoria','cobertura_aliado'
    ]) AS t
   WHERE to_regclass('public.' || t) IS NULL;

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Faltan tablas en el esquema: %. Aplica Product/DDL_MANI.sql antes de sembrar.',
      v_faltantes;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION
      'Falta la extension pgcrypto (necesaria para crypt()/gen_salt()). Habilitala en Database > Extensions.';
  END IF;

  -- Colisiones que la limpieza por UUID NO puede resolver: si alguien creo
  -- a mano un tenant con nuestro slug pero otro id, el INSERT chocaria
  -- contra el UNIQUE de `slug` y ON CONFLICT (id) no lo atrapa. Preferimos
  -- fallar con un mensaje claro antes que borrar algo que no es nuestro.
  SELECT string_agg(slug, ', ')
    INTO v_faltantes
    FROM tenant
   WHERE slug IN ('acme-servicios', 'nova-mantenimiento')
     AND id NOT IN ('10000000-0000-4000-8000-000000000011',
                    '10000000-0000-4000-8000-000000000021');

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) tenant(s) con slug % pero con otro id. Borralos a mano o cambia los slugs del seed.',
      v_faltantes;
  END IF;

  -- Mismo caso para auth.users: el email es UNIQUE ahi.
  SELECT string_agg(email, ', ')
    INTO v_faltantes
    FROM auth.users
   WHERE email LIKE '%@qa.mani.test'
     AND id NOT IN ('30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
                    '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023');

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) usuario(s) de Auth con email % pero con otro id. Borralos desde Authentication > Users antes de sembrar.',
      v_faltantes;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- PARTE A — Limpieza controlada (orden inverso de FK)
-- ---------------------------------------------------------------------
-- Barre TODAS las tablas tenant-scoped, no solo las 9 del ticket: si algo
-- en solicitud/cotizacion/evento apunta a una fila seed, un DELETE parcial
-- revienta por FK.

DELETE FROM calificacion      WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM mensaje           WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM notificacion      WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM evento_servicio   WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM cotizacion        WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM solicitud         WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM cobertura_aliado  WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM aliado_categoria  WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM tarifa_referencia WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM documento_kyc     WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM sitio             WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM categoria_servicio WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM aliado            WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM cliente           WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM usuario           WHERE tenant_id IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');
DELETE FROM tenant            WHERE id        IN ('10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000021');

-- Usuarios de Auth, por UUID fijo. identities primero (FK a users).
DELETE FROM auth.identities WHERE user_id IN (
  '30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
  '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023'
);
DELETE FROM auth.users WHERE id IN (
  '30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
  '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023'
);

-- `zona` NO se borra nunca: es catalogo global y otros tenants dependen de el.

-- ---------------------------------------------------------------------
-- PARTE B.1 — Usuarios de Supabase Auth
-- ---------------------------------------------------------------------
-- Columnas verificadas contra el esquema real de auth.users de este
-- proyecto. `aud`/`role` son los valores estandar de un usuario final
-- autenticado. `is_sso_user`/`is_anonymous` son NOT NULL: van explicitos
-- para no depender de que el DEFAULT exista. Las columnas generadas
-- (`confirmed_at`) no se tocan.

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
VALUES
  -- Tenant 1 — acme-servicios
  ('30000000-0000-4000-8000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'admin.t1@qa.mani.test',   crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000011","user_role":"admin_tenant","rol":"admin_tenant"}'::jsonb,
   '{"nombre":"Admin QA Tenant 1"}'::jsonb, now(), now(), false, false),

  ('30000000-0000-4000-8000-000000000012', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'cliente.t1@qa.mani.test', crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000011","user_role":"cliente","rol":"cliente"}'::jsonb,
   '{"nombre":"Cliente QA Tenant 1"}'::jsonb, now(), now(), false, false),

  ('30000000-0000-4000-8000-000000000013', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'aliado.t1@qa.mani.test',  crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000011","user_role":"aliado","rol":"aliado"}'::jsonb,
   '{"nombre":"Aliado QA Tenant 1"}'::jsonb, now(), now(), false, false),

  -- Tenant 2 — nova-mantenimiento
  ('30000000-0000-4000-8000-000000000021', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'admin.t2@qa.mani.test',   crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000021","user_role":"admin_tenant","rol":"admin_tenant"}'::jsonb,
   '{"nombre":"Admin QA Tenant 2"}'::jsonb, now(), now(), false, false),

  ('30000000-0000-4000-8000-000000000022', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'cliente.t2@qa.mani.test', crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000021","user_role":"cliente","rol":"cliente"}'::jsonb,
   '{"nombre":"Cliente QA Tenant 2"}'::jsonb, now(), now(), false, false),

  ('30000000-0000-4000-8000-000000000023', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'aliado.t2@qa.mani.test',  crypt('QaSeed2026!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"10000000-0000-4000-8000-000000000021","user_role":"aliado","rol":"aliado"}'::jsonb,
   '{"nombre":"Aliado QA Tenant 2"}'::jsonb, now(), now(), false, false);

-- GoTrue lee varias columnas de token como string de Go, no como puntero:
-- si quedan en NULL, el login falla con "converting NULL to string is
-- unsupported". Cadena vacia es lo que escribe el propio servicio cuando
-- no hay un flujo de confirmacion/recuperacion en curso. Sin esto los 6
-- usuarios existen pero no pueden iniciar sesion, que es justo para lo que
-- los necesitamos (CFG-12 y la suite de ADR-0015).
UPDATE auth.users
   SET confirmation_token         = COALESCE(confirmation_token, ''),
       recovery_token             = COALESCE(recovery_token, ''),
       email_change               = COALESCE(email_change, ''),
       email_change_token_new     = COALESCE(email_change_token_new, ''),
       email_change_token_current = COALESCE(email_change_token_current, ''),
       reauthentication_token     = COALESCE(reauthentication_token, ''),
       phone_change               = COALESCE(phone_change, ''),
       phone_change_token         = COALESCE(phone_change_token, '')
 WHERE id IN ('30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
              '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023');

-- auth.identities: su forma cambio entre versiones de GoTrue (la columna
-- `provider_id` se agrego despues, y `id` paso de text a uuid). Detectamos
-- la forma real en vez de asumirla — un INSERT fijo aqui es la causa mas
-- comun de que un seed de Auth reviente al cambiar de proyecto.
-- PL/pgSQL solo planifica la rama que ejecuta, asi que la rama que no
-- aplica nunca se valida contra columnas inexistentes.
DO $$
DECLARE
  v_tiene_provider_id boolean;
  v_id_es_uuid        boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'auth' AND table_name = 'identities'
       AND column_name = 'provider_id'
  ) INTO v_tiene_provider_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'auth' AND table_name = 'identities'
       AND column_name = 'id' AND data_type = 'uuid'
  ) INTO v_id_es_uuid;

  IF v_tiene_provider_id AND v_id_es_uuid THEN
    -- GoTrue actual: id uuid propio + provider_id NOT NULL
    INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT gen_random_uuid(), u.id, u.id::text, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u
     WHERE u.id IN ('30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
                    '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023');

  ELSIF NOT v_tiene_provider_id THEN
    -- GoTrue legacy: id text = el sub del proveedor, sin provider_id
    INSERT INTO auth.identities (id, user_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT u.id::text, u.id, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u
     WHERE u.id IN ('30000000-0000-4000-8000-000000000011','30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000013',
                    '30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022','30000000-0000-4000-8000-000000000023');

  ELSE
    RAISE EXCEPTION
      'Forma inesperada de auth.identities (provider_id=%, id uuid=%). Revisar columnas y ajustar este bloque.',
      v_tiene_provider_id, v_id_es_uuid;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- PARTE B.2 — Datos de dominio (orden de FK)
-- ---------------------------------------------------------------------
-- ON CONFLICT (id) DO NOTHING en todo: red de seguridad ademas del DELETE
-- de la Parte A, por si el script se interrumpe a medias.

-- 1. tenant
INSERT INTO tenant (id, nombre, slug, estado) VALUES
  ('10000000-0000-4000-8000-000000000011', 'ACME Servicios',      'acme-servicios',     'activo'),
  ('10000000-0000-4000-8000-000000000021', 'Nova Mantenimiento',  'nova-mantenimiento', 'activo')
ON CONFLICT (id) DO NOTHING;

-- 2. zona (global — compartida por ambos tenants, jamas se borra)
INSERT INTO zona (id, nivel, nombre, zona_padre_id, estado) VALUES
  ('20000000-0000-4000-8000-000000000001', 'ciudad',    'Bogota',    NULL,                                   'activa'),
  ('20000000-0000-4000-8000-000000000002', 'localidad', 'Chapinero', '20000000-0000-4000-8000-000000000001', 'activa'),
  ('20000000-0000-4000-8000-000000000003', 'localidad', 'Suba',      '20000000-0000-4000-8000-000000000001', 'activa')
ON CONFLICT (id) DO NOTHING;

-- 3. usuario (id == auth.users.id)
INSERT INTO usuario (id, tenant_id, email, rol, estado) VALUES
  ('30000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', 'admin.t1@qa.mani.test',   'admin_tenant', 'activo'),
  ('30000000-0000-4000-8000-000000000012', '10000000-0000-4000-8000-000000000011', 'cliente.t1@qa.mani.test', 'cliente',      'activo'),
  ('30000000-0000-4000-8000-000000000013', '10000000-0000-4000-8000-000000000011', 'aliado.t1@qa.mani.test',  'aliado',       'activo'),
  ('30000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', 'admin.t2@qa.mani.test',   'admin_tenant', 'activo'),
  ('30000000-0000-4000-8000-000000000022', '10000000-0000-4000-8000-000000000021', 'cliente.t2@qa.mani.test', 'cliente',      'activo'),
  ('30000000-0000-4000-8000-000000000023', '10000000-0000-4000-8000-000000000021', 'aliado.t2@qa.mani.test',  'aliado',       'activo')
ON CONFLICT (id) DO NOTHING;

-- 4. cliente
INSERT INTO cliente (id, tenant_id, usuario_id, tipo) VALUES
  ('40000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', '30000000-0000-4000-8000-000000000012', 'persona_natural'),
  ('40000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000000022', 'empresa')
ON CONFLICT (id) DO NOTHING;

-- 5. aliado — 'aprobado' obligatorio: en 'pendiente' no puede operar
INSERT INTO aliado (id, tenant_id, usuario_id, tipo, nombre_razon_social, estado_verificacion) VALUES
  ('50000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', '30000000-0000-4000-8000-000000000013', 'persona_natural', 'Aliado QA Tenant 1',      'aprobado'),
  ('50000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000000023', 'empresa',         'Aliado QA Tenant 2 SAS',  'aprobado')
ON CONFLICT (id) DO NOTHING;

-- 6. categoria_servicio — al menos 1 activa por tenant
INSERT INTO categoria_servicio (id, tenant_id, nombre, estado, flujo_operativo) VALUES
  ('60000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', 'Plomeria',     'activa', NULL),
  ('60000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', 'Electricidad', 'activa', NULL)
ON CONFLICT (id) DO NOTHING;

-- 7. sitio — zona_id obligatoria; ambos en Chapinero (ver decisiones de diseno)
INSERT INTO sitio (id, tenant_id, cliente_id, zona_id, direccion, reglas) VALUES
  ('70000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-000000000002', 'Calle 72 #10-34, Chapinero', '{"horario_acceso":"08:00-18:00"}'::jsonb),
  ('70000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', '40000000-0000-4000-8000-000000000021', '20000000-0000-4000-8000-000000000002', 'Carrera 13 #63-21, Chapinero', '{"horario_acceso":"09:00-17:00"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- 8. aliado_categoria
INSERT INTO aliado_categoria (id, tenant_id, aliado_id, categoria_id) VALUES
  ('80000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000000011', '60000000-0000-4000-8000-000000000011'),
  ('80000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000000021', '60000000-0000-4000-8000-000000000021')
ON CONFLICT (id) DO NOTHING;

-- 9. cobertura_aliado — misma zona que el sitio del cliente del mismo
--    tenant, si no el despacho nunca hace match
INSERT INTO cobertura_aliado (id, tenant_id, aliado_id, zona_id) VALUES
  ('90000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-000000000002'),
  ('90000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000000021', '20000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- Siguiente paso: correr supabase/seed/verificar_aislamiento.sql y adjuntar
-- la salida a SCRUM-1004 como checklist de cierre.
