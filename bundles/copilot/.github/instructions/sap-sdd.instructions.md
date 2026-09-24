---
applyTo: **
description: Ciclo SDD (spec-driven development) previo a codear — requerimiento, escenarios, diseño y plan con estimación, en una carpeta de proyecto que se presenta al cliente. Usalo SOLO cuando el arquitecto pida explícitamente una estimación, una propuesta de arquitectura previa o el SDD de un requerimiento. NUNCA para un fix, un report, un cambio puntual ni una tarea de desarrollo normal. Hoy crea el proyecto, verifica y aprueba cada fase, y lo empaqueta; los agentes de cada fase llegan en P3–P4 (ADR-014).
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

## Cerrar una fase: gate, aprobación humana, y recién ahí avanzar

Cada fase termina igual, y **el agente nunca avanza solo**:

1. Producí los artefactos de la fase (tabla de abajo) en su carpeta.
2. Corré el gate. Si falla, corregí y volvé a correrlo; no presentes una fase
   que no pasa.

   ```bash
   node "$SDD" gate <proyecto> C2
   ```

3. Presentá el resumen al arquitecto y **preguntá si aprueba**.
4. Sólo con un sí explícito, aprobá con su nombre. Eso escribe la entrada
   `DEC-NNN` en `decisiones.md` con el hash de lo aprobado:

   ```bash
   node "$SDD" aprobar <proyecto> C2 --decide "<nombre de quien aprobó>"
   ```

Nunca pongas en `--decide` un nombre que no te dieron, ni apruebes porque "el
gate pasó": el gate verifica la forma; la aprobación es de una persona.
Aprobar otra vez algo que no cambió no agrega otra decisión.

### Qué verifica el gate

| Chequeo | Falla si… |
|---|---|
| Fases anteriores | alguna no está aprobada, o quedó vieja |
| Completitud | falta un obligatorio, tiene menos de 100 caracteres o lleva `<!-- sdd:pendiente -->` |
| Whitelist | hay un archivo que la fase no declara |
| Citas | una `[C1-captura/requerimiento.md:N]` o `:N-M` apunta a una línea que no existe o está vacía, o está mal escrita; se cita `entradas/`; o falta cita donde se exige. Lo que está dentro de bloques de código no cuenta |
| Encoding | un obligatorio no es UTF-8 |

| Fase | Obligatorios | Opcionales | Citas exigidas |
|---|---|---|---|
| C1 | `requerimiento.md`, `fs.md`, `handoff.md` | `gap-analysis.md`, `preguntas.md` | — |
| C2 | `escenarios.md`, `casos-prueba.md`, `handoff.md` | — | una por sección `##`/`###` en escenarios; al menos una en casos |
| C3 | `diseno.md`, `arquitectura.sapdiag.json`, `handoff.md` | `arquitectura.drawio`, `arquitectura.svg`, `prototipo.html` | al menos una en diseño |
| C4 | `plan.md`, `handoff.md` | `estimacion.md` | al menos una en plan |

`requerimiento.md` es el texto normalizado del cliente: sus números de línea son
los que se citan, así que después de aprobar C1 no se reformatea sin reaprobar.

## Reabrir una fase

Editar cualquier cosa que una fase aprobada consumió —`entradas/`, o un
artefacto de una fase anterior— la deja **vieja**, y con ella a todas las que
siguen. No hay que acordarse de nada:

```bash
node "$SDD" estado <proyecto>        # qué quedó vieja y por qué edición
```

Se reaprueba en orden: primero la fase editada, después cada una de las
siguientes, cada una con su gate y su sí.

## Presentar

```bash
node "$SDD" empaquetar <proyecto>    # <raiz>/<proyecto>-AAAAMMDD-HHMMSS.zip
```

Lleva las carpetas de fase y, en la raíz, sólo `README.md`, `decisiones.md`,
`estado.json` y `.gitignore`: nada que empiece con punto adentro de las fases, y
ni `.git/` ni un `.env` ni notas sueltas en la raíz (la salida dice qué dejó
afuera). Sale **sin** `entradas/` (con `--con-entradas` si el arquitecto lo pide)
y se niega si hay una fase vieja. Las pendientes van como borrador.

## `entradas/`

Es la documentación original del cliente. La deja el arquitecto; el agente la
lee **sólo en C1** y sólo cuando se le pide. Las fases siguientes citan
`C1-captura/requerimiento.md`, nunca `entradas/`. No se copia fuera de la
carpeta del proyecto ni se escribe en logs: de ella sólo sale su hash.

Si el proyecto termina versionado, el Gate 1 y CI rechazan cualquier commit que
agregue algo bajo `entradas/` de un proyecto SDD, aunque se haya forzado con
`git add -f` o borrado en un commit posterior.

## Estado de la implementación

| Fase | Qué agrega | Estado |
|---|---|---|
| P1 | `init`, estructura y plantillas | disponible |
| P2 | `gate`, `aprobar`, `estado`, `empaquetar`; `entradas/` bloqueada en Gate 1 y CI | disponible |
| P3–P5 | Agentes cableados a C1–C4, `/sap-sdd` y traspaso a `/sap-techlead` | pendiente |
