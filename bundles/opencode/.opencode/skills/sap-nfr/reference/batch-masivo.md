# Procesamiento masivo, chunking y restart-ability

> Detalle del catálogo NFR del stack. Se lee bajo demanda.

## 2. Procesamiento Masivo / Batch

Cuando un proceso lee/escribe >1.000 registros, el diseño debe incluir:

| Tecnica | ABAP | CAP/Node | HANA |
|---|---|---|---|
| Chunking | `SELECT ... PACKAGE SIZE N` | `SELECT…limit(n)` paginado por clave o por estado | `OFFSET/FETCH NEXT` o particion |
| Tamaño de paquete | 1.000–5.000 (datos), 100–500 (logica pesada) | 500–2.000 | depende particion |
| Commit boundary | cada paquete | una `cds.tx(async () => …)` por ítem o por chunk | `COMMIT` explicito |
| Restart-ability | flag de "procesado" en tabla origen | checkpoint en tabla aux | timestamp + watermark |
| Paralelismo | `SPTA_PARA_PROCESS_START_2` / aRFC | N instancias / `cds.spawn` con **claim atómico** (`UPDATE … where status='P'` + relectura por `claimedBy`); Node no tiene SKIP LOCKED | particion fisica |
| Progreso visible | log SLG1 cada paquete | `cds.log()` cada N | tabla de monitoreo |
| Cancelacion limpia | check `sy-ucomm` en cada paquete | abort signal | `STATEMENT_HINT('LIMIT')` |

### Reglas duras

- **NUNCA** un `SELECT ... INTO TABLE` sin `PACKAGE SIZE` (o paginación por clave) cuando el universo puede crecer
- **NUNCA** un `COMMIT WORK` dentro de `SELECT … PACKAGE SIZE … ENDSELECT`: cierra el cursor. Un job que commitea por paquete pagina por clave (`ORDER BY` + `UP TO n ROWS` desde el checkpoint)
- **NUNCA** un `LOOP AT … MODIFY DB` (acoplar SELECT y UPDATE)
- **NUNCA** un job sin estrategia de reinicio definida (¿que pasa si cae en el registro 47.000?)
- **SIEMPRE** estimar volumen pico antes de elegir tamaño de paquete
- **SIEMPRE** medir en QAS con volumen ≥80% del pico productivo antes de marcar como "listo"

## 5. Restart-ability y Recovery

- Todo job masivo debe poder reanudarse desde el ultimo registro procesado
- Tabla de checkpoint con: `proceso_id`, `ultimo_id_procesado`, `timestamp`, `usuario`, `status`
- Logs estructurados en SLG1 (ABAP) / `cds.log()` (CAP) / Message Monitoring (CPI)
- Mensajes con severidad correcta: INFO progreso, WARNING saltos, ERROR datos invalidos, ABORT corte

## 3. Idempotencia

Toda operacion que puede reintentar (interface, job, retry de usuario) debe ser idempotente.

- **Clave natural unica** como restricción en la base (PK / índice único / `@assert.unique`): se hace el INSERT y se captura la violación (ABAP `sy-subrc = 4`, HANA error 301, CAP: el error de la base tal cual). **Nunca** un SELECT antes del INSERT: dos procesos ven «no existe» a la vez
- **UPSERT explicito** (`MODIFY` con clave completa) en lugar de INSERT
- **Token de idempotencia** en headers de APIs externas
- **Replay sin efectos colaterales**: el segundo intento produce el mismo resultado que el primero
- **Compensating actions** documentadas si la operacion no puede ser idempotente nativamente
