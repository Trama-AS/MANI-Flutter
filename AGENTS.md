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
