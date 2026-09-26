# Fuentes de verdad — CAP / BTP

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `cap.capire` | **capire** | Todo CAP: servicios, handlers, providing/consuming, deployment | [cap.cloud.sap/docs](https://cap.cloud.sap/docs/) |
| `cap.cds` | **capire → CDS** | Sintaxis CDL/CQL/CSN, anotaciones, aspectos, `cds.requires` | [cap.cloud.sap/docs/cds](https://cap.cloud.sap/docs/cds/) |
| `cap.java` | **capire → Java** | Runtime Java: event handlers, `CqnService`, Spring Boot | [cap.cloud.sap/docs/java](https://cap.cloud.sap/docs/java/) |
| `cap.releases` | **capire → Releases** | Qué cambió y en qué versión de `@sap/cds`; breaking changes | [cap.cloud.sap/docs/releases](https://cap.cloud.sap/docs/releases/) |
| `btp.developer-guide` | **SAP BTP Developer Guide** | Arquitectura de extensión, CF vs Kyma, observability, CI/CD | [BTP Developer Guide](https://help.sap.com/docs/btp/btp-developers-guide/btp-developers-guide) |
| `btp.platform` | **SAP BTP (documentación de plataforma)** | Subaccounts, entitlements, service plans, regiones | [help.sap.com/docs/btp](https://help.sap.com/docs/btp) |
| `btp.xsuaa` | **Authorization and Trust Management (XSUAA)** | Scopes, role templates, role collections, `xs-security.json` | [XSUAA](https://help.sap.com/docs/btp/sap-business-technology-platform/authorization-and-trust-management-in-cloud-foundry-environment) |
| `sap.api-hub` | **SAP Business Accelerator Hub** (algunas APIs piden login) | Contrato de las APIs S/4HANA que el servicio consume | [api.sap.com](https://api.sap.com/) |
| — | MCP `sap-cap-capire` (`search_docs`, `search_model`) | Buscar en la doc de la versión instalada y en el modelo compilado | herramienta, **antes** de citar de memoria |

**La versión de CAP la manda el proyecto, no la documentación.** `@sap/cds` sale
de `package.json`; recién después se lee capire para *esa* línea de versión.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| ABAP Keyword Documentation / ABAP CDS | Son otro CDS: las anotaciones no se comparten |
| Documentación de XS Advanced / HANA XS clásico | Otro runtime, otro modelo de seguridad |
| Un ejemplo de capire con su versión implícita | capire documenta la línea actual; el proyecto puede estar atrás |
| El `mta.yaml` de otro proyecto como plantilla | Los `resources` son del landscape del cliente |
| Blogs sobre "cómo desplegar en CF" | Pista, no fuente: el contrato está en la doc de BTP |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| `package.json` → `name`, `version`, `cds.requires` | ID de la app, versión, servicios externos |
| `srv/*.cds` → `@path`, `@requires`, nombre del `service` | Nombre y path del servicio, roles requeridos |
| `db/*.cds` → entities, enums, associations | Entidades del dominio, campos clave, relaciones |
| `mta.yaml` → `modules`, `resources` | Módulos desplegados, servicios BTP (HANA, XSUAA, Destination) |
| `xs-security.json` → `scopes`, `role-templates` | Modelo de autorización XSUAA |
| `package.json` → `scripts` | Comandos de build, deploy y test |
| `.cdsrc.json` / `cds` en `package.json` | Perfiles, features, configuración de base de datos |

> `.env`, `default-env.json` y `xs-security.json` con valores reales **no se
> transcriben** a un entregable: se documenta la estructura, nunca el secreto.
