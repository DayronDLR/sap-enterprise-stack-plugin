# SAP Enterprise Stack — Claude Code Plugin

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Un stack completo de desarrollo SAP dentro de Claude Code. Instalás el plugin y
tenés **11 agentes SAP especializados**, un **orquestador** que enruta por
lenguaje natural, **subagentes** de apoyo, **skills SAP de referencia**, **gates
de calidad (Definition of Done)** y **5 MCP servers SAP** — sin clonar ningún
repo.

- **Agentes de desarrollo** (Opus): ABAP, CAP/BTP, Fiori/UI5, HANA, Integration.
- **Agentes de soporte** (Sonnet): Basis, Migration, QA, DevOps, Requirements, Docs.
- **Entorno asumido:** S/4HANA 2023 + BTP, landscape DEV→QAS→PRD, principios
  Clean Core, español técnico.

## Licencia

**GPL-3.0** (ver [`LICENSE`](LICENSE)). Es software libre **copyleft**: podés
usarlo, modificarlo y redistribuirlo, siempre que tus derivados **se mantengan
bajo GPL-3.0 y publiques su código fuente**. No se puede cerrar ni integrar en un
producto propietario.

Incluye componentes de terceros compatibles — atribuciones completas en
[`NOTICE`](NOTICE):

| Componente | Origen | Licencia |
| --- | --- | --- |
| 10 skills SAP de referencia | [`secondsky/sap-skills`](https://github.com/secondsky/sap-skills) | GPL-3.0 |
| `skill-creator` | Anthropic | Apache-2.0 |
| `sapui5-freestyle` | upstream | MIT |
| Todo lo demás (agentes, hooks, orquestador, comandos) | Insight Technologies | GPL-3.0 |

## Requisito: pnpm

Todo lo de Node usa **pnpm** (los MCP corren con `pnpm dlx`, los linters de hooks
también). Tenelo en el PATH:

```bash
corepack enable && corepack prepare pnpm@latest --activate   # o: brew install pnpm
```

## Instalación

```text
/plugin marketplace add DayronDLR/sap-enterprise-stack-plugin
/plugin install ses@sap-stack
/reload-plugins
```

Los comandos quedan namespaced bajo `ses:` — p.ej. `/ses:sap-abap`.

## Cómo actualizar

El plugin se actualiza como cualquier plugin de Claude Code:

```text
/plugin update
```

Cada release publica una versión nueva del marketplace automáticamente, así que
`/plugin update` te trae lo último — **sin re-clonar ni pasos manuales**. Después
de actualizar, corré `/reload-plugins` para recargar comandos y hooks.

> Detrás de escena: cada cambio en el stack reconstruye y republica este repo
> (que es plugin **y** marketplace a la vez) bumpeando la versión — por eso
> `/plugin update` detecta el cambio.

## Primeros pasos (2 minutos)

1. Instalá (los 3 comandos de arriba).
2. Escribí `/ses:` y el autocompletado te muestra los 11 agentes.
3. Probá uno:

   ```text
   /ses:sap-abap Necesito un report de aging AR con buckets
   0-30, 31-60, 61-90, +90 días usando BSID/BSAD
   ```

4. O describí la tarea en lenguaje natural y dejá que el orquestador enrute:

   ```text
   Tengo que diseñar un Calculation View de ventas con conversión de moneda para SAC
   ```

## Uso — los 11 agentes

| Comando | Dominio | Ejemplo |
| --- | --- | --- |
| `:sap-req` | Requirements, blueprints, FS, gap analysis | Blueprint del proceso Procure-to-Pay |
| `:sap-integration` | CPI, iFlows, OData, IDocs, APIs | iFlow asíncrono SAP→Salesforce con reintentos |
| `:sap-cap` | CAP Node.js/Java, BTP, MTA, XSUAA | App de aprobaciones de gastos con CAP + HANA Cloud |
| `:sap-fiori` | Fiori Elements, SAPUI5, RAP, BAS | List Report + Object Page de órdenes de compra |
| `:sap-hana` | Calculation Views, SQLScript, HDI | CalcView de ventas con conversión de moneda |
| `:sap-abap` | ABAP, CDS, RAP, BAdIs, EML, AMDP | Report de aging AR con buckets y manejo de errores |
| `:sap-basis` | Roles, autorizaciones, transportes, SoD | Diseño de rol con SoD para FI display |
| `:sap-migration` | Migración de datos, LTMC, Migration Cockpit | Mapeo de campos para carga de maestro de clientes |
| `:sap-qa` | Casos de prueba, UAT, NFR, go-live | Plan de pruebas + checklist NFR para el report de aging |
| `:sap-devops` | CI/CD, gCTS, ATC, pipelines | Pipeline de transporte con gate de ATC |
| `:sap-doc` | Documentación técnica, Word, full-stack | Documento técnico del proyecto con arquitectura |

> Todos prefijados con `/ses:`. Además: `:sap-techlead` (planifica tareas
> multi-agente) y los subagentes `reviewer` / `mentor` (vía `/agents` o por
> palabras clave como "review" / "explicame").

## Funcionalidad completa — qué queda activo al instalar

| Componente | Qué hace | Invocación |
| --- | --- | --- |
| 11 comandos de agente | Personas SAP auto-contenidas (persona + reglas + NFR + Clean Core inline) | `/ses:sap-abap …` |
| Orquestador (skill) | Enruta tu petición en lenguaje natural al agente correcto | automático |
| Subagentes | `reviewer` (code review), `mentor` (review educativo), Fiori (architect/implementer/debugger/tester) | `/agents` o keywords |
| Skills SAP de referencia | Material técnico (ABAP, CDS, CAP, SQLScript, BTP, Fiori Tools, UI5) que el agente consulta on-demand | automático |
| Hooks de Definition of Done | Gates de calidad en el evento `Stop` (quality-gate + code review), protección de archivos sensibles, auto-lint | tras `/reload-plugins` |
| 5 MCP servers | `sap-cap-capire`, `sap-ui5`, `sap-fiori-tools`, `github`, `sap-adt` | herramientas `mcp__…` |

## Qué podés hacer / Qué NO

**Podés:**

- Usar los 11 agentes en **cualquier proyecto SAP** sin clonar el repo.
- Dejar que el **orquestador** enrute por lenguaje natural (sin recordar comandos).
- Correr los **gates de Definition of Done** automáticamente al cerrar tareas.
- Consultar las **skills SAP de referencia** on-demand.
- Usar los **5 MCP servers** (4 sin credenciales; `sap-adt` con credenciales).
- **Actualizar** con `/plugin update` y modificar/forkear (bajo GPL-3.0).

**No podés (por diseño o límites de un plugin):**

- Invocar comandos **sin el prefijo `ses:`** — el namespacing de plugins es
  obligatorio en Claude Code (no hay `/sap-abap` pelado).
- **Desarrollar o regenerar el stack** en sí (el generador, tests y CI viven en el
  repo de desarrollo, no en el plugin).
- El **build branded de documentación** (`.docx`/`.pptx` con tema del cliente +
  diagramas con iconos SAP BTP) — no se distribuye (los iconos son assets
  propietarios de SAP). `sap-doc` sí genera el **contenido** de la doc.
- Que el plugin **setee env vars** por vos (un plugin no puede shippear `env`) —
  los ponés a mano (ver abajo).
- **Relicenciar** bajo una licencia no-GPL — es copyleft.

## Gates de calidad (Definition of Done) — importante

Este plugin es **opinionado**: instala hooks que aplican una *Definition of Done*.
Es intencional (nace de un flujo enterprise), pero conviene que lo sepas antes:

| Evento | Qué hace | ¿Puede bloquear? |
| --- | --- | --- |
| `Stop` (al cerrar una tarea) | Corre **quality-gate** (linters/smells) + **code review** sobre el diff | **Sí** — si hay hallazgos CRITICAL/HIGH, te pide seguir trabajando antes de cerrar |
| `PreToolUse` | **Protege archivos sensibles** (`.env`, `xs-security.json`, …) | Sí — impide editarlos |
| `PostToolUse` | Auto-lint de CDS/UI5/manifests al editar | No (informativo) |

**¿No los querés?** Poné esta variable en tu `settings.json` (opt-out solo para
el plugin):

```json
{ "env": { "SES_SKIP_DOD_GATES": "1" } }
```

Con eso los gates de `Stop` se **omiten** y podés cerrar sin review. Los agentes,
skills y MCP siguen funcionando igual. (La protección de archivos sensibles y el
auto-lint no dependen de esta variable.)

> Los hooks son scripts **bash** — en Windows necesitás Git Bash o WSL para que
> corran.

## Configuración que requiere acción del usuario

1. **MCP `sap-adt`** (lectura ABAP del sistema real) necesita credenciales:

   ```bash
   export SAP_ADT_URL="https://tu-sistema:44300"
   export SAP_ADT_USER="..." SAP_ADT_PASSWORD="..." SAP_ADT_CLIENT="100"
   ```

   Los otros 4 MCP (CAP, UI5, Fiori Tools, GitHub) arrancan sin secrets.

2. **Optimización de contexto (opcional)** — un plugin no puede shippear `env`;
   si la querés, agregá a TU `settings.json`:

   ```json
   { "env": { "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "60", "ENABLE_TOOL_SEARCH": "auto:5", "MAX_MCP_OUTPUT_TOKENS": "50000" } }
   ```

3. **Primer uso de cada MCP descarga su paquete** (`pnpm dlx`, requiere red).

## Skills SAP de referencia (incluidas)

Este plugin **incluye** las skills de referencia SAP (sintaxis ABAP, CDS, CAP,
SQLScript, BTP, Fiori Tools, UI5, …) — material que los agentes consultan
on-demand. Provienen del proyecto upstream
[`secondsky/sap-skills`](https://github.com/secondsky/sap-skills) bajo **GPL-3.0**;
por eso todo este plugin se distribuye bajo **GPL-3.0**. Ver `NOTICE` para las
atribuciones completas.

## Insumos y documentación (agente `sap-doc`)

`/ses:sap-doc` genera documentación técnica SAP. Como un plugin es de
**solo-lectura**, sus insumos van en **TU proyecto**, no en el plugin — el agente
los lee vía `${CLAUDE_PROJECT_DIR}`.

**Datos del cliente (los colocás vos, en tu proyecto):**

```text
tu-proyecto/
└── docs/architecture/
    ├── client-theme.yaml     # paleta, fuentes, logos del cliente
    ├── reference.docx        # plantilla Word para pandoc --reference-doc
    └── …                     # estructura/plantilla del cliente
```

> Nunca subas datos de cliente a un repo público. Van en el repo/carpeta de tu
> proyecto (privado).

**Build con identidad visual (branded `.docx`/`.pptx` + diagramas draw.io):**
el toolchain (generador draw.io, `build-doc.sh`, la librería de **iconos SAP BTP**
y los diagramas de ejemplo) **no** se distribuye con este plugin — los iconos son
assets de SAP con su propia licencia. `/ses:sap-doc` produce el **contenido** de
la documentación; para el build branded completo, usá el toolchain del repo de
desarrollo del stack.

## Soporte

Issues y mejoras: <https://github.com/DayronDLR/sap-enterprise-stack-plugin/issues>
