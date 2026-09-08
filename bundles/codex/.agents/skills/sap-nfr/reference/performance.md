# Performance: smells, obligaciones y observabilidad

> Detalle del catálogo NFR del stack. Se lee bajo demanda.

## 4. Performance

### Smells prohibidos

- `SELECT *` en codigo productivo
- `SELECT` dentro de `LOOP` sin `FOR ALL ENTRIES` o JOIN
- Subqueries correlacionados sin justificacion
- Funciones escalares ABAP dentro de `WHERE` (evita uso de indice)
- `READ TABLE` sin `BINARY SEARCH` o `WITH KEY` en tablas sorted/hashed
- Nested `LOOP` cuadratico (O(n²)) sobre tablas internas grandes

### Obligaciones positivas

- Indices secundarios para campos de filtro frecuente (validar con SE16 / `EXPLAIN PLAN`)
- Buffer de tablas Z de configuracion (`Single records` o `Full`)
- `AMDP` / `CDS Table Function` para logica analitica pesada
- Calculation Views sin `SELECT *` en proyecciones
- En CAP: `$top`, `$skip`, `growing=true` en listas; lazy load de asociaciones
- En Fiori: `growing` + `growingThreshold` + `growingScrollToLoad`

## 6. Observabilidad

- ABAP: SLG1 con object/subobject por modulo, no genericos
- CAP: `cds.log('mi-modulo').info(...)` con namespace propio
- CPI: Message Monitoring + Alert Notification Service en errores criticos
- HANA: `M_SQL_PLAN_CACHE` + `M_EXPENSIVE_STATEMENTS` revisado pre-PRD
- **Sin observabilidad no hay sign-off** — el QA debe verificar que los logs existen y son utiles
