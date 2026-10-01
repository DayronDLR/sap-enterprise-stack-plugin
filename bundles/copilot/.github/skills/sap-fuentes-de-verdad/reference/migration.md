# Fuentes de verdad — Data Migration (S/4HANA 2023)

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `s4.data-migration-2023` | **Data Migration — SAP S/4HANA 2023** (landing del Migration Cockpit) | Enfoques disponibles (staging tables, direct transfer), Note Analyzer, licenciamiento | [Data Migration](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/a4d4119a2cc9448a98e5d17e6dd0eac4.html?version=2023.latest) |
| `s4.migrate-your-data` | **Migrate Your Data – Migration Cockpit (2023)** | La app Fiori: proyectos, objetos, simulación, migración, mensajes | [Migrate Your Data](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/2f0dbe4111214bcf9b2d57eca26f0525.html?version=2023.latest) |
| `s4.migration-staging` | **Migrate Data Using Staging Tables (2023)** | Carga por staging tables: generación, llenado, transferencia | [Staging Tables](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/87ffdbfebd504116b497c02d51ce5b58.html?version=2023.latest) |
| `s4.migration-direct-transfer` | **Migrate Data Directly from SAP System (2023)** | Direct transfer desde un sistema SAP origen: selección y transferencia | [Direct Transfer](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/7a62b59726ce42e7a10770b06940f934.html?version=2023.latest) |
| `s4.migration-objects` | **Available Migration Objects (2023)** | Qué objeto de migración existe en 2023, su alcance y su documentación | [Available Migration Objects](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/d3a3eb7caa1842858bf0372e17ad3909/8dd142b479f9481891fa8b3f86648df3.html?version=2023.latest) |
| `s4.ltmom` | **SAP S/4HANA Migration Object Modeler (LTMOM)** | Ajustar objetos estándar y crear objetos propios | [LTMOM](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/3732aa6c1acf4184812f0db7beb8e037.html?version=2023.latest) |
| `s4.ltmc-deprecated` | **Migration Cockpit (Transaction LTMC) – Deprecated** | LTMC ya no migra datos en 2023: sólo permite ver proyectos viejos | [LTMC – Deprecated](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/29193bf0ebdd4583930b2176cb993268/8f97f0b407024465a283809f0bbe000c.html?version=2023.latest) |
| `s4.simplification-list-2023` | **Simplification List for SAP S/4HANA 2023** (PDF) | Cambios de modelo de datos que condicionan el mapeo (Business Partner, Material Ledger…) | [SIMPL_OP2023.pdf](https://help.sap.com/doc/c34b5ef72430484cb4d8895d5edd12af/2023/en-US/SIMPL_OP2023.pdf) |
| `sap.readiness-check` | **SAP Readiness Check** | Volumen y calidad del sistema origen en una conversión | [SAP Readiness Check](https://help.sap.com/docs/SAP_READINESS_CHECK) |
| `sap.notes` | **SAP Notes / KBA** (requiere S-user) | Correcciones del Migration Cockpit y del add-on DMIS | [me.sap.com/notes](https://me.sap.com/notes) |
| — | MCP `sap-adt` (`ReadTable`, `ReadStructure`, `ReadDataElement`, `ReadDomain`) | Campos, claves y longitudes reales de la tabla destino | herramienta, sólo lectura |

**Correcciones del cockpit:** la landing de 2023 pide correr el Note Analyzer
(`CNV_NA_MC`) y remite a la SAP Note `3016862` — se cita
`[fuente:sap.notes 3016862]`. Ninguna otra nota se cita sin haberla abierto.

**La estructura de un objeto sale del proyecto, no de la doc.** Los campos
obligatorios y la plantilla de un objeto se leen del proyecto de migración del
cliente (o de LTMOM): cambian por release, por FPS y por ajustes propios.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| Doc de LTMC o del enfoque "file" de releases 1709–2020 | LTMC está deprecada: en 2023 no migra datos |
| Doc del Migration Cockpit de S/4HANA Cloud Public Edition | Objetos, plantillas y extensibilidad difieren del on-premise |
| LSMW como método para S/4HANA | El stack lo reserva para ECC; en 2023 se usa el Migration Cockpit |
| Una plantilla o lista de campos de otro proyecto o release | Se regenera desde el proyecto del cliente |
| Un número de SAP Note "de memoria" | Un número inventado manda a leer otra cosa |
| Blogs con plantillas o mapeos | Pista, no fuente |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| Proyecto de migración en *Migrate Your Data* | Objetos seleccionados, estado, mensajes de simulación y migración |
| Staging tables generadas por el proyecto | Estructura real que hay que llenar |
| Value mappings del proyecto | Conversión de valores legacy → SAP |
| Objetos ajustados o propios en LTMOM | Reglas de campo, estructuras adicionales |
| Definición DDIC de la tabla destino (`SE11` / ADT) | Campos, claves, longitudes, valores fijos |
| Especificación de mapeo y transformación firmada | Reglas acordadas con negocio |
| Conteos de reconciliación origen vs destino | Evidencia de completitud por objeto |

**Transacciones / apps:** *Migrate Your Data – Migration Cockpit*, `LTMOM`,
`CNV_NA_MC`, `LTMC` (deprecada: sólo consulta de proyectos viejos), `SE11`, `SE16N`, `SLG1`.
