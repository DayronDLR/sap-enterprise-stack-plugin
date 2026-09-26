---
name: sap-sdd
description: Ciclo SDD (spec-driven development) previo a codear — requerimiento, escenarios, diseño y plan con estimación, en una carpeta de proyecto que se presenta al cliente. Usalo SOLO cuando el arquitecto pida explícitamente una estimación, una propuesta de arquitectura previa o el SDD de un requerimiento. NUNCA para un fix, un report, un cambio puntual ni una tarea de desarrollo normal. Crea el proyecto, conduce C1–C4 con gate y aprobación por fase, lo empaqueta y lo traspasa a /sap-techlead (ADR-014).
---

<!-- prompt-meta: last_reviewed=2026-09-24; sap_baseline=2025/2026; review_cycle_days=180 -->

# Ciclo SDD

> **Activación sólo a pedido (ADR-014 §5).** Si el pedido es un fix, un cambio
> puntual o una tarea de desarrollo, este skill no aplica: resolvé con el agente
> que corresponda.

Un proyecto SDD vive **fuera de todo repo de código**, bajo `~/sdd-projects/`
(o `SES_SDD_HOME`). La carpeta entera es el entregable.

## Resolver el CLI (una vez por sesión)

El motor viaja dentro del skill, y cada host lo instala en otro lugar: el
plugin de Claude, el checkout del stack, `.agents/` (Codex), `.opencode/`
(OpenCode) o `.github/` (Copilot). Resolvelo una vez y **cortá si no aparece**: `node ""` sale 0 sin
hacer nada, y eso se lee como un éxito.

```bash
SDD=$(ls "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills/sap-sdd/bin/sdd.mjs" \
         skills/sap-sdd/bin/sdd.mjs \
         .agents/skills/sap-sdd/bin/sdd.mjs \
         .opencode/skills/sap-sdd/bin/sdd.mjs \
         .github/skills/sap-sdd/bin/sdd.mjs 2>/dev/null | head -1)
[ -n "$SDD" ] || { echo "✗ no encontré el motor SDD (skills/sap-sdd/bin/sdd.mjs)"; exit 1; }
node "$SDD" raiz
```

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

## Producir una fase

Cada fase tiene su guía en `reference/`: qué leer, qué producir, con qué forma
y qué no hacer. Leela entera antes de escribir el primer artefacto.

| Fase | Guía |
|---|---|
| C1 Captura | `reference/C1-captura.md` |
| C2 Escenarios | `reference/C2-escenarios.md` |
| C3 Diseño | `reference/C3-diseno.md` |
| C4 Plan y estimación | `reference/C4-plan.md` |

El comando `/sap-sdd <proyecto> [fase]` conduce el ciclo entero: crea el
proyecto, retoma en la fase que corresponde y cierra cada una con el protocolo
de abajo.

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
| Citas | una `[C1-captura/requerimiento.md:N]` o `:N-M` no apunta a una regla `RQ-NN` vigente, o está mal escrita; un `Fuente:` sin cita; se cita `entradas/`; o falta cita donde se exige. Lo que está entre backticks o en bloques de código no cuenta |
| Reglas estables (C1) | una regla que cita una fase aprobada cambió de línea o desapareció; o un código `RQ-NN` está repetido |
| Encoding | un obligatorio no es UTF-8 |
| Inventario (C3) | falta la tabla «Inventario de objetos», un `OBJ-NN` repetido, un objeto sin cita o con Clean Core `Modificación` |
| Diagrama (C3) | `arquitectura.sapdiag.json` no pasa `sap-diagrams` con el perfil showcase |
| Estimación (C4) | una línea sobre un objeto que no está en el inventario, o un objeto sin estimar; O ≤ M ≤ P roto; E ≠ 0,3·O + 0,4·M + 0,3·P; M > 40 h; un `%` en Base; contingencia sin riesgo `R-NN` de la tabla de riesgos del plan, con Prob fuera de (0, 1) o ≠ Prob × Impacto; totales que no son la cuenta o con filas de más |

| Fase | Obligatorios | Opcionales | Citas exigidas |
|---|---|---|---|
| C1 | `requerimiento.md`, `fs.md`, `handoff.md` | `gap-analysis.md`, `preguntas.md` | al menos una en fs |
| C2 | `escenarios.md`, `casos-prueba.md`, `handoff.md` | — | una por sección `##`/`###`/`####` con texto en escenarios; al menos una en casos |
| C3 | `diseno.md`, `arquitectura.sapdiag.json`, `handoff.md` | `arquitectura.drawio`, `arquitectura.svg`, `prototipo.html` | al menos una en diseño |
| C4 | `plan.md`, `estimacion.md`, `handoff.md` | — | al menos una en plan |

`requerimiento.md` es el texto normalizado del cliente, una regla `RQ-NN` por
línea: sus números de línea son los que se citan. Una vez citadas, las reglas no
se mueven: las nuevas van al final y las que no aplican se marcan `(retirado)`.

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

## Pasar a desarrollo

En la máquina donde se implementa (BAS), el paquete se importa fuera del repo de
código y se genera el brief para `/sap-techlead`:

```bash
node "$SDD" importar <proyecto>-AAAAMMDD-HHMMSS.zip
node "$SDD" traspaso <proyecto>       # exige C1–C4 aprobadas y al día
```

Las aprobaciones sobreviven al viaje porque están ancladas al contenido. La guía
de uso completa para el arquitecto está en `docs/SDD.md` del stack.

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
| P3 | `/sap-sdd` y guías de C1 y C2 | disponible |
| P4 | Guías de C3 y C4; inventario, diagrama y estimación verificados | disponible |
| P5 | `importar` y `traspaso`: el SDD aprobado pasa a `/sap-techlead` | disponible |
