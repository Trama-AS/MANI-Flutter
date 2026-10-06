-- =====================================================================
-- MANI — Verificacion de una corrida del harness (fuente de verdad)
-- =====================================================================
-- Ticket: SCRUM-926 (CFG-09) · Subtareas: SCRUM-962, SCRUM-963
-- Ambiente: SOLO QA · TODO ESTE ARCHIVO ES DE SOLO LECTURA.
--
-- Estas consultas —no la salida de k6— deciden si la PoC pasa. k6 reporta
-- lo que el cliente RECIBIO; la bitacora registra lo que la base HIZO. Si
-- las dos discrepan, manda la base.
--
-- Reemplazar :corrida por la etiqueta que imprimio el teardown de k6.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BLOQUE 1 — LA METRICA DEL TICKET
-- ---------------------------------------------------------------------
-- Umbral: asignaciones = 1 y dobles = 0.
-- `asignaciones` cuenta filas de la bitacora, no el estado final de la
-- solicitud: con una sola fila de solicitud, dos ganadores dejan el mismo
-- rastro que uno (el segundo pisa al primero). La bitacora es lo unico que
-- distingue los dos casos.
SELECT corrida,
       count(*)                          AS asignaciones,
       count(DISTINCT aliado_id)         AS aliados_distintos,
       count(DISTINCT txid)              AS transacciones_distintas,
       GREATEST(count(*) - 1, 0)         AS dobles_asignaciones,
       CASE WHEN count(*) = 1 THEN 'CUMPLE' ELSE 'NO CUMPLE' END AS veredicto
  FROM poc_asignacion_log
 WHERE solicitud_id = 'a0000000-0000-4000-8000-900000000001'
 GROUP BY corrida
 ORDER BY min(asignada_en);

-- ---------------------------------------------------------------------
-- BLOQUE 2 — ¿HUBO CONCURRENCIA REAL? (control del control)
-- ---------------------------------------------------------------------
-- Solo aplica a la corrida con MODO=sin_exclusion. Si el control negativo
-- devuelve asignaciones = 1, el harness NO genero peticiones solapadas y
-- el verde del bloque 1 no prueba nada: no se demostro exclusion, se
-- demostro que no hubo carrera.
--
-- `ventana_ms` es la distancia entre la primera y la ultima asignacion de
-- la corrida. Una ventana de pocos ms con N filas es la evidencia directa
-- de que las transacciones se solaparon.
SELECT corrida,
       count(*) AS asignaciones,
       min(asignada_en) AS primera,
       max(asignada_en) AS ultima,
       EXTRACT(milliseconds FROM max(asignada_en) - min(asignada_en)) AS ventana_ms,
       count(*) FILTER (WHERE aliado_previo IS NOT NULL) AS pisaron_a_otro
  FROM poc_asignacion_log
 WHERE solicitud_id = 'a0000000-0000-4000-8000-900000000001'
 GROUP BY corrida
 ORDER BY min(asignada_en);

-- ---------------------------------------------------------------------
-- BLOQUE 3 — Detalle por asignacion (evidencia cruda)
-- ---------------------------------------------------------------------
-- Con exclusion correcta: 1 fila. Con el control negativo: varias, cada
-- una con su txid propio. `aliado_previo` no nulo es la prueba literal de
-- un lost update: esa transaccion sobrescribio a un ganador anterior.
SELECT l.id, l.corrida, l.aliado_id, l.aliado_previo, l.txid,
       to_char(l.asignada_en, 'HH24:MI:SS.MS') AS hora,
       a.nombre_razon_social
  FROM poc_asignacion_log l
  LEFT JOIN aliado a ON a.id = l.aliado_id
 WHERE l.solicitud_id = 'a0000000-0000-4000-8000-900000000001'
 ORDER BY l.asignada_en;

-- ---------------------------------------------------------------------
-- BLOQUE 4 — Estado final de la solicitud
-- ---------------------------------------------------------------------
-- Complemento, NO la metrica. Sirve para confirmar que el ganador que
-- quedo en la fila es uno de los que registro la bitacora.
SELECT s.id, s.estado, s.aliado_id AS ganador_en_fila,
       (SELECT count(*) FROM poc_asignacion_log l
         WHERE l.solicitud_id = s.id AND l.aliado_id = s.aliado_id) AS ganador_en_bitacora
  FROM solicitud s
 WHERE s.id = 'a0000000-0000-4000-8000-900000000001';
