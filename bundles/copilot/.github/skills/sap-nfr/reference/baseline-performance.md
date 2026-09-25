# Baseline de performance: captura, umbrales y comparación

> Detalle del catálogo NFR del stack. Se lee bajo demanda.

## 8. Performance Baseline — Captura y Comparacion (BLOQUEANTE)

Toda tarea que toque codigo productivo debe **capturar un baseline en QAS antes del cambio** y compararlo despues. Bloquea si la regresion supera los umbrales.

### Que capturar (siempre en QAS con volumen ≥80% del pico)

| Metrica | ABAP | CAP / Node | HANA | CPI |
|---|---|---|---|---|
| Runtime (p50 / p95) | SE30 / SAT / ST05 | `process.hrtime()` + APM | `M_SQL_PLAN_CACHE` | MPL `processingTime` |
| Memoria pico | SM50 → "Memory" / `cl_abap_memory_utilities` | `process.memoryUsage()` | `M_HOST_RESOURCE_UTILIZATION` | MPL attachment size |
| DB calls / IO | ST05 traza | `cds.trace` / DB log | `M_EXPENSIVE_STATEMENTS` | iFlow trace |
| CPU | SM50 / SAR | APM | `M_SERVICE_THREADS` | tenant metrics |

### Donde guardar

Tabla / fichero `performance-baseline.json` versionado en el repo del proyecto:

```json
{
  "objeto": "ZCL_ORDER_PROCESSOR",
  "test_case": "procesar_50000_pedidos",
  "baseline_ts": "2026-06-22T10:00:00Z",
  "qas_volume": 50000,
  "runtime_p95_ms": 12500,
  "memory_peak_mb": 480,
  "db_calls": 142,
  "executed_by": "ci-user@cliente.com"
}
```

### Umbrales de regresion (bloqueantes)

| Metrica | Umbral verde | Warning | Bloqueante |
|---|---|---|---|
| Runtime p95 | ≤ baseline ×1.10 | baseline ×1.10–1.20 | > baseline ×1.20 |
| Memoria pico | ≤ baseline ×1.15 | baseline ×1.15–1.30 | > baseline ×1.30 |
| DB calls | ≤ baseline ×1.00 | baseline ×1.00–1.10 | > baseline ×1.10 |
| CPU | ≤ baseline ×1.15 | — | > baseline ×1.30 |

**Regla dura**: regresion >20% en runtime p95 **bloquea el cierre**, salvo que el cambio funcional la justifique explicitamente (documentar en commit + sign-off del Tech Lead).

### Como integrarlo al flujo

1. Antes de tocar codigo: ejecutar test de performance en QAS y guardar baseline en repo
2. Tras el cambio: re-ejecutar el mismo test, comparar contra baseline
3. Si regresion ≥ umbral bloqueante: corregir antes de cerrar
4. Tras release a PRD: el baseline nuevo reemplaza el anterior (commit de "performance baseline post-release")

### Anti-patrones

- "No medi performance porque el cambio es pequeño" — TODO cambio puede tener regresion
- Medir solo en DEV con dataset pequeño — no es representativo
- Aceptar regresion sin justificacion porque "es solo 25%"
- No versionar el baseline — sin baseline historico no hay comparacion posible
