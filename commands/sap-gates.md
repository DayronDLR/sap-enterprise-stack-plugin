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

## Paso 0 — ¿Es un ajuste chico de configuración?

```bash
node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lib/clase-cambio.mjs"
```

Si responde `"clase":"config-trivial"`, el camino es corto. La clase exige que
CADA clave que cambia esté en una lista de lo seguro —la versión, la
descripción, metadatos del paquete, la versión concreta de una dependencia que
ya estaba, el título de la app, textos de i18n—, 30 líneas o menos, sin borrados y sin
hallazgos del scan. Una ruta, un host, un scope, un script o una librería sacan
el cambio de la clase. `xs-app.json`, `xs-security.json` y `.cdsrc.json` nunca
entran: definen la seguridad. Para `mta.yaml` y `ui5*.yaml` la clase necesita
`js-yaml` o `yaml` instalado en el proyecto (o en el stack); sin ninguno, un YAML
va por el camino completo.

- **Gate 1** igual (paso 1).
- **Gate 2** en esta misma sesión, **sin subagente**: leé el diff y confirmá
  seis cosas —la versión o el valor cambiado es el pedido; no hay secretos ni
  URLs de un entorno productivo; no cambia quién puede entrar ni qué puede hacer
  (login, roles, scopes, rutas públicas); el JSON/YAML es válido; las rutas y los
  nombres existen; y nada más cambió. Si todo está bien:
  `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/sellar-gate.sh" review`.
- **Gate 3 no aplica**: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/sellar-gate.sh" qa --config-trivial`.
  El script vuelve a calcular la clase y se niega a sellar si no se cumple.

Cualquier otra respuesta: los tres gates completos, pasos 1 a 3.

## Paso 1 — Gate 1: Quality

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/quality-gate.sh" --mode=cli
```

Si sale distinto de 0, **corregí los hallazgos antes de seguir**. No tiene sentido
gastar un code review sobre código que no pasa el linter.

## Paso 2 — Gate 2: Code Review

Invocá el agente `reviewer` sobre el diff de la sesión (`git diff HEAD`,
`git diff --cached HEAD` y los archivos sin trackear: lo staged y después
revertido en el working tree sólo aparece en el segundo). Que reporte hallazgos inline con severidad, sin generar
archivos.

Bloquea si reporta CRITICAL o HIGH. Si el resultado es aceptable, **anotá el
hash del árbol revisado** — no un `touch` pelado:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/sellar-gate.sh" review
```

## Paso 3 — Gate 3: QA + NFR

Invocá el agente `sap-qa` con el checklist de `${CLAUDE_PLUGIN_ROOT}/stack/agents/09-qa-testing/nfr-checklist.md`
—sólo las secciones de las tecnologías que toca el diff—. Tiene que responder **con evidencia**, no con supuestos: concurrencia,
volumen, idempotencia, restart-ability, observabilidad y locking.

Si pasa:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/sellar-gate.sh" qa
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

El Gate 1 recuerda sus aprobaciones por contenido: si nada cambió desde la
última vez que aprobó, no se repite (`tmp/.gate1-ok`).

Hay además un vencimiento por tiempo de 24 h, pero es una red, no el control:
evita que un flag olvidado aplique tras un cambio de base o de dependencias que
el árbol no captura. Los flags se consumen cuando la entrega efectivamente
ocurre (hook `post-commit`).
