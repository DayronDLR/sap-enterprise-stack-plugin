# Fuentes de verdad — SAP DevOps (CI/CD, transportes, BTP)

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `cicd.piper` | **Project "Piper"** (SAP, open source) | Steps, stages y parámetros de `.pipeline/config.yml` | [project-piper.io](https://www.project-piper.io/) |
| `btp.cicd` | **SAP Continuous Integration and Delivery** | Servicio de CI/CD gestionado en BTP: jobs, credenciales, webhooks | [help.sap.com/docs/continuous-integration-and-delivery](https://help.sap.com/docs/continuous-integration-and-delivery) |
| `abap.gcts` | **gCTS — ABAP Platform 2023** | Repositorios Git en el sistema ABAP, push/pull, configuración y prerequisitos | [gCTS](https://help.sap.com/docs/ABAP_PLATFORM_NEW/4a368c163b08418890a406d413933ba7/f319b168e87e42149e25e13c08d002b9.html?version=2023.latest) |
| `abap.abapgit` | **abapGit Docs** (open source) | Serialización de objetos, `.abapgit.xml`, online/offline repos | [docs.abapgit.org](https://docs.abapgit.org/) |
| `abap.cts` | **Change and Transport System (CTS) — ABAP Platform 2023** | Órdenes, capas y rutas de transporte | [Change and Transport System](https://help.sap.com/docs/ABAP_PLATFORM_NEW/4a368c163b08418890a406d413933ba7/48c4300fca5d581ce10000000a42189c.html?version=2023.latest) |
| `abap.tms` | **Transport Management System (TMS) — ABAP Platform 2023** | Colas de import, rutas, `STMS` | [Transport Management System](https://help.sap.com/docs/ABAP_PLATFORM_NEW/4a368c163b08418890a406d413933ba7/0988f339db9911d2b41a00609419f767.html?version=2023.latest) |
| `abap.atc` | **ABAP Test Cockpit (ATC) — ABAP Platform 2023** | Gate de calidad ABAP en el pipeline | [ATC](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/62c41ad841554516bb06fb3620540e47.html?version=2023.latest) |
| `abap.unit` | **ABAP Unit — ABAP Platform 2023** | Ejecución de tests ABAP como gate | [ABAP Unit](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/491cfd8926bc14cde10000000a42189b.html?version=2023.latest) |
| `btp.ctms` | **SAP Cloud Transport Management** | Nodos, rutas y transporte de MTAs entre subaccounts | [help.sap.com/docs/cloud-transport-management](https://help.sap.com/docs/cloud-transport-management) |
| `sap.cloud-alm` | **SAP Cloud ALM** | Features, despliegues y monitoreo de operaciones | [help.sap.com/docs/cloud-alm](https://help.sap.com/docs/cloud-alm) |
| `calm.transports` | **SAP Cloud ALM → Working with Transports** | Transportes asociados a features y su despliegue | [Working with Transports](https://help.sap.com/docs/cloud-alm/applicationhelp/working-with-transports) |
| `btp.mta` | **Multitarget Applications in the Cloud Foundry Environment** | `mta.yaml`, extensiones `.mtaext`, deploy con el plugin MultiApps | [MTA en Cloud Foundry](https://help.sap.com/docs/btp/sap-business-technology-platform/multitarget-applications-in-cloud-foundry-environment) |
| `btp.mbt` | **Cloud MTA Build Tool (`mbt`)** | Build de `.mtar`: comandos, flags, Makefile generado | [sap.github.io/cloud-mta-build-tool](https://sap.github.io/cloud-mta-build-tool/) |
| `cf.cli` | **Cloud Foundry CLI** | Comandos `cf` (push, services, logs) | [docs.cloudfoundry.org/cf-cli](https://docs.cloudfoundry.org/cf-cli/) |
| `btp.developer-guide` | **SAP BTP Developer Guide** | Arquitectura de extensión, CF vs Kyma, observability, CI/CD | [BTP Developer Guide](https://help.sap.com/docs/btp/btp-developers-guide/btp-developers-guide) |
| — | Skill `sap-btp-developer-guide` (vendored) | Llegar rápido al patrón de pipeline BTP | material de trabajo — **no es norma** |
| — | MCP `sap-adt` (`ListTransports`, `GetTransport`, `GetInactiveObjects`) | Estado real de órdenes y objetos antes de liberar | herramienta, sólo lectura |

**La versión de cada herramienta la manda el proyecto.** La de `mbt`, `cf` y la
imagen de Piper sale del pipeline del repo; gCTS y CTS se citan fijados a
ABAP Platform 2023 (`version=2023.latest`), no a la última release.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| Doc de gCTS o CTS de otra release | help.sap.com abre la última release por defecto, no la del cliente |
| abapGit como transporte productivo | El camino del landscape es CTS/gCTS; abapGit versiona y comparte código |
| Doc del entorno Neo (MTA en Neo, CTS+ para Neo) | Entorno en retiro; el destino es Cloud Foundry |
| Parámetros de un step de Piper sacados de un blog | La referencia de cada step está en project-piper.io |
| Doc genérica de Cloud Foundry para servicios SAP (XSUAA, HDI) | Esos servicios se documentan en BTP |
| Credenciales, service keys o tokens en un entregable | Se documenta el **tipo** de credencial, nunca el valor |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| `.pipeline/config.yml` | Stages y parámetros de Piper |
| `Jenkinsfile` / `.github/workflows/` | Orquestación real del pipeline |
| `mta.yaml` y `*.mtaext` | Módulos, recursos y parámetros por entorno |
| `package.json` (`scripts`, `devDependencies`) | Build, lint y test que corre el pipeline |
| `.abapgit.xml` | Starting folder y mapeo de paquetes |
| Repositorio gCTS en el sistema (vSID, branch) | Qué paquete sincroniza con qué rama |
| Rutas `STMS` y nodos de Cloud Transport Management | Orden de promoción DEV → QAS → PRD |

**Transacciones relevantes:** `STMS`, `SE09`/`SE10`, `SE01`, `ATC`, `SCI`.
