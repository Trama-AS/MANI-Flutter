-- =====================================================================
-- MANI — Seed de identidad para la PoC de claims de tenant
-- =====================================================================
-- Ticket: SCRUM-929 (CFG-12) · Subtareas: SCRUM-971, SCRUM-972, SCRUM-973
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: supabase/seed/seed_qa_multitenant.sql (CFG-04) y de que el
--   hook de 10_hook_claims_tenant.sql este aplicado Y registrado en
--   Authentication > Hooks.
--
-- ESTE ARCHIVO ESCRIBE DATOS. Es transaccional: o entra todo, o nada.
--
-- LA IDEA CENTRAL — POR QUE ESTE SEED NO SE PARECE AL DE CFG-04
--
--   El seed de CFG-04 escribe `tenant_id`, `user_role` y `rol` dentro de
--   `auth.users.raw_app_meta_data`. GoTrue copia ese objeto a
--   `app_metadata` del JWT, y por eso hoy el token sale con tenant.
--
--   Medir la propagacion contra esos usuarios NO PRUEBA NADA sobre el
--   mecanismo: el claim estaria ahi con hook o sin hook. Seria comprobar
--   que el seed escribio lo que el seed escribio.
--
--   Los usuarios de este archivo llevan `raw_app_meta_data` con SOLO
--   `provider` y `providers`. Cero claims de tenant. El tenant vive
--   unicamente en `public.usuario`.
--
--   ⇒ Si el JWT sale con `tenant_id`, lo puso el hook. No hay otra via.
--   ⇒ Si se desactiva el hook, estos usuarios deben perder el claim,
--      mientras los de CFG-04 lo conservan. Esa diferencia es el control
--      negativo de la Fase 7, y es lo que convierte el 100% en un
--      resultado con significado (mismo razonamiento que r1 vs r2 en
--      PoC-001).
--
-- DOMINIO DE CORREO PROPIO: `@cfg12.mani.test`
--   CFG-04 es dueño de `@qa.mani.test` y CFG-09 de `@poc.mani.test`, y
--   cada seed borra por ese patron en su limpieza. Un dominio propio
--   mantiene los tres seeds independientes: correr cualquiera de ellos
--   no pisa a los otros.
--
-- UUIDs FIJOS — bloque `c` para no chocar con los seeds existentes
--   CFG-04 usa 30000000-...-0000000000<T><I> y CFG-09 el bloque `9`.
--   Este seed usa el bloque `c`:
--     30000000-0000-4000-8000-c00000000011  hook.t1    (tenant 1)
--     30000000-0000-4000-8000-c00000000021  hook.t2    (tenant 2)
--     30000000-0000-4000-8000-c00000000091  huerfano   (sin tenant)
--     30000000-0000-4000-8000-c00000000092  sin.perfil (sin fila en usuario)
--     a0000000-0000-4000-8000-c00000000011  documento KYC del tenant 1
--     a0000000-0000-4000-8000-c00000000021  documento KYC del tenant 2
--
-- ⚠️ CREDENCIALES
--   Password unico y en claro: QaSeed2026!, igual que los otros dos
--   seeds. Aceptable en un QA desechable sin datos reales. NO reutilizar
--   en produccion.
--
-- COMO SE CORRE
--   SQL Editor del dashboard (corre como `postgres`, que bypassa RLS —
--   correcto para sembrar). Es idempotente: correrlo N veces deja el
--   mismo estado.
-- =====================================================================

BEGIN;

SET LOCAL search_path = public, extensions;

DO $seed$
DECLARE
  v_t1       uuid := '10000000-0000-4000-8000-000000000011';  -- acme-servicios
  v_t2       uuid := '10000000-0000-4000-8000-000000000021';  -- nova-mantenimiento
  v_instance uuid;
  v_hash     text;
  v_prov_id  boolean;
  v_id_uuid  boolean;
  v_aliado1  uuid;
  v_aliado2  uuid;
  v_choque   text;
BEGIN
  -- -----------------------------------------------------------------
  -- PARTE 0 — Guardas
  -- -----------------------------------------------------------------
  IF (SELECT count(*) FROM public.tenant WHERE id IN (v_t1, v_t2)) <> 2 THEN
    RAISE EXCEPTION
      'Faltan los tenants de CFG-04. Corre supabase/seed/seed_qa_multitenant.sql primero.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'Falta la extension pgcrypto (crypt()/gen_salt()).';
  END IF;

  -- El hook debe existir. Que este REGISTRADO en el dashboard no se
  -- puede comprobar desde SQL; eso lo verifica la Fase 3 con un login.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'custom_access_token_hook'
  ) THEN
    RAISE EXCEPTION
      'No existe public.custom_access_token_hook. Corre 10_hook_claims_tenant.sql primero.';
  END IF;

  -- El email es UNIQUE en auth.users. Si alguien creo a mano una cuenta
  -- con nuestros correos pero otro id, la limpieza por patron no la
  -- atrapa y el INSERT chocaria. Preferimos fallar con mensaje claro.
  SELECT string_agg(u.email, ', ') INTO v_choque
    FROM auth.users u
   WHERE u.email LIKE '%@cfg12.mani.test'
     AND u.id NOT IN ('30000000-0000-4000-8000-c00000000011',
                      '30000000-0000-4000-8000-c00000000021',
                      '30000000-0000-4000-8000-c00000000091',
                      '30000000-0000-4000-8000-c00000000092');
  IF v_choque IS NOT NULL THEN
    RAISE EXCEPTION
      'Hay cuentas @cfg12.mani.test con ids distintos a los del seed: %. Revisalas a mano.',
      v_choque;
  END IF;

  -- `min(uuid)` no existe en Postgres, asi que no se puede agregar sobre
  -- instance_id. Se toma el de cualquier usuario existente y, si la tabla
  -- estuviera vacia, el UUID nulo que usa GoTrue por defecto.
  SELECT COALESCE(
           (SELECT u.instance_id FROM auth.users u WHERE u.instance_id IS NOT NULL LIMIT 1),
           '00000000-0000-0000-0000-000000000000')
    INTO v_instance;

  -- -----------------------------------------------------------------
  -- PARTE A — Limpieza, acotada a lo que este seed es dueño
  -- -----------------------------------------------------------------
  -- No toca `@qa.mani.test` (CFG-04) ni `@poc.mani.test` (CFG-09).
  DELETE FROM public.documento_kyc
   WHERE id IN ('a0000000-0000-4000-8000-c00000000011',
                'a0000000-0000-4000-8000-c00000000021');

  DELETE FROM public.usuario
   WHERE email LIKE '%@cfg12.mani.test';

  DELETE FROM auth.identities
   WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@cfg12.mani.test');
  DELETE FROM auth.users WHERE email LIKE '%@cfg12.mani.test';

  -- -----------------------------------------------------------------
  -- PARTE B — Usuarios de Auth SIN claims de tenant
  -- -----------------------------------------------------------------
  v_hash := crypt('QaSeed2026!', gen_salt('bf'));

  -- ⚠️ ESTO ES LO QUE HACE VALIDA LA MEDICION:
  --   raw_app_meta_data solo lleva provider/providers. Comparar con
  --   seed_qa_multitenant.sql, que ahi mismo escribe tenant_id,
  --   user_role y rol. Si a esta linea se le agregan claims de tenant,
  --   la PoC vuelve a medir el seed y el resultado pierde sentido.
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous)
  VALUES
    ('30000000-0000-4000-8000-c00000000011', v_instance, 'authenticated', 'authenticated',
     'hook.t1@cfg12.mani.test', v_hash, now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')),
     jsonb_build_object('nombre','Hook Tenant 1'), now(), now(), false, false),
    ('30000000-0000-4000-8000-c00000000021', v_instance, 'authenticated', 'authenticated',
     'hook.t2@cfg12.mani.test', v_hash, now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')),
     jsonb_build_object('nombre','Hook Tenant 2'), now(), now(), false, false),
    ('30000000-0000-4000-8000-c00000000091', v_instance, 'authenticated', 'authenticated',
     'huerfano@cfg12.mani.test', v_hash, now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')),
     jsonb_build_object('nombre','Usuario sin tenant'), now(), now(), false, false),
    ('30000000-0000-4000-8000-c00000000092', v_instance, 'authenticated', 'authenticated',
     'sin.perfil@cfg12.mani.test', v_hash, now(),
     jsonb_build_object('provider','email','providers',jsonb_build_array('email')),
     jsonb_build_object('nombre','Usuario sin fila en usuario'), now(), now(), false, false);

  -- GoTrue lee las columnas de token como string de Go: en NULL el login
  -- falla con "converting NULL to string is unsupported". Mismo
  -- tratamiento que los seeds de CFG-04 y CFG-09.
  UPDATE auth.users
     SET confirmation_token         = COALESCE(confirmation_token, ''),
         recovery_token             = COALESCE(recovery_token, ''),
         email_change               = COALESCE(email_change, ''),
         email_change_token_new     = COALESCE(email_change_token_new, ''),
         email_change_token_current = COALESCE(email_change_token_current, ''),
         reauthentication_token     = COALESCE(reauthentication_token, ''),
         phone_change               = COALESCE(phone_change, ''),
         phone_change_token         = COALESCE(phone_change_token, '')
   WHERE email LIKE '%@cfg12.mani.test';

  -- auth.identities cambio de forma entre versiones de GoTrue: se
  -- detecta en vez de asumirse (heredado de CFG-09).
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='identities'
                    AND column_name='provider_id') INTO v_prov_id;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='auth' AND table_name='identities'
                    AND column_name='id' AND data_type='uuid') INTO v_id_uuid;

  IF v_prov_id AND v_id_uuid THEN
    INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT gen_random_uuid(), u.id, u.id::text, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u WHERE u.email LIKE '%@cfg12.mani.test';
  ELSIF NOT v_prov_id THEN
    INSERT INTO auth.identities (id, user_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT u.id::text, u.id, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u WHERE u.email LIKE '%@cfg12.mani.test';
  ELSE
    RAISE EXCEPTION 'Forma inesperada de auth.identities (provider_id=%, id uuid=%).',
      v_prov_id, v_id_uuid;
  END IF;

  -- -----------------------------------------------------------------
  -- PARTE C — Filas en public.usuario: aqui SI vive el tenant
  -- -----------------------------------------------------------------
  -- Tres filas para cuatro cuentas. `sin.perfil` no lleva fila a
  -- proposito: es el caso del alta por el flujo real que nunca quedo
  -- vinculada a un tenant, la brecha que ADR-0018 tiene hoy en
  -- produccion. El hook debe resolverlo emitiendo claims nulos, no
  -- reventando.
  INSERT INTO public.usuario (id, tenant_id, email, rol, estado, created_at)
  VALUES
    ('30000000-0000-4000-8000-c00000000011', v_t1,
     'hook.t1@cfg12.mani.test', 'aliado',  'activo', now()),
    ('30000000-0000-4000-8000-c00000000021', v_t2,
     'hook.t2@cfg12.mani.test', 'cliente', 'activo', now()),
    -- tenant_id NULL: el esquema lo admite (la columna es NULLABLE), asi
    -- que este caso borde es un estado que el modelo ya permite, no una
    -- anomalia fabricada para la prueba.
    ('30000000-0000-4000-8000-c00000000091', NULL,
     'huerfano@cfg12.mani.test', 'cliente', 'activo', now());

  -- Roles distintos en t1 y t2 a proposito: `aliado` y `cliente`. Si el
  -- hook copiara un rol fijo o se equivocara de fila, dos usuarios con
  -- el mismo rol no lo delatarian.

  -- -----------------------------------------------------------------
  -- PARTE D — Un documento KYC por tenant
  -- -----------------------------------------------------------------
  -- QUE PRUEBA Y QUE NO:
  --   La verificacion de terreno encontro CERO buckets en Storage, asi
  --   que el caso 6 de ADR-0015 —aislamiento del OBJETO en Storage,
  --   ADR-0013— sigue siendo no ejecutable y se declara asi.
  --
  --   Estas dos filas habilitan lo que si es ejecutable: que la FILA de
  --   `documento_kyc` de un tenant no sea legible por el otro. Es el
  --   caso 1 de ADR-0015 aplicado a la tabla mas sensible del modelo, no
  --   un sustituto del caso 6. El informe debe decirlo con esas palabras.
  --
  --   `ruta_storage` apunta a un objeto que no existe. Es deliberado: si
  --   alguien intenta descargarlo y obtiene 404 en vez de 403, eso mismo
  --   es informacion sobre ADR-0013.
  SELECT a.id INTO v_aliado1 FROM public.aliado a WHERE a.tenant_id = v_t1 LIMIT 1;
  SELECT a.id INTO v_aliado2 FROM public.aliado a WHERE a.tenant_id = v_t2 LIMIT 1;

  IF v_aliado1 IS NULL OR v_aliado2 IS NULL THEN
    RAISE EXCEPTION
      'Falta el aliado de algun tenant de CFG-04. ¿Se corrio seed_qa_multitenant.sql completo?';
  END IF;

  INSERT INTO public.documento_kyc
    (id, tenant_id, aliado_id, tipo_documento, ruta_storage, estado, fecha_carga)
  VALUES
    ('a0000000-0000-4000-8000-c00000000011', v_t1, v_aliado1,
     'cedula', 'kyc/' || v_t1::text || '/cedula-t1.pdf', 'aprobado', now()),
    ('a0000000-0000-4000-8000-c00000000021', v_t2, v_aliado2,
     'cedula', 'kyc/' || v_t2::text || '/cedula-t2.pdf', 'aprobado', now());

  RAISE NOTICE 'Seed de CFG-12 aplicado: 4 cuentas de Auth, 3 filas de usuario, 2 documentos KYC.';
END $seed$;

COMMIT;


-- =====================================================================
-- VERIFICACION POSTERIOR (correr aparte, despues del COMMIT)
-- =====================================================================
-- W1 — Las cuentas existen y NO traen claims de tenant en app_metadata.
--   Esperado: meta_tenant_id y meta_user_role en NULL para las 4, y
--   con_identity = true. Si alguna trajera tenant_id, este seed dejo de
--   servir para su proposito.
--
-- SELECT u.email,
--        u.raw_app_meta_data ->> 'tenant_id' AS meta_tenant_id,
--        u.raw_app_meta_data ->> 'user_role' AS meta_user_role,
--        EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id) AS con_identity
--   FROM auth.users u
--  WHERE u.email LIKE '%@cfg12.mani.test'
--  ORDER BY u.email;
--
-- W2 — El tenant vive solo en public.usuario.
--   Esperado: hook.t1 -> tenant 1 / aliado; hook.t2 -> tenant 2 /
--   cliente; huerfano -> tenant NULL; sin.perfil -> sin fila.
--
-- SELECT a.email, p.tenant_id, p.rol, p.estado, (p.id IS NULL) AS sin_fila_en_usuario
--   FROM auth.users a LEFT JOIN public.usuario p ON p.id = a.id
--  WHERE a.email LIKE '%@cfg12.mani.test'
--  ORDER BY a.email;
--
-- W3 — Lo que el hook produciria para cada cuenta.
--   Esperado: claims poblados para hook.t1 y hook.t2; los tres claims
--   PRESENTES y nulos para huerfano y sin.perfil.
--   Esto simula la logica; el camino real con firma lo mide la Fase 3.
--
-- SELECT u.email,
--        public.custom_access_token_hook(
--          jsonb_build_object('user_id', u.id::text,
--                             'claims', jsonb_build_object('role','authenticated'))
--        ) -> 'claims' -> 'app_metadata' AS claims_del_hook
--   FROM auth.users u
--  WHERE u.email LIKE '%@cfg12.mani.test'
--  ORDER BY u.email;
--
-- W4 — Un documento KYC por tenant, ambos con ruta.
--
-- SELECT d.tenant_id, t.slug, d.tipo_documento, d.ruta_storage
--   FROM public.documento_kyc d JOIN public.tenant t ON t.id = d.tenant_id
--  WHERE d.id IN ('a0000000-0000-4000-8000-c00000000011',
--                 'a0000000-0000-4000-8000-c00000000021')
--  ORDER BY t.slug;


-- =====================================================================
-- REVERSION
-- =====================================================================
-- BEGIN;
--   DELETE FROM public.documento_kyc
--    WHERE id IN ('a0000000-0000-4000-8000-c00000000011',
--                 'a0000000-0000-4000-8000-c00000000021');
--   DELETE FROM public.usuario WHERE email LIKE '%@cfg12.mani.test';
--   DELETE FROM auth.identities
--    WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@cfg12.mani.test');
--   DELETE FROM auth.users WHERE email LIKE '%@cfg12.mani.test';
-- COMMIT;
