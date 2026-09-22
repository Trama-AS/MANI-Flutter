# Suites de Newman — CFG-12 y ADR-0015

Ticket: **SCRUM-929 (CFG-12)** · Ambiente: **solo QA** (`hpsxdotaizzclkeufzct`)

El informe de la PoC va a `Trama-AS/MANI-docs`, `Entregas/PoC/`. Aqui vive el codigo
ejecutable (ADR-0001, ADR-0007).

## Por que Newman y no un script

La revision del 2026-09-17 del DoR y el DoD reparte las herramientas por modulo: Maestro
para flujos de pantalla de Flutter, Postman/Newman para endpoints de los modulos Java
y .NET. **El aislamiento multi-tenant queda fuera de ese reparto**, marcado como
transversal en ambos documentos:

- DoR punto 4 — *"Si el ticket toca autenticacion, RLS o el esquema de datos (transversal
  a cualquier modulo): ademas de lo anterior, debe pasar la suite de aislamiento
  multi-tenant ya definida en ADR-0015"*.
- DoD punto 2 — *"Aislamiento multi-tenant (transversal, cualquier modulo): la suite ya
  definida en ADR-0015"*, adoptada como gate de cierre.

CFG-12 toca autenticacion y RLS, asi que aplica. Ademas el DoD pide el **reporte de
Newman** como evidencia de cierre: un JSON de un script propio no lo es.

## Colecciones

| Archivo | Cubre |
| --- | --- |
| `mani-claims.postman_collection.json` | SCRUM-972, SCRUM-973 y la suite anti-spoofing del punto 7 del DoR |
| `mani-aislamiento.postman_collection.json` | Los 6 casos de acceso cruzado de ADR-0015 (SCRUM-975) |

`mani-aislamiento` se mantiene aparte a proposito: su vida util excede esta PoC. Es el
artefacto que el DoR punto 4 y el DoD punto 2 exigen en cada ticket que toque auth, RLS o
esquema, y hoy no existia en ningun repositorio.

## Como se corre

Las credenciales no se versionan: se inyectan por variable.

```bash
set -a; source .env; set +a

npx newman run qa/newman/mani-claims.postman_collection.json \
  --env-var base_url="$SUPABASE_URL" \
  --env-var anon_key="$SUPABASE_ANON_KEY" \
  --reporters cli,json \
  --reporter-json-export qa/newman/evidencia/claims-hook-activo.json
```

Newman esta como dependencia de desarrollo de esta carpeta, no global, para que quede
versionado (`qa/newman/package.json`).

## La evidencia se redacta antes de commitear

El reporte JSON de newman guarda la peticion y la respuesta completas. Eso incluye las
cabeceras `apikey` y `Authorization`, y —lo que menos se ve— los cuerpos de respuesta en
`response.stream`, como **Buffer serializado**: ahi viven enteros los `access_token` y
`refresh_token` de cada login.

```bash
node qa/newman/redactar_evidencia.mjs \
  qa/newman/evidencia/claims-hook-activo.json \
  qa/newman/evidencia/claims-hook-activo.redactado.json \
  "$SUPABASE_ANON_KEY"
```

El redactor falla con codigo 1 si sobrevive algo con forma de JWT, y para comprobarlo
decodifica los buffers en vez de buscar en el texto del archivo. Los reportes crudos estan
gitignoreados; se versiona el `.redactado.json`.

## Estructura de `mani-claims`

| Carpeta | Que responde |
| --- | --- |
| `00 preparacion` | Resuelve los ids de tenant y descarga el JWKS. Ninguna de las dos depende de un token |
| `01 propagacion` | El JWT propaga `tenant_id` y el rol correctos, en dos tenants y con dos roles distintos |
| `02 casos borde` | Usuario sin tenant y usuario sin fila en `usuario` |
| `03 anti-spoofing` | Los cuatro vectores que ataca ADR-0018 |

### Dos decisiones de metodo que hacen que el verde signifique algo

**Los usuarios son `@cfg12.mani.test`, no los de CFG-04.** Las cuentas de CFG-04 llevan
`tenant_id` escrito a mano en `raw_app_meta_data`, que GoTrue copia al JWT: su token sale
con tenant **con hook o sin hook**. Probar contra ellas mediria el seed, no el mecanismo.
Las de `20_seed_identidad.sql` llevan `raw_app_meta_data` sin claims de tenant, asi que un
`tenant_id` en el token solo puede venir del hook.

**El oraculo no es circular.** El `tenant_id` del claim no se compara contra `usuario`:
RLS filtra esa tabla usando ese mismo claim, y la comprobacion se confirmaria a si misma.
Se compara contra `tenant`, que tiene `lectura_global_tenant USING (true)` y se lee sin
depender del claim. La asercion real es que el `tenant_id` del token corresponde al tenant
cuyo `slug` es el esperado.

## Casos que NO son ejecutables, y por que

Se declaran en vez de omitirse, como pide la plantilla de PoC.

- **Usuario con multiples roles (SCRUM-973).** `usuario` tiene un solo `tenant_id` y no
  existe tabla de membresia: la doble pertenencia no es representable. ADR-0018 ya admite
  como consecuencia negativa que cambiar de tenant exige reexpedir el token; lo que la
  verificacion de terreno agrega es que hoy ese escenario ni siquiera se puede modelar.
- **Caso 6 de ADR-0015, aislamiento de KYC en Storage.** QA tiene cero buckets y cero
  politicas sobre `storage.objects`: ADR-0013 no esta implementado. El seed siembra un
  `documento_kyc` por tenant, lo que habilita probar el aislamiento de la **fila** — util,
  pero no es el caso 6, que es el del **objeto**.
- **Token expirado.** Los JWT de QA duran una hora. Probarlo exige esperar o bajar
  temporalmente el TTL del proyecto, que es un cambio de configuracion de autenticacion.
  El vector 1 cubre la mitad del caso 5 de ADR-0015 —token **alterado**— demostrando que
  cualquier modificacion del payload, incluido `exp`, invalida la firma.

## Dependencias

1. `supabase/poc-cfg12/10_hook_claims_tenant.sql` aplicado **y** el hook registrado en
   Authentication > Hooks. Que este registrado no se puede comprobar desde SQL: lo
   comprueba la carpeta `01 propagacion` con un login real.
2. `supabase/poc-cfg12/20_seed_identidad.sql` aplicado.
3. El seed de CFG-04 (`supabase/seed/seed_qa_multitenant.sql`), del que dependen los dos
   tenants y sus datos.
