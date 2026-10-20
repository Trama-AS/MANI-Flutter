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

---

## Autoría y atribución (obligatorio)

**El entregable lo firma la persona que lo presenta.** No se añaden líneas de coautoría, firmas, pies ni emojis que atribuyan el trabajo a una herramienta de IA, ni en commits, Pull Requests, documentos, código o comentarios. Tampoco se firma un documento o un ADR como autor: ese campo lleva el nombre de la persona responsable.

Regla vigente: `MANI-Docs` → [`governance/POLITICAS_DEVOPS_HERRAMIENTAS.md`](https://github.com/Trama-AS/MANI-docs/blob/main/governance/POLITICAS_DEVOPS_HERRAMIENTAS.md) §18.7 y [`wiki/05-proceso/trabajo-con-ia.md`](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/05-proceso/trabajo-con-ia.md).

Por qué, para no revertirla «mejorando»: la política §18.1 ya exige revisión humana de todo resultado, y esa revisión es la garantía; §18.5 dice que una respuesta de IA no es una decisión arquitectónica, así que atribuirle autoría la contradice. La trazabilidad del cambio la dan el identificador de Jira, la rama, el PR y el historial de Git, que sí dicen qué cambió, por qué y quién lo aprobó.

Lo que sí se registra es el **método de verificación** —el comando ejecutado y su resultado, el archivo comparado, la consulta hecha—, no la herramienta que ayudó a escribirlo.

Si encuentras una atribución de ese tipo en un archivo que ya estás editando, quítala.
