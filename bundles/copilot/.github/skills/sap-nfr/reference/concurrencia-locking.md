# Concurrencia y locking por tecnología

> Detalle del catálogo NFR del stack. Se lee bajo demanda.

## 1. Concurrencia y Locking

Toda logica que escribe en tablas compartidas o ejecuta en background debe
diseñarse asumiendo **N procesos paralelos sobre los mismos datos**.

### ABAP / S/4HANA

- **ENQUEUE_E* / DEQUEUE_E*** antes de UPDATE/MODIFY de tablas con lock object
- **RAP**: usar `lock master` en BDEF; manejar `CX_ABAP_BEHV_CONFLICT` en EML
- **Update Task**: separar logica de UI (V1) de logica posponible (V2) — `PERFORM ... ON COMMIT`
- **COMMIT WORK boundaries**: nunca un solo COMMIT al final de un proceso masivo
  - Patron: cada N registros (500–2000) → COMMIT WORK, log de progreso, reset de buffers
- **Cursor stable + parallel cursor** para LOOPs grandes con tablas anidadas
- **SY-SUBRC** despues de CADA ENQUEUE/DEQUEUE/UPDATE — nunca asumir exito

### CAP / BTP

- **Optimistic locking**: usar `@odata.etag` en entidades con concurrencia alta
- **`cds.tx(req)`**: una transaccion por request HTTP, nunca compartir tx entre requests
- **Batch handlers**: si el handler procesa array, iterar en chunks con `Promise.allSettled`
- **Idempotency-key**: aceptar header `Idempotency-Key` en endpoints POST/PATCH criticos
- **`@requires` y `@restrict`** en TODAS las acciones que modifican estado

### HANA

- **MVCC** se asume — pero validar isolation level si se usa READ COMMITTED / SERIALIZABLE
- **`SELECT … FOR UPDATE NOWAIT`** para reservas de stock / asignacion de numeros
- **Particionado por hash** para tablas con escritura paralela alta (>1k tx/s)
- **Statement-level vs procedure-level COMMIT** — explicitar en SQLScript

### Integration (CPI / iFlow)

- **Idempotent Receiver pattern**: deduplicar por `MessageID` en JMS / persistencia
- **Splitter + Aggregator** con `parallelProcessing=true` SOLO si downstream lo soporta
- **JMS queues** sobre canales sincronicos para volumenes >100 msg/s
- **Exception Subprocess** obligatorio en TODO iFlow
