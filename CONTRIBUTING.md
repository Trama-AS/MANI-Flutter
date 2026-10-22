# Guia de Contribucion y Trazabilidad

Para garantizar la trazabilidad automatica con Jira Software y el cumplimiento de las politicas de gobernanza del proyecto MANI, todo desarrollo debe seguir estrictamente los siguientes estandares.

## 1. Convencion Obligatoria de Nombres (SCRUM-<id>)

Cada historia de usuario, tarea tecnica, sub-tarea o defecto cuenta con un identificador unico en Jira (ejemplo: SCRUM-1114 o SCRUM-452). Este identificador debe incluirse de manera obligatoria en ramas, commits y pull requests.

### 1.1 Nombre de Ramas (Branch Naming)
Las ramas deben crearse a partir de develop (o main segun el flujo definido) y seguir la siguiente nomenclatura:

- Formato: tipo/SCRUM-<id>-descripcion-corta
- Tipos validos: feature, fix, chore, docs, refactor, test

Ejemplos:
- Correcto: feature/SCRUM-1114-trazabilidad-jira-github
- Correcto: fix/SCRUM-848-validacion-documentos-aliado
- Incorrecto: feature/trazabilidad-jira
- Incorrecto: fix-documentos

### 1.2 Mensajes de Commit
Cada mensaje de commit debe iniciar con el identificador del ticket entre corchetes, seguido de un mensaje descriptivo en modo imperativo.

- Formato: [SCRUM-<id>] Descripcion del cambio realizado

Ejemplos:
- Correcto: [SCRUM-1114] Configura guia de contribucion y plantillas de pull request
- Correcto: [SCRUM-859] Implementa seleccion de categorias atendidas por el aliado
- Incorrecto: Arreglo de estilos y plantillas
- Incorrecto: subiendo cambios

### 1.3 Titulo de Pull Requests
El titulo del Pull Request debe contener el identificador del ticket para permitir a Jira enlazar la revision en el panel de desarrollo y gestionar las transiciones de estado automaticamente.

- Formato: [SCRUM-<id>] Descripcion concisa de la solucion

Ejemplos:
- Correcto: [SCRUM-1114] Integracion de trazabilidad automatica GitHub y Jira
- Incorrecto: Nuevas configuraciones del repositorio

## 2. Uso de Smart Commits

La integracion con Jira soporta Smart Commits para ejecutar acciones y registrar progreso directamente desde los mensajes de confirmacion en Git:

- Registro de tiempo invertido:
  [SCRUM-1114] #time 2h 30m

- Comentarios automaticos en el ticket:
  [SCRUM-1114] #comment Se completo la revision de plantillas en todos los repositorios

- Transicion de estado de la tarea:
  [SCRUM-1114] #resolve Documentacion y configuracion finalizadas

- Combinacion de comandos:
  [SCRUM-1114] #comment Pruebas de integracion concluidas #time 1h #resolve

## 3. Proceso de Revision de Codigo

1. Crear la rama siguiendo la convencion indicada.
2. Realizar los commits utilizando el prefijo [SCRUM-<id>].
3. Abrir el Pull Request completando la plantilla predeterminada (.github/pull_request_template.md).
4. Solicitar la aprobacion de al menos un CODEOWNER asignado.
5. Verificar que todas las comprobaciones de integracion continua (CI) finalicen de forma exitosa antes de la fusion (merge).
