# CLAUDE.md — Guía de Desarrollo para MANI-Flutter

Este documento sintetiza las directrices para el desarrollo en el cliente frontend de MANI.

---

## 1. Arquitectura de Integración (SOA / Multi-Repo)
* **MANI-Flutter** actúa exclusivamente como capa de presentación (Web y Móvil).
* **Consumo de Servicios:** Todo consumo de APIs REST se realiza apuntando a la URL del **`MANI-APIGateway`**:
  - `/api/v1/core/*` ➔ Backend Core (Node.js).
  - `/api/v1/rules/*` ➔ Motor de Reglas (Java).
  - `/api/v1/dispatch/*` ➔ Algoritmo de Despacho (.NET).
* **Prohibición Arquitectónica:** No configurar URLs fijas directas a los puertos internos de los microservicios (`:3000`, `:8080`, `:5000`). Toda petición debe ingresar por el puerto del Gateway (`:80`).

---

## 2. Convenciones de Código y Estado
* **Manejo de Estado:** `flutter_bloc` / `Cubit` con arquitectura limpia por capas (`domain`, `data`, `presentation`).
* **Clientes HTTP:** Interceptar peticiones para inyectar automáticamente:
  - `Authorization: Bearer <token>`
  - `X-Correlation-ID: <uuid>`
* **Manejo de Errores Concurrenciales:** En flujos de aceptación de servicio de aliados, capturar específicamente el código HTTP `409 Conflict` (emitido por `MANI-Dispatch-DotNet`) para notificar al usuario que la solicitud ya fue tomada por otro profesional.

---

## 3. Pruebas y CI
* Ejecutar siempre `flutter analyze` y `flutter test` antes de abrir Pull Requests hacia `develop` o `release`.
