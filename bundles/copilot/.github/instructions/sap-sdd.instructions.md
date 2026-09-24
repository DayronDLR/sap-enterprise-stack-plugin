---
applyTo: **
description: Ciclo SDD (spec-driven development) previo a codear — requerimiento, escenarios, diseño y plan con estimación, en una carpeta de proyecto que se presenta al cliente. Usalo SOLO cuando el arquitecto pida explícitamente una estimación, una propuesta de arquitectura previa o el SDD de un requerimiento. NUNCA para un fix, un report, un cambio puntual ni una tarea de desarrollo normal. Hoy crea la carpeta del proyecto; las fases C1–C4 llegan en P3–P4 (ADR-014).
---

# Ciclo SDD

> **Activación sólo a pedido (ADR-014 §5).** Si el pedido es un fix, un cambio
> puntual o una tarea de desarrollo, este skill no aplica: resolvé con el agente
> que corresponda.

Un proyecto SDD vive **fuera de todo repo de código**, bajo `~/sdd-projects/`
(o `SES_SDD_HOME`). La carpeta entera es el entregable.

## Resolver el CLI (una vez por sesión)

El motor viaja dentro del skill, y cada host lo instala en otro lugar: el
plugin de Claude, el checkout del stack, `.agents/` (Codex) u `.opencode/`
(OpenCode). Resolvelo una vez y **cortá si no aparece**: `node ""` sale 0 sin
hacer nada, y eso se lee como un éxito.

```bash
SDD=$(ls "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills/sap-sdd/bin/sdd.mjs" \
         skills/sap-sdd/bin/sdd.mjs \
         .agents/skills/sap-sdd/bin/sdd.mjs \
         .opencode/skills/sap-sdd/bin/sdd.mjs 2>/dev/null | head -1)
[ -n "$SDD" ] || { echo "✗ no encontré el motor SDD (skills/sap-sdd/bin/sdd.mjs)"; exit 1; }
node "$SDD" raiz
```

Copilot no tiene el motor: recibe este skill como instrucciones, sin `bin/`.

## Crear el proyecto

```bash
node "$SDD" init <proyecto>          # p. ej. aging-ar-mx
```

Es idempotente: sobre un proyecto existente sólo completa lo que falta y nunca
pisa un archivo. Si encuentra uno vacío o un `estado.json` roto, lo informa y
sale 1 en vez de decir "completo".

Se niega a crear el proyecto dentro de un repo git. Si tu `$HOME` es un repo
(dotfiles versionados), la raíz por defecto queda dentro de él: usá
`SES_SDD_HOME=/ruta/absoluta` fuera de todo repo.

## `entradas/`

Es la documentación original del cliente. La deja el arquitecto; el agente la
lee **sólo en C1** y sólo cuando se le pide. Las fases siguientes citan
`C1-captura/requerimiento.md`, nunca `entradas/`. No se copia fuera de la
carpeta del proyecto ni se escribe en logs.

## Estado de la implementación

| Fase | Qué agrega | Estado |
|---|---|---|
| P1 | `init`, estructura y plantillas | disponible |
| P2 | `gate`, `estado`, `empaquetar` | pendiente |
| P3–P5 | Fases C1–C4 y traspaso a `/sap-techlead` | pendiente |
