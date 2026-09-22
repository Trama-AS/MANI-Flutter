-- =====================================================================
-- MANI — Custom Access Token Hook: propagacion de tenant y rol al JWT
-- =====================================================================
-- Ticket: SCRUM-929 (CFG-12) · Cierra SCRUM-971
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Depende de: la verificacion de terreno de SCRUM-971
--   (Entregas/PoC/SCRUM-971-verificacion-terreno.md en Trama-AS/MANI-docs)
--
-- ESTE ARCHIVO ESCRIBE ESQUEMA. Es transaccional: o entra todo, o nada.
--
-- QUE HACE
--   Implementa el mecanismo que ADR-0018 decidio pero que nadie habia
--   construido: al emitir un token, GoTrue llama a esta funcion, que
--   resuelve el tenant y el rol del usuario desde `public.usuario` y los
--   inyecta en `claims.app_metadata`.
--
-- POR QUE HACE FALTA
--   Hoy el `tenant_id` llega al JWT solo porque el seed de CFG-04 lo
--   escribe a mano en `auth.users.raw_app_meta_data`. No hay hook ni
--   trigger: un usuario dado de alta por el flujo real de registro
--   saldria SIN tenant, y contra las politicas de ADR-0018 no veria
--   absolutamente nada.
--
--   Medir la propagacion sobre usuarios que nosotros mismos sembramos
--   con los claims correctos mide el seed, no el mecanismo. Por eso el
--   seed de la Fase 2 crea usuarios con `raw_app_meta_data` vacio de
--   claims de tenant: si el JWT sale con `tenant_id`, lo puso este hook.
--
-- ⚠️ PASO MANUAL OBLIGATORIO DESPUES DE CORRER ESTE ARCHIVO
--   Registrar el hook en el dashboard:
--     Authentication > Hooks > Customize Access Token > Postgres >
--     public.custom_access_token_hook > Enable
--   No es SQL. Sin ese paso la funcion existe y nunca se invoca, y las
--   pruebas de la Fase 3 darian rojo por una razon que no es el codigo.
--
-- COMO SE REVIERTE
--   Desactivar el hook en el dashboard (eso solo ya lo deja inerte) y,
--   si se quiere limpiar del todo, correr el bloque de reversion
--   comentado al final de este archivo. La corrida de control de la
--   PoC usa la desactivacion desde el dashboard, no el DROP.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- PARTE 0 — Guardas
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.usuario') IS NULL THEN
    RAISE EXCEPTION 'Falta public.usuario. Aplica el esquema antes de instalar el hook.';
  END IF;

  -- El hook resuelve por event->>'user_id', que es auth.users.id, y
  -- entra a public.usuario por esa misma columna. La verificacion de
  -- terreno confirmo que la convencion usuario.id = auth.users.id se
  -- cumple en los 57 usuarios de QA. Si dejara de cumplirse, el hook
  -- emitiria claims vacios en silencio, que es el peor modo de fallo.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'usuario'
       AND column_name IN ('tenant_id', 'rol')
     GROUP BY table_name HAVING count(*) = 2
  ) THEN
    RAISE EXCEPTION
      'public.usuario no tiene las columnas tenant_id y rol que el hook necesita leer.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    RAISE EXCEPTION
      'No existe el rol supabase_auth_admin. ¿Es un Postgres sin GoTrue?';
  END IF;
END $$;


-- ---------------------------------------------------------------------
-- PARTE 1 — La funcion
-- ---------------------------------------------------------------------
-- DECISIONES DE DISENO, y por que cada una:
--
--   * SECURITY INVOKER (el default, explicito aqui). NO se usa
--     SECURITY DEFINER. Con DEFINER la funcion correria como su dueño
--     (`postgres`, que bypassa RLS) y leeria cualquier fila sin que
--     ninguna politica intervenga. Funcionaria, y seria mas facil, pero
--     esconderia el acceso: nada en `pg_policies` diria que algo lee
--     `usuario` entero. Con INVOKER el acceso queda declarado como una
--     politica visible y auditable (Parte 2). Es mas trabajo y es lo
--     correcto para una funcion que decide identidad.
--
--   * STABLE, no VOLATILE. Solo lee. Permite al planificador cachear
--     dentro de la sentencia y deja constancia de que el hook no debe
--     escribir nada durante la emision de un token.
--
--   * `SET search_path = ''` con todo calificado. Sin esto, alguien con
--     permiso de crear objetos en un esquema del search_path podria
--     interponer una tabla `usuario` propia y controlar que tenant se
--     firma en el token. Es la superficie clasica de estas funciones.
--
--   * FAIL CLOSED. Si el usuario no tiene fila, o su `tenant_id` es
--     NULL, el claim se emite explicitamente como `null` — nunca se
--     omite, nunca se hereda de lo que viniera en app_metadata.
--     Con el predicado de ADR-0018:
--         (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid = t.tenant_id
--     un `null` produce NULL, que no es true: cero filas. El usuario
--     queda autenticado y sin acceso a nada, que es el comportamiento
--     seguro. La Fase 3 VERIFICA esa propiedad; aqui solo se garantiza
--     que el claim salga presente y nulo, no ausente. Conseguirlo exige
--     el `coalesce` de la Parte 1 — ver el comentario de esas lineas.
--
--   * Se escriben `tenant_id`, `user_role` Y `rol`. ADR-0018 y las 15
--     politicas de QA leen `user_role`; el comentario del DDL dice
--     `rol`. El seed de CFG-04 ya escribia ambos por la misma razon
--     (seed_qa_multitenant.sql). Cuesta una linea y evita fallos
--     silenciosos mientras la ambiguedad no se resuelva en el DDL.
--
--   * El hook NO valida el vocabulario de `rol`. La verificacion de
--     terreno encontro que `usuario.rol` es texto libre, sin CHECK
--     (hallazgo H-05). El hook copia lo que haya. Inventar aqui una
--     lista blanca pondria la maquina de roles en la capa de identidad,
--     que no es donde debe vivir; corresponde a un CHECK en la tabla.
--     Se declara como riesgo, no se parcha desde aca.
--
--   * Multi-tenant: no se contempla porque el modelo no lo admite.
--     `usuario` tiene un solo `tenant_id` y no hay tabla de membresia.
--     El `LIMIT 1` de abajo no desempata nada real; esta para que la
--     funcion sea determinista aunque alguien duplique filas a mano.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_claims   jsonb;
  v_tenant   uuid;
  v_rol      text;
BEGIN
  SELECT u.tenant_id, u.rol
    INTO v_tenant, v_rol
    FROM public.usuario u
   WHERE u.id = (event ->> 'user_id')::uuid
   LIMIT 1;

  v_claims := coalesce(event -> 'claims', '{}'::jsonb);

  -- app_metadata puede no venir en el evento: se asegura el objeto
  -- antes de escribir dentro, o jsonb_set no tendria donde poner nada.
  IF v_claims -> 'app_metadata' IS NULL THEN
    v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb);
  END IF;

  -- ⚠️ El `coalesce` NO es decorativo: es lo que hace que el fail closed
  -- exista. `to_jsonb(NULL::text)` NO devuelve el literal JSON `null`,
  -- devuelve SQL NULL. Y `jsonb_set(x, path, NULL)` devuelve NULL, que
  -- se propaga: sin el coalesce, la funcion entera retorna NULL para
  -- cualquier usuario sin fila o sin tenant, y GoTrue recibe NULL en vez
  -- de un evento con claims — comportamiento indefinido, no degradado
  -- seguro.
  --
  -- La primera version de este archivo tenia ese error, con un comentario
  -- que afirmaba lo contrario. Lo atrapo la verificacion V4 al aplicarlo
  -- en QA el 2026-09-22: V4 devolvio `null` donde esperaba un objeto con
  -- las tres claves presentes y nulas. Por eso V4 existe.
  --
  -- `'null'::jsonb` es el literal JSON null. Asi el claim queda PRESENTE
  -- y nulo, que contra el predicado de ADR-0018 da NULL, que no es true:
  -- cero filas.
  v_claims := jsonb_set(v_claims, '{app_metadata,tenant_id}',
                        coalesce(to_jsonb(v_tenant::text), 'null'::jsonb));
  v_claims := jsonb_set(v_claims, '{app_metadata,user_role}',
                        coalesce(to_jsonb(v_rol), 'null'::jsonb));
  v_claims := jsonb_set(v_claims, '{app_metadata,rol}',
                        coalesce(to_jsonb(v_rol), 'null'::jsonb));

  RETURN jsonb_set(event, '{claims}', v_claims);
END;
$$;

COMMENT ON FUNCTION public.custom_access_token_hook(jsonb) IS
  'CFG-12 / SCRUM-971. Inyecta tenant_id y user_role en app_metadata al emitir el token, '
  'implementando ADR-0018. Fail closed: si el usuario no tiene tenant, el claim sale null '
  'y las politicas RLS no devuelven ninguna fila.';


-- ---------------------------------------------------------------------
-- PARTE 2 — Permisos: quien puede ejecutar el hook y que puede leer
-- ---------------------------------------------------------------------

-- 2.a — Solo GoTrue ejecuta el hook.
--   Un usuario de la API que pudiera invocarlo controlaria el argumento
--   `event` y podria pedir los claims de cualquier user_id. No firmaria
--   un token —eso lo hace GoTrue— pero si seria un oraculo que mapea
--   usuarios a tenants. Se revoca antes de conceder, y a PUBLIC tambien,
--   porque CREATE FUNCTION concede EXECUTE a PUBLIC por defecto.
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;

-- 2.b — El hook necesita leer `usuario`. La verificacion de terreno
--   (bloqueante B1) encontro que hoy no puede:
--     has_table_privilege('supabase_auth_admin','public.usuario','SELECT') = false
GRANT USAGE  ON SCHEMA public   TO supabase_auth_admin;
GRANT SELECT ON public.usuario  TO supabase_auth_admin;

-- 2.c — Y aunque tenga el GRANT, sigue sin poder leer.
--
--   ⚠️ AMPLIACION DE SUPERFICIE — DECLARADA A PROPOSITO
--
--   `supabase_auth_admin` tiene rolbypassrls = false, y `usuario` tiene
--   RLS con `tenant_isolation_usuario`:
--       USING (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid)
--   Dentro del hook TODAVIA NO HAY JWT: el hook corre para construirlo.
--   `auth.jwt()` devuelve null, la comparacion da NULL, y la funcion lee
--   cero filas. No falla: emite claims vacios y GoTrue firma un token
--   valido sin tenant. Fallo silencioso en la capa de identidad.
--
--   Esta politica le da a `supabase_auth_admin` lectura de TODAS las
--   filas de `usuario`, cruzando tenants. Es inevitable: el hook tiene
--   que resolver el tenant de cualquier usuario que se autentique, antes
--   de saber cual es. No se puede acotar por tenant sin conocer el
--   tenant, que es justo lo que va a averiguar.
--
--   Lo que acota el riesgo:
--     * El rol no es alcanzable desde la API. `anon` y `authenticated`
--       no pueden asumirlo; es interno de GoTrue.
--     * La politica es solo FOR SELECT. No concede escritura.
--     * Alcanza solo a `usuario`. No se concede nada sobre `tenant`
--       ni sobre ninguna otra tabla: el hook no las necesita.
--     * Queda visible en pg_policies, auditable. Esa es la razon de
--       usar SECURITY INVOKER en vez de DEFINER: con DEFINER el mismo
--       acceso existiria y no apareceria en ningun catalogo de politicas.
DROP POLICY IF EXISTS hook_lee_usuario ON public.usuario;
CREATE POLICY hook_lee_usuario ON public.usuario
  FOR SELECT TO supabase_auth_admin
  USING (true);

COMMENT ON POLICY hook_lee_usuario ON public.usuario IS
  'CFG-12 / SCRUM-971. Permite a supabase_auth_admin leer usuario desde el Custom Access '
  'Token Hook. Cruza tenants por necesidad: el hook resuelve el tenant antes de conocerlo. '
  'Rol interno de GoTrue, no alcanzable por anon ni authenticated. Solo SELECT.';

COMMIT;


-- =====================================================================
-- VERIFICACION POSTERIOR (correr aparte, despues del COMMIT)
-- =====================================================================
-- V1 — La funcion existe con la forma esperada.
--   Esperado: prosecdef = false (INVOKER), provolatile = 's' (STABLE).
--
-- SELECT p.proname, p.prosecdef AS security_definer, p.provolatile AS volatilidad,
--        pg_get_function_identity_arguments(p.oid) AS args
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public' AND p.proname = 'custom_access_token_hook';
--
-- V2 — Los permisos quedaron como se espera.
--   Esperado: ejecuta_auth_admin = true, ejecuta_authenticated = false,
--             lee_usuario = true.
--
-- SELECT has_function_privilege('supabase_auth_admin',
--          'public.custom_access_token_hook(jsonb)', 'EXECUTE') AS ejecuta_auth_admin,
--        has_function_privilege('authenticated',
--          'public.custom_access_token_hook(jsonb)', 'EXECUTE') AS ejecuta_authenticated,
--        has_table_privilege('supabase_auth_admin',
--          'public.usuario', 'SELECT')                          AS lee_usuario;
--
-- V3 — Simulacion del hook contra un usuario real de CFG-04.
--   Corre como `postgres`, que bypassa RLS, asi que comprueba la LOGICA
--   de la funcion, no los permisos. Los permisos los comprueba V2, y el
--   camino completo lo comprueba la Fase 3 con un login de verdad.
--   Esperado: app_metadata con el tenant_id y el rol de ese usuario.
--
-- SELECT jsonb_pretty(public.custom_access_token_hook(jsonb_build_object(
--          'user_id', (SELECT id FROM public.usuario WHERE email = 'aliado.t1@qa.mani.test'),
--          'claims',  jsonb_build_object('role', 'authenticated')
--        )));
--
-- V4 — Fail closed contra un user_id inexistente. LA VERIFICACION CLAVE.
--   Esperado: "tenant_id": null y "user_role": null, ambos PRESENTES, y
--   el retorno de la funcion NO nulo.
--
--   Esta es la que atrapo el bug de la primera version (ver el comentario
--   del coalesce en la Parte 1): devolvia NULL entero en vez de claims
--   nulos. Si alguna clave sale ausente, o si la funcion retorna NULL, el
--   fail closed no esta garantizado y no se puede seguir a la Fase 3.
--
-- SELECT jsonb_pretty(public.custom_access_token_hook(jsonb_build_object(
--          'user_id', '00000000-0000-4000-8000-000000000000',
--          'claims',  jsonb_build_object('role', 'authenticated')
--        )));
--
-- V5 — El hook no pisa los claims propios de GoTrue.
--   La funcion recibe el evento entero y devuelve el evento entero. Si
--   reconstruyera `claims` en vez de modificarlo, se perderian `sub`,
--   `aal`, `session_id`, `exp` y demas, y el token saldria invalido o
--   degradado. Esperado: los tres claims de prueba intactos, mas
--   app_metadata poblado.
--
-- SELECT jsonb_pretty(public.custom_access_token_hook(jsonb_build_object(
--          'user_id', (SELECT id FROM public.usuario WHERE email = 'aliado.t1@qa.mani.test'),
--          'claims',  jsonb_build_object('role','authenticated','sub','abc','aal','aal1')
--        )) -> 'claims');


-- =====================================================================
-- REVERSION (no correr durante la PoC)
-- =====================================================================
-- La corrida de control de la Fase 7 DESACTIVA el hook desde el
-- dashboard, no lo borra: hay que poder volver a activarlo. Esto es
-- para desmontarlo del todo.
--
-- BEGIN;
--   DROP POLICY IF EXISTS hook_lee_usuario ON public.usuario;
--   REVOKE SELECT ON public.usuario FROM supabase_auth_admin;
--   DROP FUNCTION IF EXISTS public.custom_access_token_hook(jsonb);
-- COMMIT;
