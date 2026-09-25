# C2 — Escenarios

Perspectiva: **QA Lead SAP** con criterio de Requirements Analyst. Convertís el
requerimiento en escenarios verificables y casos de prueba, incluidos los no
funcionales que aplican.

## Qué leer

1. `C1-captura/handoff.md` y `C1-captura/requerimiento.md`.
2. `C1-captura/fs.md`, `gap-analysis.md` y `preguntas.md` si existen.
3. **No leas `entradas/`.** Lo que necesitás de la documentación del cliente ya
   está en el requerimiento; si falta algo, es una pregunta abierta de C1.

## Qué producir

| Archivo | Obligatorio | Citas que exige el gate |
|---|---|---|
| `C2-escenarios/escenarios.md` | sí | una en **cada** sección `##` / `###` |
| `C2-escenarios/casos-prueba.md` | sí | al menos una |
| `C2-escenarios/handoff.md` | sí | — |

Toda cita tiene la forma `[C1-captura/requerimiento.md:N]` o
`[C1-captura/requerimiento.md:N-M]`, donde `N` es un número de línea del
archivo. El gate verifica que cada línea citada sea una regla `RQ-NN` no
retirada —en un rango, las del medio pueden ser líneas en blanco pero no títulos
ni reglas retiradas— y rechaza:

- las citas mal escritas;
- un `Fuente:` que nombra la regla sin la cita (`Fuente: RQ-11`);
- una cita **entre backticks o en un bloque de código**: no cuenta, porque ahí
  es un ejemplo, no una afirmación. Escribila como texto, también en tablas.

## `escenarios.md`

Un escenario por sección `###`, en Gherkin en español. Toda sección `##`, `###`
o `####` que tenga texto tiene que citar; para agrupar escenarios, usá un `##`
**sin texto debajo**, o que cite el rango de reglas que agrupa:

```markdown
### ESC-03 — Factura vencida pasa a gestión judicial

Fuente: [C1-captura/requerimiento.md:8]

- **Dado** un cliente de la sociedad 1000 con una factura vencida hace 91 días
- **Cuando** corre el proceso de clasificación
- **Entonces** la factura queda marcada para gestión judicial
- **Y** aparece en el reporte de cartera judicial
```

Cubrí, para cada regla:

- el camino feliz;
- el **negativo**: qué pasa cuando la condición no se cumple;
- el **límite**: 90 contra 91 días, cero, el máximo, el vacío;
- los **datos sucios** que el caso admita: nulls, moneda distinta, cliente
  bloqueado.

Y los **no funcionales** que apliquen, del catálogo NFR del stack:

| NFR | Cuándo aplica |
|---|---|
| Concurrencia | dos usuarios o jobs sobre el mismo objeto |
| Volumen | proceso masivo o reporte sobre tablas grandes |
| Idempotencia | reintentos, mensajes que llegan dos veces |
| Restart | jobs que se pueden cancelar a mitad |
| Autorizaciones | quién puede ver o ejecutar qué |

Un NFR sin regla que lo motive no se inventa: si el requerimiento no dice
volúmenes, es una pregunta abierta, no un escenario.

## `casos-prueba.md`

| ID | Escenario | Tipo | Precondiciones y datos | Pasos | Resultado esperado | Transacción / app | Prioridad | Fuente |
|---|---|---|---|---|---|---|---|---|

- `Tipo`: Funcional, Negativo, Límite o NFR.
- `Transacción / app`: dónde se ejecuta la prueba en SAP.
- `Fuente`: la cita al requerimiento.

## Si C1 cambió

Si se reabrió C1, `sdd estado` muestra C2 vieja. Antes de reaprobarla, revisá
cada cita contra el requerimiento nuevo: el gate garantiza que apunten a
reglas vigentes, no que sigan diciendo lo que el escenario necesita.

## `handoff.md` — para C3

- Escenarios que condicionan el diseño: volumen, concurrencia, integraciones.
- Reglas que el diseño no puede romper, con citas.
- Preguntas abiertas que siguen afectando al diseño.

## No hacer

- Escenarios sin cita, o citando `entradas/`.
- Copiar las reglas del requerimiento como escenarios sin decir qué se verifica.
- Casos de prueba sin resultado esperado verificable.
- Dejar `<!-- sdd:pendiente -->` en un archivo que se presenta.
