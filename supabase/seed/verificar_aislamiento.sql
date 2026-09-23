-- =====================================================================
-- MANI — Verificacion del seed multi-tenant de QA
-- =====================================================================
-- Ticket: SCRUM-921 (CFG-04) · Cierra SCRUM-1002 y SCRUM-1004
-- Complemento de: supabase/seed/seed_qa_multitenant.sql
--
-- TODO ESTE ARCHIVO ES DE SOLO LECTURA. No modifica datos. El unico bloque
-- que abre transaccion (el 5) termina en ROLLBACK.
--
-- COMO USARLO
--   Correr bloque por bloque en el SQL Editor y guardar cada salida. El
--   conjunto es el "checklist de cierre" que pide el DoD §5 del spike
--   SCRUM-945; la salida del bloque 5 es la evidencia del "chequeo
--   explicito de aislamiento multi-tenant" del DoD §4.
--
--   El bloque 0 conviene correrlo ANTES del seed (estado de partida).
--   Los bloques 1-5, despues.
-- =====================================================================


-- ---------------------------------------------------------------------
-- BLOQUE 0 — Estado de partida (correr ANTES del seed)
-- ---------------------------------------------------------------------

-- 0.a — Forma real de auth.users / auth.identities en ESTE proyecto.
-- El seed ya se adapta solo, pero si falla la Parte B.1 esta es la salida
-- que hay que mirar primero.
SELECT table_name, column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'auth'
   AND table_name IN ('users', 'identities')
 ORDER BY table_name, ordinal_position;

-- 0.b — SCRUM-1002: catalogo de zonas cargado en QA.
-- Si devuelve 0, el seed igual carga sus 3 zonas (Bogota/Chapinero/Suba),
-- asi que no bloquea. Esta consulta es la evidencia del ticket.
SELECT count(*) AS zonas_activas
  FROM zona
 WHERE estado = 'ACTIVO';

-- 0.c — GRANTs a los roles de PostgREST.
-- Si sale VACIO, PostgREST corta por permisos ANTES de que RLS actue: el
-- bloque 5 fallara con "permission denied" y la suite Newman de ADR-0015
-- no podra correr aunque el seed este perfecto. Es un hallazgo aparte
-- (fuera del alcance de CFG-04), no un fallo del seed.
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
  FROM information_schema.role_table_grants
 WHERE table_schema = 'public'
   AND grantee IN ('anon', 'authenticated')
 GROUP BY grantee, table_name
 ORDER BY grantee, table_name;


-- ---------------------------------------------------------------------
-- BLOQUE 1 — 2 tenants completos + idempotencia (SCRUM-1003)
-- ---------------------------------------------------------------------
-- Esperado: 2 filas, con exactamente estos numeros en ambas.
--   usuarios=3, clientes=1, aliados=1, aliados_aprobados=1,
--   categorias_activas=1, sitios=1, vinculos_categoria=1, coberturas=1
-- Para probar idempotencia: correr el seed 2 o 3 veces mas y repetir esta
-- consulta. Los numeros no se deben mover ni un digito.
SELECT t.slug,
       (SELECT count(*) FROM usuario            u WHERE u.tenant_id = t.id) AS usuarios,
       (SELECT count(*) FROM cliente            c WHERE c.tenant_id = t.id) AS clientes,
       (SELECT count(*) FROM aliado             a WHERE a.tenant_id = t.id) AS aliados,
       (SELECT count(*) FROM aliado             a WHERE a.tenant_id = t.id
                                                   AND a.estado_verificacion = 'VERIFICADO') AS aliados_aprobados,
       (SELECT count(*) FROM categoria_servicio s WHERE s.tenant_id = t.id
                                                   AND s.estado = 'ACTIVO')                AS categorias_activas,
       (SELECT count(*) FROM sitio              s WHERE s.tenant_id = t.id) AS sitios,
       (SELECT count(*) FROM aliado_categoria  ac WHERE ac.tenant_id = t.id) AS vinculos_categoria,
       (SELECT count(*) FROM cobertura_aliado  ca WHERE ca.tenant_id = t.id) AS coberturas
  FROM tenant t
 WHERE t.id IN ('10000000-0000-4000-8000-000000000011',
                '10000000-0000-4000-8000-000000000021')
 ORDER BY t.slug;

-- 1.b — Los 6 usuarios de Auth existen y llevan los claims correctos.
-- Esperado: 6 filas, todas con tenant_id no nulo y user_role = rol.
SELECT u.email,
       u.raw_app_meta_data ->> 'tenant_id' AS claim_tenant_id,
       u.raw_app_meta_data ->> 'user_role' AS claim_user_role,
       u.raw_app_meta_data ->> 'rol'       AS claim_rol,
       (u.email_confirmed_at IS NOT NULL)  AS email_confirmado,
       EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id) AS tiene_identity,
       EXISTS (SELECT 1 FROM usuario         a WHERE a.id      = u.id) AS ligado_a_usuario
  FROM auth.users u
 WHERE u.email LIKE '%@qa.mani.test'
 ORDER BY u.email;


-- ---------------------------------------------------------------------
-- BLOQUE 2 — El despacho puede hacer match dentro de cada tenant
-- ---------------------------------------------------------------------
-- Esperado: 2 filas (una por tenant), ambas con match = true.
-- Si sale false, el aliado no cubre la zona del sitio de su cliente y el
-- despacho (ADR-0016) nunca asignaria la solicitud.
SELECT t.slug,
       z.nombre AS zona_sitio,
       (ca.zona_id IS NOT NULL) AS match
  FROM tenant t
  JOIN sitio  s  ON s.tenant_id = t.id
  JOIN zona   z  ON z.id        = s.zona_id
  JOIN aliado a  ON a.tenant_id = t.id
  LEFT JOIN cobertura_aliado ca
         ON ca.aliado_id = a.id
        AND ca.zona_id   = s.zona_id
 WHERE t.id IN ('10000000-0000-4000-8000-000000000011',
                '10000000-0000-4000-8000-000000000021')
 ORDER BY t.slug;


-- ---------------------------------------------------------------------
-- BLOQUE 3 — Cero cruces de tenant_id entre filas relacionadas
-- ---------------------------------------------------------------------
-- Esperado: CERO filas. Cada fila que salga es una fuga estructural: dos
-- registros relacionados que pertenecen a tenants distintos.
SELECT 'cliente -> usuario'          AS relacion, c.id AS fila_id FROM cliente c
   JOIN usuario u ON u.id = c.usuario_id           WHERE u.tenant_id IS DISTINCT FROM c.tenant_id
UNION ALL
SELECT 'aliado -> usuario',           a.id FROM aliado a
   JOIN usuario u ON u.id = a.usuario_id           WHERE u.tenant_id IS DISTINCT FROM a.tenant_id
UNION ALL
SELECT 'sitio -> cliente',            s.id FROM sitio s
   JOIN cliente c ON c.id = s.cliente_id           WHERE c.tenant_id IS DISTINCT FROM s.tenant_id
UNION ALL
SELECT 'aliado_categoria -> aliado',  ac.id FROM aliado_categoria ac
   JOIN aliado a ON a.id = ac.aliado_id            WHERE a.tenant_id IS DISTINCT FROM ac.tenant_id
UNION ALL
SELECT 'aliado_categoria -> categoria', ac.id FROM aliado_categoria ac
   JOIN categoria_servicio cs ON cs.id = ac.categoria_id
                                                   WHERE cs.tenant_id IS DISTINCT FROM ac.tenant_id
UNION ALL
SELECT 'cobertura_aliado -> aliado',  ca.id FROM cobertura_aliado ca
   JOIN aliado a ON a.id = ca.aliado_id            WHERE a.tenant_id IS DISTINCT FROM ca.tenant_id;


-- ---------------------------------------------------------------------
-- BLOQUE 4 — Confirmacion de que las tablas tienen RLS activo
-- ---------------------------------------------------------------------
-- Esperado: rls_activo = true en las 9 tablas tenant-scoped.
-- `tenant` y `zona` son globales por diseno: ahi false es lo correcto.
SELECT c.relname AS tabla,
       c.relrowsecurity AS rls_activo,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS politicas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relname IN ('tenant','zona','usuario','cliente','aliado',
                     'categoria_servicio','sitio','aliado_categoria','cobertura_aliado')
 ORDER BY c.relrowsecurity, c.relname;


-- ---------------------------------------------------------------------
-- BLOQUE 5 — RLS con sesion simulada  ← LA VALIDACION QUE IMPORTA
-- ---------------------------------------------------------------------
-- Los bloques anteriores corren como `postgres`, que BYPASSA RLS: prueban
-- que los datos estan bien, no que el aislamiento funcione. Este bloque
-- adopta el rol `authenticated` e inyecta un JWT falso con el tenant_id en
-- app_metadata — exactamente lo que auth.jwt() lee en las politicas.
--
-- Si falla con "permission denied for table ...", NO es el aislamiento:
-- son los GRANTs faltantes del bloque 0.c.

-- 5.a — Sesion del CLIENTE DEL TENANT 1
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-4000-8000-000000000012","role":"authenticated","app_metadata":{"tenant_id":"10000000-0000-4000-8000-000000000011","user_role":"cliente","rol":"cliente"}}';

  -- Esperado: 1 en cada columna (solo ve lo suyo), 0 en las de fuga.
  SELECT (SELECT count(*) FROM sitio)              AS sitios_visibles,
         (SELECT count(*) FROM aliado)             AS aliados_visibles,
         (SELECT count(*) FROM categoria_servicio) AS categorias_visibles,
         (SELECT count(*) FROM sitio  WHERE id = '70000000-0000-4000-8000-000000000021') AS FUGA_sitio_t2,
         (SELECT count(*) FROM aliado WHERE id = '50000000-0000-4000-8000-000000000021') AS FUGA_aliado_t2;
ROLLBACK;

-- 5.b — Sesion del CLIENTE DEL TENANT 2 (el espejo)
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-4000-8000-000000000022","role":"authenticated","app_metadata":{"tenant_id":"10000000-0000-4000-8000-000000000021","user_role":"cliente","rol":"cliente"}}';

  SELECT (SELECT count(*) FROM sitio)              AS sitios_visibles,
         (SELECT count(*) FROM aliado)             AS aliados_visibles,
         (SELECT count(*) FROM categoria_servicio) AS categorias_visibles,
         (SELECT count(*) FROM sitio  WHERE id = '70000000-0000-4000-8000-000000000011') AS FUGA_sitio_t1,
         (SELECT count(*) FROM aliado WHERE id = '50000000-0000-4000-8000-000000000011') AS FUGA_aliado_t1;
ROLLBACK;

-- 5.c — Control negativo: JWT con un tenant_id que no existe.
-- Esperado: 0 en todo. Si devuelve filas, la politica no esta filtrando.
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-4000-8000-000000000012","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-00000000ffff","user_role":"cliente","rol":"cliente"}}';

  SELECT (SELECT count(*) FROM sitio)   AS sitios_visibles,
         (SELECT count(*) FROM aliado)  AS aliados_visibles,
         (SELECT count(*) FROM usuario) AS usuarios_visibles;
ROLLBACK;


-- ---------------------------------------------------------------------
-- RESUMEN ESPERADO PARA ADJUNTAR A SCRUM-1004
-- ---------------------------------------------------------------------
--   Bloque 1   : 2 tenants, todos los conteos en 1 (usuarios en 3)
--   Bloque 1.b : 6 usuarios de Auth, claims completos, ligados a `usuario`
--   Bloque 2   : match = true en ambos tenants
--   Bloque 3   : cero filas
--   Bloque 4   : rls_activo = true en las 9 tablas tenant-scoped
--   Bloque 5.a : 1/1/1 visibles, 0/0 de fuga
--   Bloque 5.b : 1/1/1 visibles, 0/0 de fuga
--   Bloque 5.c : 0/0/0
--   Idempotencia: bloque 1 identico tras correr el seed 3 veces
