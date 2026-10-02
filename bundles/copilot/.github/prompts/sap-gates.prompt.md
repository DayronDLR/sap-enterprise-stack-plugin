---
name: sap-gates
description: Corre los 3 gates de la Definition of Done sobre el diff actual (quality, code review, QA+NFR).
argument-hint: solicitud en lenguaje natural
agent: agent
model: Claude Sonnet 4.6
---
# /sap-gates — Definition of Done bajo demanda

Corré los 3 gates de la DoD sobre el trabajo actual. Este comando es la forma
**explícita** de pedir la revisión: los gates ya no corren en cada turno, corren
acá o al momento de entregar (`git commit` / `git push` / `gh pr create`).

Argumentos opcionales: `${input:solicitud}`

- `--gate=1` / `--gate=2` / `--gate=3` → correr solo ese gate
- sin argumentos → los tres, en orden

## Paso 0 — ¿Qué profundidad exige el cambio?

```bash
node ".github/hooks/scripts/lib/nivel-revision.mjs"
```

El nivel lo decide el script, no la sesión, y `sellar-gate.sh` lo vuelve a
calcular: se niega a sellar una revisión más liviana que la que corresponde.

| Nivel | Cuándo | Gate 2 | Gate 3 |
| --- | --- | --- | --- |
| `config-trivial` | Cada clave cambiada está en una lista de lo seguro (versión, descripción, metadatos, versión concreta de una dependencia que ya estaba, título, i18n); ≤ 30 líneas, sin borrados ni hallazgos del scan | En esta sesión, sin subagente: los seis checks de abajo; sella `review --nivel=config-trivial` | No aplica: `qa --config-trivial` |
| `liviana` | Sólo markdown, textos i18n e imágenes, ≤ 300 líneas y **sin código** (fences, código indentado, `<pre>`/`<script>`) en ninguna de sus versiones | Subagente `reviewer` con `model: sonnet`, dimensiones 1, 2, 3 y 8, sin ejecutar nada | No aplica: `qa --nivel=liviana` |
| `estandar` | El resto: UI, tests, código fuera del backend, markdown con código | `reviewer` con `model: sonnet`, las ocho dimensiones; ejecutar sólo lo barato y decisivo | `sap-qa` con `model: sonnet`, sólo las secciones de `tecnologias` |
| `completa` | Seguridad (`xs-security`, `xs-app`, `.cdsrc`), configuración que instala o despliega, hooks/CI, scripts, backend CAP (`srv/`, `db/`, `.cds`), ABAP, HANA, credenciales, borrados, más de 400 líneas o algo ilegible | `reviewer` con `model: opus`, las ocho dimensiones; reproducir lo que se pueda | `sap-qa` con `model: opus`, con evidencia ejecutada (mutantes, concurrencia) |

El modelo se pasa en el parámetro `model` del Agent tool; un host que no deja
elegirlo usa el suyo y el resto del plan igual aplica. Si el nivel no se puede
calcular, es `completa`.

**Los seis checks de `config-trivial`:** la versión o el valor cambiado es el
pedido; no hay secretos ni URLs de un entorno productivo; no cambia
quién puede entrar ni qué puede hacer (login, roles, scopes, rutas públicas); el JSON/YAML es
válido; las rutas y los nombres existen; y nada más cambió. `xs-app.json`,
`xs-security.json` y `.cdsrc.json` nunca son `config-trivial`. Para `mta.yaml` y
`ui5*.yaml` la clase necesita `js-yaml` o `yaml` en el proyecto (o en el stack).

## Paso 1 — Gate 1: Quality

```bash
bash ".github/hooks/scripts/quality-gate.sh" --mode=cli
```

Si sale distinto de 0, **corregí los hallazgos antes de seguir**. No tiene sentido
gastar un code review sobre código que no pasa el linter.

## Paso 2 — Gate 2: Code Review

Antes de lanzar el revisor, preguntá si hay una ronda anterior —con
`--con-hallazgos` sólo si tenés el reporte de esa ronda para pasárselo—:

```bash
node ".github/hooks/scripts/lib/ronda-revision.mjs" delta review --nivel=<nivel> [--con-hallazgos]
```

- `hayRonda: false` → revisión entera: el diff de la sesión (`git diff HEAD`,
  `git diff --cached HEAD` y los archivos sin trackear; lo staged y después
  revertido en el working tree sólo aparece en el segundo).
- `hayRonda: true` → **sólo** los archivos de `cambiados` y `fueraDelDiff`, con
  los hallazgos de la ronda anterior: el revisor confirma que se cerraron y
  revisa lo nuevo. El delta mira índice y working tree, vuelve a traer los
  archivos con hallazgos abiertos y no acota si la ronda anterior fue más liviana.

Fijá lo que va a ver el revisor **antes** de lanzarlo, y cerrá la ronda al
terminar, haya pasado o no:

```bash
node ".github/hooks/scripts/lib/ronda-revision.mjs" iniciar review --nivel=<nivel>
# … el reviewer, con el nivel y su modelo (Paso 0); hallazgos inline, sin archivos …
node ".github/hooks/scripts/lib/ronda-revision.mjs" cerrar review --veredicto=<aprueba|bloquea> --abiertos=<archivos con hallazgos>
```

Bloquea si reporta CRITICAL o HIGH. Si el resultado es aceptable, sellá con el
nivel con que se revisó:

```bash
bash ".github/hooks/scripts/sellar-gate.sh" review --nivel=<nivel>
```

## Paso 3 — Gate 3: QA + NFR

Si el nivel es `config-trivial` o `liviana`, el Gate 3 no aplica. Sellá según el
nivel; el script lo vuelve a calcular y se niega si el cambio exige más:

```bash
bash ".github/hooks/scripts/sellar-gate.sh" qa --config-trivial   # config-trivial
bash ".github/hooks/scripts/sellar-gate.sh" qa --nivel=liviana    # liviana
```

Si no, el mismo ciclo de rondas (`delta` / `iniciar` / `cerrar` con `qa`). Invocá el agente
`sap-qa` con el modelo del nivel y el checklist de
`.github/agents/09-qa-testing/nfr-checklist.md` —sólo las secciones de las
`tecnologias` que devolvió el Paso 0; si la lista vino vacía, **todas**—. Tiene que responder **con evidencia**, no
con supuestos: concurrencia, volumen, idempotencia, restart-ability,
observabilidad y locking. Si pasa:

```bash
bash ".github/hooks/scripts/sellar-gate.sh" qa --nivel=<nivel>
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