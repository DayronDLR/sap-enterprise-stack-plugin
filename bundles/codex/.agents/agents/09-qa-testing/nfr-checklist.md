# NFR Checklist — Gate 3 (QA + NFR)

> Invocado por `/sap-gates`, o por `mandatory-review.sh` —que corre desde
> `.husky/pre-commit` y desde el gate de entrega— cuando hay cambios productivos.
> Aplicar contra el **diff de la sesion**. Devolver hallazgos inline (sin archivos).

## Como usarlo

1. Leer cada item; responder con UNA de estas categorias:
   - `OK + evidencia` (ej: "se probo con 50.000 registros, latencia p95=180ms").
     Si la evidencia es código, citalo como `archivo:línea` (`srv/pedidos.js:88`):
     un hook verifica que la ubicación exista
   - `N/A + justificacion` (ej: "no aplica: el codigo es solo lectura sin estado")
   - `NO CUBIERTO` → **bloqueante** (CRITICAL o HIGH segun el item)
2. Tras completar, ejecutar `bash ".agents/hooks/scripts/sellar-gate.sh" qa` solo si NO hay CRITICAL ni HIGH.

## 1. Concurrencia y Locking (CRITICAL)

- [ ] ¿Que pasa si dos usuarios ejecutan esto al mismo tiempo? Documentar el comportamiento esperado.
- [ ] ABAP: ¿hay ENQUEUE_E* antes de UPDATE/MODIFY en tablas con lock object? ¿hay DEQUEUE en el camino feliz Y en el de error?
- [ ] RAP: ¿el BDEF tiene `lock master`? ¿se maneja `CX_ABAP_BEHV_CONFLICT` en EML?
- [ ] CAP: ¿las entidades con concurrencia alta tienen `@odata.etag`? ¿`cds.tx(req)` por request?
- [ ] HANA: ¿se usa `FOR UPDATE NOWAIT` en reservas / asignacion de numeros?
- [ ] Integration: ¿hay deduplicacion por `MessageID` en el receiver?

## 2. Procesamiento masivo (CRITICAL)

- [ ] ¿Hay `SELECT ... PACKAGE SIZE N` para universos crecientes? (NUNCA `SELECT ... INTO TABLE` sin limite)
- [ ] ¿COMMIT WORK por paquete (cada 500-2000 registros)? NO un solo COMMIT al final.
- [ ] ¿NO hay `LOOP AT ... MODIFY DB` acoplado?
- [ ] CAP: ¿chunks via `for await`? ¿`Promise.allSettled` con limite de concurrencia?
- [ ] ¿Se midio en QAS con volumen >=80% del pico productivo estimado? Adjuntar metricas.

## 3. Idempotencia (CRITICAL)

- [ ] ¿Que pasa si el mensaje / job / request llega DOS veces? El resultado debe ser el mismo.
- [ ] ¿La clave natural es única en la base (PK / índice único) y el INSERT trata el duplicado, o se usa `MODIFY` con clave completa (UPSERT)? Un SELECT previo al INSERT NO cuenta: es una carrera
- [ ] APIs externas: ¿se acepta `Idempotency-Key` header? ¿se respeta?
- [ ] Si la operacion NO puede ser idempotente nativamente: ¿hay accion compensatoria documentada?

## 4. Restart-ability (HIGH)

- [ ] ¿Que pasa si el proceso se cancela en el registro N/2? ¿Puede reanudarse?
- [ ] ¿Hay tabla de checkpoint con `proceso_id`, `ultimo_id`, `timestamp`, `usuario`, `status`?
- [ ] ¿Se valida que NO se re-procesen registros ya completados?
- [ ] ¿Se simulo cancelacion en la prueba de QAS? Adjuntar evidencia.

## 5. Performance (HIGH)

- [ ] ¿NO hay `SELECT *` en codigo productivo?
- [ ] ¿NO hay `SELECT` dentro de `LOOP` sin `FOR ALL ENTRIES` o JOIN?
- [ ] ¿Indices secundarios para los filtros frecuentes? (`SE16` / `EXPLAIN PLAN`)
- [ ] CAP: ¿`$top`/`$skip`/`growing=true` en listas? ¿lazy load de asociaciones?
- [ ] Fiori: ¿`growing` + `growingThreshold` + `growingScrollToLoad` en listas largas?
- [ ] HANA: ¿se reviso `M_SQL_PLAN_CACHE` y `M_EXPENSIVE_STATEMENTS` pre-PRD?

## 6. Observabilidad (HIGH)

- [ ] ABAP: ¿SLG1 con object/subobject ESPECIFICOS al modulo (no genericos)?
- [ ] CAP: ¿`cds.log('mi-modulo').info(...)` con namespace propio?
- [ ] CPI: ¿Message Monitoring + Alert Notification Service en errores criticos?
- [ ] ¿El log seria UTIL para diagnosticar un problema de PRD a las 3 AM? (incluye: input, contexto, error, accion sugerida)
- [ ] ¿El usuario ve progreso si el proceso dura >30 segundos?

## 7. Seguridad y Access Control (CRITICAL)

- [ ] CDS ABAP: `@AccessControl.authorizationCheck: #CHECK`
- [ ] CAP: `@requires` / `@restrict` en TODA accion que modifica estado
- [ ] Fiori: autorizacion validada en backend (no solo en frontend)
- [ ] No hay credenciales / URLs / textos hardcodeados (ver `shared/core-dev-principles.md`)

## 8. Datos sucios y casos limite (MEDIUM/HIGH)

- [ ] ¿Se probo con nulls, strings vacios, encoding raro (UTF-8 con BOM, caracteres especiales)?
- [ ] ¿Se probo con valores limite (0, -1, MAX_INT, fechas en futuro/pasado lejano)?
- [ ] ¿Se probo con cantidades fraccionales / unidades de medida no estandar?
- [ ] ¿Que pasa si una asociacion / foreign key esta rota?

## 9. Tests automatizados (HIGH)

- [ ] ABAP: tests con `cl_abap_behv_test_environment` (RAP) o ABAP Unit (logica)
- [ ] CAP: `cds.test()` con casos positivos Y negativos
- [ ] Fiori: OPA5 para flujos criticos, QUnit para formatters
- [ ] Coverage >=70% en logica nueva

## 10. Performance Baseline (HIGH)

- [ ] ¿Existe baseline pre-cambio en `performance-baseline.json` (runtime p95, memoria, DB calls) ejecutado en QAS con volumen >=80% del pico?
- [ ] ¿Se re-ejecuto el mismo test post-cambio con el mismo dataset?
- [ ] Comparacion runtime p95: ¿incremento ≤ 20%? (umbral bloqueante segun `shared/non-functional-requirements.md` seccion 8)
- [ ] Comparacion memoria pico: ¿incremento ≤ 30%? (bloqueante si supera)
- [ ] Comparacion DB calls: ¿incremento ≤ 10%? (bloqueante si supera — indica N+1 o falta de batching)
- [ ] ¿Se corrio el `perf:compare` del stack contra el baseline anterior? (ver `docs/PERF-RUNNER.md`)
- [ ] Si hubo regresion: ¿esta justificada en commit + sign-off del Tech Lead?

## Reglas de cierre

- Hay 1+ items `NO CUBIERTO` en seccion 1, 2, 3 o 7 (CRITICAL) → **BLOQUEAR cierre**
- Hay 2+ items `NO CUBIERTO` en seccion 4, 5, 6, 9, 10 (HIGH) → **BLOQUEAR cierre**
- Regresion de performance >20% en runtime p95 sin justificacion → **BLOQUEAR cierre**
- Solo items MEDIUM sin cubrir → warning visible, NO bloquea
- Si bloqueas, devolver: que falta, en que archivo se ve el problema, que hay que agregar/cambiar
