# Fuentes de verdad — Integration Suite / CPI

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `is.suite` | **SAP Integration Suite** | Capabilities, API Management, Event Mesh, Trading Partner Management | [help.sap.com/docs/integration-suite](https://help.sap.com/docs/integration-suite) |
| `is.cpi` | **Cloud Integration (CPI)** | Adapters, pasos del iFlow, scripting, Message Monitoring, reintentos | [help.sap.com/docs/cloud-integration](https://help.sap.com/docs/cloud-integration) |
| `sap.api-hub` | **SAP Business Accelerator Hub** (algunas APIs piden login) | Contrato real de APIs SAP, BAPIs, IDocs y eventos publicados | [api.sap.com](https://api.sap.com/) |
| `btp.connectivity` | **SAP BTP Connectivity** | Cloud Connector, destinations, principal propagation | [SAP BTP Connectivity](https://help.sap.com/docs/CP_CONNECTIVITY) |
| `odata.v4` | **OData v4 (OASIS)** | Semántica del protocolo cuando la doc SAP no alcanza | [OData v4.01](https://docs.oasis-open.org/odata/odata/v4.01/) |
| `sap.notes` | **SAP Notes / KBA** (requiere S-user) | Cambios de segmento IDoc, correcciones de adapter | [me.sap.com/notes](https://me.sap.com/notes) |
| — | Skills `sap-api-style`, `sap-btp-connectivity` (vendored) | Estilo de contrato y patrones de conectividad | material de trabajo — **no es norma** |

**El contrato de una interfaz sale del sistema, no del diseño.** La estructura de
un IDoc se lee en `WE60`/`WE30` del sistema del cliente y la de un servicio
OData en su `$metadata`; el Business Accelerator Hub describe la API estándar, que
puede estar extendida en el cliente.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| capire o la doc de CAP para un iFlow | Es otro runtime: ni los adapters ni el manejo de errores coinciden |
| Documentación de SAP PI/PO para CPI | Comparten conceptos, no configuración ni scripting |
| Un segmento IDoc "de memoria" | Cambia por release y por extensión Z del cliente |
| Credenciales, certificados o endpoints productivos | En un entregable se documenta el **tipo** de autenticación, nunca el valor |
| Blogs con snippets de Groovy | Pista, no fuente: el contrato está en la doc de Cloud Integration |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| Exports de iFlow (`.zip` / `.xml`) | Nombre, ID, descripción, adapters sender/receiver |
| Value Mapping artifacts | Mapeos de dominio entre sistemas |
| Security Materials / Credentials (nombres) | Tipos de autenticación — **no** los valores secretos |
| Integration Package metadata | Versión, descripción, objetos incluidos |
| `$metadata` del servicio OData consumido | Entity sets, tipos, navegación, acciones |
| Definición de destinations (BTP) | Host, proxy type, autenticación, propagación |
| `WE20` / `WE21` / `WE60` (SAP backend) | Partner profiles, puertos, documentación del IDoc |

**Transacciones / herramientas:** `WE20`, `WE21`, `WE30`, `WE60`, `SM59`, `SXMB_MONI`,
Message Monitoring de Cloud Integration.
