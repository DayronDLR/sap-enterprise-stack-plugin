# Fuentes de verdad — Requirements / Fit-to-Standard (S/4HANA 2023)

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `sap.process-navigator` | **SAP Signavio Process Navigator** (requiere S-user; reemplaza a SAP Best Practices Explorer y al Roadmap Viewer) | Roadmaps SAP Activate, scope items de SAP Best Practices, process flows para los workshops de fit-to-standard | [me.sap.com/processnavigator](https://me.sap.com/processnavigator) |
| `s4.best-practices-2023` | **SAP Best Practices for SAP S/4HANA 2023** (solution scope SolS-055 en Process Navigator) | Scope items de la release 2023 on-premise, su test script y su configuración | [SolS-055 / 2023](https://me.sap.com/processnavigator/SolS/SolS-055/2023?region=US) |
| `s4.product-2023` | **SAP S/4HANA 2023 — Product Assistance** | Funcionalidad estándar por área, apps y transacciones de la release 2023 | [SAP S/4HANA 2023](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE?version=2023) |
| `s4.fsd-2023` | **Feature Scope Description — SAP S/4HANA 2023** (PDF) | Qué entra en el alcance de la release: base para clasificar un requerimiento como fit o gap | [FSD_OP2023_latest.pdf](https://help.sap.com/doc/e2048712f0ab45e791e6d15ba5e20c68/2023/en-US/FSD_OP2023_latest.pdf) |
| `s4.simplification-list-2023` | **Simplification List for SAP S/4HANA 2023** (PDF) | Funcionalidad ECC eliminada, cambiada o no estratégica; impacto de una conversión | [SIMPL_OP2023.pdf](https://help.sap.com/doc/c34b5ef72430484cb4d8895d5edd12af/2023/en-US/SIMPL_OP2023.pdf) |
| `fiori.apps-library` | **SAP Fiori Apps Reference Library** | Qué app estándar cubre un proceso, en qué release existe y qué rol de negocio la trae | [Fiori Apps Library](https://fioriappslibrary.hana.ondemand.com/sap/fix/externalViewer/) |
| `sap.roadmap` | **SAP Road Map Explorer** | Qué está anunciado y qué todavía no existe | [roadmaps.sap.com](https://roadmaps.sap.com/) |
| `sap.readiness-check` | **SAP Readiness Check** | Análisis del sistema origen: simplification items, add-ons, custom code, volumen | [SAP Readiness Check](https://help.sap.com/docs/SAP_READINESS_CHECK) |
| `sap.cloud-alm` | **SAP Cloud ALM** | Gestión del proyecto de implementación: alcance, requerimientos, tests, transportes | [help.sap.com/docs/cloud-alm](https://help.sap.com/docs/cloud-alm) |
| `calm.requirements` | **SAP Cloud ALM → Requirements** | Ciclo de vida del requerimiento y su trazabilidad a procesos, cuando el proyecto usa Cloud ALM | [Requirements](https://help.sap.com/docs/cloud-alm/applicationhelp/requirements) |
| `sap.leanix` | **SAP LeanIX** (sólo si el cliente lo licencia) | Inventario AS-IS de aplicaciones, interfaces y capacidades de negocio | [help.sap.com/docs/leanix](https://help.sap.com/docs/leanix) |
| `sap.notes` | **SAP Notes / KBA** (requiere S-user) | Notas de release, restricciones y matriz de compatibilidad | [me.sap.com/notes](https://me.sap.com/notes) |

**Notas de la release 2023** que enlaza la página oficial del producto: Release
Information Note `3307222`, Release Restriction Note `3348949` y Compatibility
Scope Matrix `2269324`. Se citan `[fuente:sap.notes 3307222]`. Antes de declarar
un fit, la Release Restriction Note dice si la función tiene restricciones en 2023.

**Fit o gap se decide contra la release del cliente.** El FSD, la Simplification
List y los scope items son **por release**: los de 2025 no prueban nada en 2023.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| SAP Best Practices Explorer (`rapid.sap.com/bp`) | Retirado: el host rechaza la conexión. Los scope items viven en Process Navigator |
| SAP Roadmap Viewer (`go.support.sap.com/roadmapviewer`) | Devuelve 404. Los roadmaps de SAP Activate están en Process Navigator |
| Documentación o scope items de S/4HANA Cloud Public Edition | Otro producto: alcance, extensibilidad y scope items difieren del on-premise |
| FSD o Simplification List de otra release | El alcance cambia por release y por FPS |
| Road Map Explorer como prueba de que algo existe | Es un plan, no producto entregado |
| Una app de la Fiori Apps Library sin filtrar por release | Puede no existir en 2023 o requerir otro backend |
| Presentaciones comerciales o blogs de partners | Pista, no fuente. Se cita el documento oficial al que llevan |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| Blueprint / Business Process Design firmado | Alcance acordado, procesos in-scope y out-of-scope |
| Scope items seleccionados (Process Navigator / Cloud ALM) | Qué proceso estándar se toma como base |
| Matriz fit-gap / backlog de requerimientos (Cloud ALM, Jira) | Clasificación de cada requerimiento y su decisión |
| Actas de los workshops de fit-to-standard | Decisiones, responsables, pendientes |
| Estructura organizativa (`SPRO` → Enterprise Structure) | Sociedades, centros, organizaciones de ventas y compras — **nunca asumida** |
| Resultado de SAP Readiness Check del sistema origen | Simplification items y add-ons relevantes |
| Inventario SAP LeanIX (si existe) | Aplicaciones e interfaces del AS-IS |

**Transacciones relevantes:** `SPRO`, `SFW5`, `SE16N`, `/UI2/FLP`.
