# AGENTS.md — MANI-Flutter (Frontend Web & Mobile)

Bienvenido al repositorio **MANI-Flutter**. Este archivo define el rol del frontend y las directrices operativas de IA y desarrollo dentro del nuevo ecosistema SOA distribuido de MANI.

---

## 1. Rol y Responsabilidad del Repositorio
* **Tecnología:** Flutter (Canal Stable) / Dart (^3.9.2).
* **Plataformas:** Web (SPA servido vía Nginx) y Móvil (Android/iOS).
* **Dominio:** Interfaz de usuario, presentación y experiencia de cliente:
  - Experiencia para **Clientes:** Solicitud de servicios, seguimiento en vivo, cotización y pagos.
  - Experiencia para **Aliados (Profesionales):** Bandeja de solicitudes disponibles, aceptación/rechazo, gestión de categorías y KYC.
  - Experiencia para **Administradores:** Verificación de documentación y métricas operativas.
* **Principio Clave:** El Frontend **no contiene lógica de negocio crítica, cálculos de tarifas ni algoritmos de despacho**. Toda la lógica de dominio reside en los microservicios backend.

---

## 2. Topología de Comunicación con Microservicios vía API Gateway

En la arquitectura SOA de MANI, **`MANI-Flutter` nunca se comunica directamente con los microservicios individuales**, sino exclusivamente a través del **API Gateway** (`MANI-APIGateway`):

```
                       [ MANI-Flutter ]
                              │
                              ▼ (HTTP / Puerto 80)
                      [ MANI-APIGateway ] (NGINX)
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
[ MANI-Node ]          [ MANI-Rules-Java ]    [ MANI-Dispatch-DotNet ]
 (Core: :3000)          (Rules: :8080)         (Dispatch: :5000)
 /api/v1/core/*         /api/v1/rules/*        /api/v1/dispatch/*
```

### Rutas consumidas por Flutter a través del Gateway:

| Prefijo de Ruta | Microservicio Destino | Propósito Funcional para Flutter |
| :--- | :--- | :--- |
| **`/api/v1/core/*`** | **`MANI-Node`** | Autenticación, perfiles de usuario, KYC, catálogos de servicios y gestión de tenants. |
| **`/api/v1/rules/*`** | **`MANI-Rules-Java`** | Cotización en vivo, cálculo dinámico de tarifas, recargos y ranking de aliados. |
| **`/api/v1/dispatch/*`** | **`MANI-Dispatch-DotNet`** | Lanzamiento de solicitudes de servicio, cálculo de cercanía y aceptación del aliado (exclusión concurrente). |

---

## 3. Protocolos y Encabezados Enviados por el Cliente
* **`Authorization: Bearer <JWT>`:** Token de sesión emitido tras autenticación, requerido en todas las peticiones a endpoints protegidos.
* **`X-Correlation-ID`:** UUID v4 autogenerado en cada petición HTTP desde Flutter (vía `Dio` o `http.Client`) para permitir la auditoría de extremo a extremo a través del Gateway y los servicios.
* **Variables de Entorno (`.env`):**
  - `API_GATEWAY_URL`: URL base del API Gateway (ej. `http://localhost:80` en local, o IPs dedicadas en QA/PROD).

---

## 4. Comandos de Calidad y Desarrollo
```bash
# Instalar dependencias
flutter pub get

# Ejecutar análisis estático (Linter)
flutter analyze

# Ejecutar suite de pruebas con cobertura
flutter test --coverage

# Ejecutar aplicación en navegador Chrome
flutter run -d chrome
```

---

## Autoría y atribución (obligatorio)

**El entregable lo firma la persona que lo presenta.** No se añaden líneas de coautoría, firmas, pies ni emojis que atribuyan el trabajo a una herramienta de IA, ni en commits, Pull Requests, documentos, código o comentarios. Tampoco se firma un documento o un ADR como autor: ese campo lleva el nombre de la persona responsable.

Regla vigente: `MANI-Docs` → [`governance/POLITICAS_DEVOPS_HERRAMIENTAS.md`](https://github.com/Trama-AS/MANI-docs/blob/main/governance/POLITICAS_DEVOPS_HERRAMIENTAS.md) §18.7 y [`wiki/05-proceso/trabajo-con-ia.md`](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/05-proceso/trabajo-con-ia.md).

Por qué, para no revertirla «mejorando»: la política §18.1 ya exige revisión humana de todo resultado, y esa revisión es la garantía; §18.5 dice que una respuesta de IA no es una decisión arquitectónica, así que atribuirle autoría la contradice. La trazabilidad del cambio la dan el identificador de Jira, la rama, el PR y el historial de Git, que sí dicen qué cambió, por qué y quién lo aprobó.

Lo que sí se registra es el **método de verificación** —el comando ejecutado y su resultado, el archivo comparado, la consulta hecha—, no la herramienta que ayudó a escribirlo.

Si encuentras una atribución de ese tipo en un archivo que ya estás editando, quítala.
