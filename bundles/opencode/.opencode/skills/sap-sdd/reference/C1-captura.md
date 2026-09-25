# C1 — Captura

Perspectiva: **Requirements Analyst SAP senior**. Convertís la documentación
del cliente en un requerimiento que se pueda citar línea por línea, una
especificación funcional y la lista de lo que falta saber.

Es la única fase que lee `entradas/`.

## Qué leer

1. Todo `entradas/`. Se aceptan `.md` y `.txt`. Si hay PDF, Word o Excel,
   listalos y pedile al arquitecto que los convierta a texto; no adivines su
   contenido.
2. Nada más. El requerimiento sale de lo que el cliente escribió, no de lo que
   un proyecto típico suele necesitar.

## Qué producir

| Archivo | Obligatorio | Para qué |
|---|---|---|
| `C1-captura/requerimiento.md` | sí | La fuente que citan todas las fases siguientes |
| `C1-captura/fs.md` | sí | La especificación funcional |
| `C1-captura/handoff.md` | sí | Lo que C2 necesita para empezar |
| `C1-captura/gap-analysis.md` | si hay estándar SAP que evaluar | Fit-to-standard |
| `C1-captura/preguntas.md` | si queda algo abierto | Lo que la documentación no dice |

Ningún otro archivo: el gate rechaza lo que no está en esta tabla.

## `requerimiento.md` — la regla que sostiene todo el ciclo

Las fases siguientes lo citan como `[C1-captura/requerimiento.md:N]`, y el gate
verifica que la línea `N` exista y no esté vacía. Por eso:

- **Una afirmación por línea.** Una regla de negocio, un dato, una restricción.
  Nada de párrafos: una cita tiene que apuntar a algo que se pueda verificar.
- **Con código.** `RQ-NN` al principio de cada línea, para que una persona
  también la pueda nombrar.
- **Con su fuente.** Al final de la línea, de qué parte de `entradas/` sale.
  Es la única fase donde se cita `entradas/`.
- **Sin interpretar.** Lo que el cliente dijo, normalizado. Lo que vos deducís
  va a `fs.md`; lo que no está claro, a `preguntas.md`.
- **Estable.** Las citas son por número de línea, así que una regla no se
  mueve una vez que otra fase la citó. El gate de C1 lo verifica: si C2 ya se
  aprobó y una regla cambió de línea o desapareció, no deja reaprobar C1.
  - Una regla **nueva** va **al final del archivo**, con el código siguiente,
    aunque temáticamente pertenezca a otra sección. Si hace falta, se abre al
    final una sección `## Agregadas en revisión`.
  - Una regla que **ya no aplica** no se borra: se deja en su línea como
    `RQ-NN (retirado) <motivo>`. El gate no deja citarla.
  - Una regla que **cambia** se reescribe en su misma línea.
  - Una regla que ninguna fase aprobada cita se puede mover; antes de que C2
    esté aprobada, C1 se reordena libremente.
  - Si el requerimiento hay que **reescribirlo entero** con fases posteriores
    aprobadas, no se reescribe encima: se retiran las reglas viejas en su línea,
    se agregan las nuevas al final y se reaprueban C2 en adelante citando las
    nuevas. Si el cambio es tan grande que el requerimiento ya es otro, conviene
    un proyecto SDD nuevo.

```markdown
# Requerimiento — <proyecto>

## Alcance
RQ-01 El proceso cubre la cobranza de clientes nacionales de la sociedad 1000. (entradas/brief.md §1)
RQ-02 Quedan fuera los clientes intercompany. (entradas/brief.md §1)

## Reglas de negocio
RQ-03 Una factura vencida hace más de 90 días pasa a gestión judicial. (entradas/minuta-0312.txt)
```

## `fs.md` — especificación funcional

Estructura obligatoria, la misma del agente Requirements Analyst:

- Header (Proyecto, Módulo, Versión, Autor, Fecha, Estado)
- Business Background
- Business Requirements
- Current Process (AS-IS)
- Proposed Process (TO-BE)
- Functional Description (cómo funciona en SAP)
- Configuration Requirements
- Development Requirements
- Interface Requirements
- Authorization Requirements
- Test Scenarios
- Open Issues / Assumptions

Nombrá las transacciones y apps SAP que aplican (p. ej. FBL5N, F-28, app Manage
Customer Line Items) y aplicá Clean Core: estándar primero; extensión vía BAdI,
CDS, RAP o BTP; modificación nunca. Cada requisito de negocio cita la línea del
requerimiento de la que sale, como `[C1-captura/requerimiento.md:N]`: el gate
exige al menos una cita en `fs.md` y que cada cita apunte a una línea `RQ-`.

## `gap-analysis.md` — opcional

| Gap ID | Descripción | Módulo | Tipo | Prioridad | Esfuerzo | Solución | Fuente |
|---|---|---|---|---|---|---|---|

`Tipo` es Configuración, Extensión (BAdI/CDS/RAP/BTP) o Proceso. `Fuente` cita el
requerimiento.

## `preguntas.md` — opcional

Una pregunta por fila: qué falta saber, a quién preguntarle, qué fase bloquea y
qué supuesto tomaste mientras tanto.

## `handoff.md` — para C2

- Alcance: qué entra y qué no, con citas.
- Actores y roles.
- Reglas de negocio que C2 tiene que convertir en escenarios, con citas.
- Supuestos tomados.
- Preguntas abiertas que afectan a C2.

## No hacer

- Inventar volúmenes, reglas o integraciones que la documentación no menciona.
- Citar `entradas/` fuera de `requerimiento.md`.
- Copiar párrafos enteros del cliente a `fs.md`: se resume y se cita.
- Dejar `<!-- sdd:pendiente -->` en un archivo que se presenta.
