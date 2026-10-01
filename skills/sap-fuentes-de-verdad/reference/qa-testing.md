# Fuentes de verdad — QA & Testing

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `abap.unit` | **ABAP Unit — ABAP Platform 2023** | Clases de test, fixtures, risk level, duración, ejecución | [ABAP Unit](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/491cfd8926bc14cde10000000a42189b.html?version=2023.latest) |
| `abap.atc` | **ABAP Test Cockpit (ATC) — ABAP Platform 2023** | Check variants, corridas, exenciones, ATC central | [ATC](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/62c41ad841554516bb06fb3620540e47.html?version=2023.latest) |
| `abap.cds-test-double` | **ABAP CDS Test Double Framework — ABAP Platform 2023** | Tests unitarios de vistas CDS aislando sus dependencias | [CDS Test Double Framework](https://help.sap.com/docs/ABAP_PLATFORM_NEW/c238d694b825421f940829321ffa326a/cbedc08ff4de48ffa8d04d3067ef08e7.html?version=2023.latest) |
| `abap.keyword-doc` | **ABAP Keyword Documentation** | Sintaxis de `FOR TESTING`, `RISK LEVEL`, `DURATION`, test seams | [abapdocu (latest)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm) |
| `ui5.testing` | **SAPUI5 SDK → Testing** | Estrategia de tests de una app UI5: qué va en QUnit y qué en OPA5 | [Testing](https://ui5.sap.com/#/topic/7cdee404cac441888539ed7bfe076e57) |
| `ui5.qunit` | **SAPUI5 SDK → Unit Testing with QUnit** | Tests unitarios de formatters, modelos y controles | [QUnit](https://ui5.sap.com/#/topic/09d145cd86ee4f8e9d08715f1b364c51) |
| `ui5.opa5` | **SAPUI5 SDK → Integration Testing with OPA5** | Journeys, pages, matchers, mock server | [OPA5](https://ui5.sap.com/#/topic/2696ab50faad458f9b4027ec2f9b884d) |
| `ui5.sdk` | **SAPUI5 SDK / Demo Kit** | API de `sap.ui.test.*` en la versión del proyecto | [ui5.sap.com](https://ui5.sap.com/) |
| `sap.cloud-alm` | **SAP Cloud ALM** | Gestión del proyecto: tests, defectos, quality gates | [help.sap.com/docs/cloud-alm](https://help.sap.com/docs/cloud-alm) |
| `calm.test-preparation` | **SAP Cloud ALM → Test Preparation** | Test cases manuales y automatizados | [Test Preparation](https://help.sap.com/docs/cloud-alm/applicationhelp/test-preparation) |
| `calm.test-execution` | **SAP Cloud ALM → Test Execution** | Ejecución, resultados y defectos desde una corrida | [Test Execution](https://help.sap.com/docs/cloud-alm/applicationhelp/test-execution) |
| `solman.test-suite` | **SAP Solution Manager 7.2 SPS 21 — Test Suite** (PDF; sólo si el cliente opera SolMan) | Test plans, test packages y TBOM en landscapes con SolMan | [Test Suite (PDF)](https://help.sap.com/doc/a5c655979d254d2bb15407f6993ab048/7.2.21/en-US/loio76ecd5174c954e8bba780b10c5ea37ae.pdf) |
| — | wdi5 (comunidad UI5; el SDK lo nombra en «Test Automation») | E2E de apps UI5 con WebdriverIO | [wdi5](https://ui5-community.github.io/wdi5/) — herramienta, **no es norma** |
| — | MCP `sap-adt` (`ReadClass`, `GetInactiveObjects`) | Fuente de las clases de test y objetos inactivos. Ejecutar ABAP Unit es en ADT o en el pipeline: el MCP es de solo lectura | herramienta, sólo lectura |
| — | MCP `sap-ui5` (`run_ui5_linter`, `run_manifest_validation`) | Evidencia sobre `webapp/` | herramienta |

**Un test se cita contra la versión del proyecto.** Para UI5, la API de
`sap.ui.test` es la de la `minUI5Version` del `manifest.json`; para ABAP, la de
ABAP Platform 2023 (`version=2023.latest`), no la de ABAP Cloud.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| Doc de ATC / ABAP Unit del entorno ABAP de BTP para on-premise | Check variants y reglas de release contract difieren |
| SolMan Test Suite cuando el cliente usa Cloud ALM (o al revés) | Cada herramienta tiene su modelo de test plan y defecto |
| Ejemplos QUnit/OPA5 de otra versión de UI5 | APIs y test starter cambian entre versiones |
| wdi5, Tricentis o Selenium como norma | Son herramientas: el contrato está en la doc SAP y en el plan de pruebas |
| Un umbral de cobertura o de performance "de memoria" | Lo fija el proyecto y el baseline (`sap-nfr`) |
| Blogs con suites de test | Pista, no fuente |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| Clases de test ABAP (`FOR TESTING`, includes de test locales) | Casos cubiertos, fixtures, dobles |
| Variante ATC del proyecto (`ATC`, `SCI`) | Qué checks bloquean y con qué prioridad |
| `webapp/test/` (`unit/`, `integration/`, `testsuite.qunit.*`) | Suites QUnit y OPA5 de la app |
| `ui5.yaml`, `karma.conf.js`, `wdio.conf.*` | Cómo corren los tests y en qué navegador |
| Plan de pruebas y test cases (Cloud ALM, SolMan o planilla firmada) | Alcance de UAT y SIT |
| Registro de defectos (Cloud ALM, Jira) | Severidad, estado, re-test |
| `agents/09-qa-testing/nfr-checklist.md` + baseline de performance | Evidencia NFR del Gate 3 |

**Transacciones relevantes:** `ATC`, `SCI`, `SE80` (ABAP Unit), `SECATT`, `ST05`,
`SAT`, `STAD`.
