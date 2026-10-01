# CONTEXT.md — el registro de decisiones de una sesión compleja

`/sap-techlead` crea `.planning/CONTEXT.md` cuando la tarea toca más de 3 archivos
o más de 2 agentes (PASO 1.3), y `/sap-pause` lo resume en el checkpoint. Sirve
para que una decisión tomada por un subagente no se pierda cuando el contexto se
compacta, o cuando la sesión se retoma otro día.

## Estructura

```markdown
# Contexto — <tarea en una línea>

- **Inicio:** AAAA-MM-DD
- **Agentes:** 03-btp-cap, 04-fiori-ui5, 09-qa-testing

## Decisiones

### D-01 — <título corto>

- **Agente:** 03-btp-cap
- **Decisión:** qué se decidió, en una o dos líneas
- **Por qué:** el motivo, y la alternativa que se descartó
- **Evidencia:** `srv/pedidos-service.cds:42`
- **Afecta a:** `app/pedidos/webapp/manifest.json`

## Pendientes

- lo que quedó abierto, con el ID de la decisión que lo originó si aplica
```

## Reglas

- **Un ID por decisión, correlativo y para siempre.** `D-01`, `D-02`… Un ID no
  se reutiliza ni se renumera: `/sap-pause` y las decisiones siguientes lo citan.
- **Las decisiones no se borran.** Si una cambia, se agrega otra que dice a cuál
  reemplaza («reemplaza a D-03»).
- **La evidencia es una ubicación que se puede abrir**: `archivo:línea`, como en
  los hallazgos del reviewer. El hook de `SubagentStop` verifica que las citas
  `archivo:línea` que escribe un subagente existan de verdad. Una decisión sin
  evidencia se marca «sin evidencia», no se inventa una.
- **Sólo decisiones técnicas.** El avance de la tarea va en el plan y en el
  checkpoint, no acá.
