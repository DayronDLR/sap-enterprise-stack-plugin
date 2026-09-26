# Fuentes de verdad — Fiori / SAPUI5

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `fiori.design` | **SAP Fiori Design Guidelines** (rechaza clientes automáticos: se abre en el navegador) | UX: qué floorplan corresponde, comportamiento esperado de cada patrón | [experience.sap.com/fiori-design-web](https://experience.sap.com/fiori-design-web/) |
| `fiori.floorplans` | **Fiori Design Guidelines → Floorplans** | List Report vs Object Page vs ALP vs Worklist | [Floorplans](https://experience.sap.com/fiori-design-web/floorplans/) |
| `ui5.sdk` | **SAPUI5 SDK / Demo Kit** | API Reference, samples y **qué versión LTS existe** (Version Overview) | [ui5.sap.com](https://ui5.sap.com/) |
| `ui5.docs` | **SAPUI5 Documentation** | Guía de desarrollo, Fiori Elements, anotaciones, routing | [help.sap.com/docs/SAPUI5](https://help.sap.com/docs/SAPUI5) |
| `fiori.tools` | **SAP Fiori tools** | Generadores, Page Editor, Service Modeler, deployment | [help.sap.com/docs/SAP_FIORI_tools](https://help.sap.com/docs/SAP_FIORI_tools) |
| — | MCP `sap-ui5` (`get_api_reference`, `get_guidelines`, `get_version_info`) | Confirmar que un control y una API existen **en la versión del proyecto** | herramienta, antes de citar |
| — | MCP `sap-fiori-tools` (`search_docs`) | Anotaciones de Fiori Elements y configuración de app | herramienta |

**Una API no se cita sin versión.** El contrato es la API Reference de la
`minUI5Version` del proyecto (`webapp/manifest.json`), no la del SDK actual: un
control agregado después no existe para esa app.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| `sapui5.hana.ondemand.com` | Host heredado del SDK; el vigente es `ui5.sap.com` |
| Ejemplos con `sap.ui.getCore()` u otras APIs deprecadas | El linter los rechaza y el upgrade los rompe |
| La documentación de OpenUI5 para features SAPUI5 | OpenUI5 no trae los Smart Controls ni Fiori Elements |
| Capturas o "cómo se ve" sin haberlo ejecutado | Una captura inventada es un defecto de entrega |
| Blogs con snippets de manifest | El contrato del `manifest.json` está en la doc de SAPUI5 |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| `webapp/manifest.json` → `sap.app.crossNavigation.inbounds` | Semantic Object, action, intent, icon |
| `webapp/manifest.json` → `sap.ui5.dependencies.minUI5Version` | Versión UI5 (y qué API Reference aplica) |
| `webapp/manifest.json` → `sap.cloud.service` | Nombre del repo HTML5 en BTP |
| `webapp/manifest.json` → `sap.app.dataSources` | URI y nombre del servicio OData |
| `webapp/i18n/i18n_*.properties` | Títulos de tabs, labels, textos visibles |
| Vistas XML / fragments → `SmartTable entitySet=` | Entity sets por vista / tab |
| `webapp/localService/*/metadata.xml` → `EntitySet` | Entity sets OData (config, value help, analíticos) |
| `ui5.yaml` | Versión del framework, proxies, tareas de build |
| `mta.yaml` → `resources` | Servicios BTP declarados |
| `package.json` → `scripts` | Comandos de build y deploy |
