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

Bloquea si reporta CRITICAL o HIGH. Si el resultado es aceptable:

```bash
touch tmp/.review-done
```

## Paso 3 — Gate 3: QA + NFR

Invocá el agente `sap-qa` con el checklist de `shared/non-functional-requirements.md`
(§9). Tiene que responder **con evidencia**, no con supuestos: concurrencia,
volumen, idempotencia, restart-ability, observabilidad y locking.

Si pasa:

```bash
touch tmp/.qa-nfr-done
```

## Cierre

Reportá al dev, en una tabla corta: gate, resultado, hallazgos abiertos.

Los flags valen **30 minutos** y se consumen en la primera entrega. Un commit
posterior con código nuevo vuelve a pedir los gates — que es la intención: se
revisa lo que se entrega, no lo que se revisó hace media hora.
