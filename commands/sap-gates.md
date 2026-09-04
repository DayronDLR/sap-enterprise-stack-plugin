---
description: "Corre los 3 gates de la Definition of Done sobre el diff actual (quality, code review, QA+NFR)."
model: claude-sonnet-4-6
---

# /sap-gates — Definition of Done bajo demanda

Corré los 3 gates de la DoD sobre el trabajo actual. Este comando es la forma
**explícita** de pedir la revisión: los gates ya no corren en cada turno, corren
acá o al momento de entregar (`git commit` / `git push` / `gh pr create`).

Argumentos opcionales: `$ARGUMENTS`

- `--gate=1` / `--gate=2` / `--gate=3` → correr solo ese gate
- sin argumentos → los tres, en orden

## Paso 1 — Gate 1: Quality

```bash
bash hooks/scripts/quality-gate.sh --mode=cli
```

Si sale distinto de 0, **corregí los hallazgos antes de seguir**. No tiene sentido
gastar un code review sobre código que no pasa el linter.

## Paso 2 — Gate 2: Code Review

Invocá el agente `reviewer` sobre el diff de la sesión (`git diff HEAD` más los
archivos sin trackear). Que reporte hallazgos inline con severidad, sin generar
archivos.

Bloquea si reporta CRITICAL o HIGH. Si el resultado es aceptable, **anotá el
hash del árbol revisado** — no un `touch` pelado:

```bash
git write-tree >> tmp/.review-done
```

## Paso 3 — Gate 3: QA + NFR

Invocá el agente `sap-qa` con el checklist de `shared/non-functional-requirements.md`
(§9). Tiene que responder **con evidencia**, no con supuestos: concurrencia,
volumen, idempotencia, restart-ability, observabilidad y locking.

Si pasa:

```bash
git write-tree >> tmp/.qa-nfr-done
```

## Cierre

Reportá al dev, en una tabla corta: gate, resultado, hallazgos abiertos.

El flag guarda los **hashes de árbol** revisados, uno por línea, y solo cubre esos.
Se **agrega** (`>>`), no se pisa: así dos sesiones trabajando en paralelo sobre el
mismo repo no se invalidan la una a la otra.
Cualquier edición posterior —aunque sea una línea— lo invalida, porque el árbol
cambia. Es a propósito: "revisé esto" tiene que significar esto y no otra cosa.

El flujo es: **correr los gates → no tocar nada → entregar.** Si el gate rechaza
diciendo "corrió, pero sobre OTRO árbol", es que hubo una edición en el medio.

Hay además un vencimiento por tiempo de 24 h, pero es una red, no el control:
evita que un flag olvidado aplique tras un cambio de base o de dependencias que
el árbol no captura. Los flags se consumen cuando la entrega efectivamente
ocurre (hook `post-commit`).
