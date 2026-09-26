# Fuentes de verdad — ABAP / RAP / S/4HANA

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `abap.clean-abap` | **Clean ABAP** (SAP/styleguides) | Estilo, naming, OO, qué patrón está desaconsejado y por qué | [CleanABAP.md](https://github.com/SAP/styleguides/blob/main/clean-abap/CleanABAP.md) |
| `abap.keyword-doc` | **ABAP Keyword Documentation** | Sintaxis exacta, variantes por release, semántica de cada statement | [abapdocu (latest)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm) |
| `abap.rap` | **ABAP RESTful Application Programming Model** | Behavior definition, draft, EML, determinations/validations, service binding | [RAP Development Guide](https://help.sap.com/docs/abap-cloud/abap-rap/abap-restful-application-programming-model) |
| `abap.cloud` | **ABAP Cloud Development Guides** | Release contract C1, tiers de extensibilidad, qué está permitido en ABAP Cloud | [ABAP Cloud](https://help.sap.com/docs/abap-cloud/abap-cloud-development-guides/abap-cloud) |
| `abap.adt` | **ADT User Guide** | ATC, variantes de check, transporte, herramientas de Eclipse | [ADT User Guide](https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/abap-development-user-guide) |
| `sap.notes` | **SAP Notes / KBA** (requiere S-user) | Correcciones, restricciones por SP, comportamiento no documentado | [me.sap.com/notes](https://me.sap.com/notes) |
| `sap.roadmap` | **SAP Road Map Explorer** | Qué está anunciado y qué todavía no existe | [roadmaps.sap.com](https://roadmaps.sap.com/) |
| — | Skills `sap-abap`, `sap-abap-cds` (vendored) | Llegar rápido al patrón | material de trabajo — **no es norma** |

**Release-state de un objeto estándar:** no se deduce de la documentación. Se
comprueba en el sistema del cliente (ADT → *API State*, o el MCP de ADT en modo
lectura). Si no se pudo comprobar, el objeto se trata como **no released**.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| capire (`cap.cloud.sap`) | Es CAP: sus anotaciones y su CDS **no** son las de ABAP CDS |
| Fiori Design Guidelines | Definen UX, no el contrato del Business Object |
| Documentación de un release distinto al del cliente | Un statement válido en 2023 puede no existir en 1909 ni en ABAP Cloud |
| Un número de SAP Note de memoria | Un número inventado es peor que no citar: manda a leer otra cosa |
| Blogs de SAP Community | Pista, no fuente. Se cita el documento al que llevan |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| CDS Interface Views (`.ddls`) | Entidades, asociaciones, campos clave, anotaciones OData |
| Behavior Definition (`.bdef`) | Operaciones CRUD, actions, determinations, validations |
| Behavior Implementation (clase `BP_*`) | Lógica real de cada handler, side effects |
| Metadata Extensions (`.ddlx`) | Anotaciones `@UI` que consume Fiori Elements |
| Access Control (`.dcls`) | Autorizaciones a nivel fila (`pfcg_auth`) |
| Service Definition / Binding (`.srvd`, `.srvb`) | Qué se expone, con qué protocolo y versión |
| Enhancement Spots / BAdIs (`SE18`) | Puntos de extensión implementados |
| Package ABAP (`SE80`, ADT) | Objetos de desarrollo, package, transport requests |
| Tablas / tipos / clases principales | Dependencias de datos, contratos de interfaz |

**Transacciones relevantes:** `SE80`, `SE18`/`SE19`, `SE24`, `ATC`, `STMS`, `SLG1`.
