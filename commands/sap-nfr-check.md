---
model: claude-opus-4-7
---

Ejecuta una **validacion NFR manual** sobre el scope indicado (o sobre el diff de la sesion si no se indica scope).

Scope solicitado:

$ARGUMENTS

## Pasos

1. Lee `shared/non-functional-requirements.md` y `agents/09-qa-testing/nfr-checklist.md`
2. Si no hay scope explicito, ejecuta `git diff HEAD` para obtener los cambios de la sesion
3. Recorre el checklist NFR (9 secciones) item por item contra el codigo del scope
4. Para cada item responde:
   - `OK + evidencia` (ej: "se probo con 50.000 registros, latencia p95=180ms")
   - `N/A + justificacion` (ej: "no aplica: codigo de solo lectura sin estado")
   - `NO CUBIERTO` → bloqueante (CRITICAL o HIGH segun el item)
5. Devuelve hallazgos **inline en la conversacion** — NO generar archivos
6. Si no hay CRITICAL ni HIGH: ejecutar `touch tmp/.qa-nfr-done` para liberar el Stop hook

## Salida esperada

```text
🔥 VALIDACION NFR — [scope]

1. Concurrencia y Locking (CRITICAL)
   [ ] item 1 → OK / N/A / NO CUBIERTO + detalle
   ...

2. Procesamiento masivo (CRITICAL)
   ...

[... 9 secciones ...]

📊 RESUMEN
- CRITICAL no cubiertos: N
- HIGH no cubiertos: N
- MEDIUM no cubiertos: N

VEREDICTO: ✅ LISTO | ❌ BLOQUEADO ([razones principales])
```

Si hay items `NO CUBIERTO` en secciones CRITICAL (1, 2, 3, 7) o 2+ en HIGH (4, 5, 6, 9), marca BLOQUEADO y lista que falta y donde corregirlo.
