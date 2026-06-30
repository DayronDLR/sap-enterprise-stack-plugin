# SAP Enterprise Stack — Claude Code Plugin

11 agentes SAP especializados (ABAP, CAP/BTP, Fiori, HANA, Integration, Basis,
Migration, QA, DevOps, Requirements, Docs) como comandos auto-contenidos, un
orquestador SAP que enruta por lenguaje natural, subagentes (reviewer, mentor,
Fiori), hooks de **Definition of Done** y 5 **MCP servers SAP**.

> **Licencia:** MIT (ver `LICENSE`). Este plugin contiene solo contenido original.

## Requisito: pnpm

Todo lo de Node usa **pnpm** (los MCP corren con `pnpm dlx`, los linters de hooks
también). Tenelo en el PATH:

```bash
corepack enable && corepack prepare pnpm@latest --activate   # o: brew install pnpm
```

## Instalación

```text
/plugin marketplace add DayronDLR/sap-enterprise-stack-plugin
/plugin install sap-enterprise-stack@sap-stack
/reload-plugins
```

Los comandos quedan namespaced: `/sap-enterprise-stack:sap-abap …`.

## Primeros pasos (2 minutos)

1. Instalá (los 3 comandos de arriba).
2. Escribí `/sap-enterprise-stack:` y el autocompletado te muestra los 11 agentes.
3. Probá uno:

   ```text
   /sap-enterprise-stack:sap-abap Necesito un report de aging AR con buckets
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

> Todos prefijados con `/sap-enterprise-stack:`. Además: `:sap-techlead` (planifica
> tareas multi-agente) y los subagentes `reviewer` / `mentor` (vía `/agents` o por
> palabras clave como "review" / "explicame").

## Qué queda activo al instalar

| Componente | Invocación | Activación |
| --- | --- | --- |
| 11 comandos de agente | `/sap-enterprise-stack:sap-abap …` | automática |
| Orquestador (routing NL) | skill `sap-orchestrator` | automática |
| Subagentes (reviewer, mentor, Fiori) | `/agents` → `sap-enterprise-stack:reviewer` | automática |
| Hooks de Definition of Done | evento `Stop` (quality-gate + review) | tras `/reload-plugins` |
| MCP servers (5) | herramientas `mcp__…` | al iniciar sesión |

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

## Skills SAP de referencia (add-on opcional)

Este plugin **no incluye** las skills de referencia SAP (sintaxis ABAP, CAP,
SQLScript, etc.) porque provienen del proyecto upstream
[`secondsky/sap-skills`](https://github.com/secondsky/sap-skills) bajo licencia
GPL-3.0. Los agentes funcionan sin ellas (la persona es auto-contenida); las
skills solo agregan material de referencia. Para sumarlas, instalalas por
separado desde el upstream.

## Soporte

Issues y mejoras: <https://github.com/DayronDLR/sap-enterprise-stack-plugin/issues>
