# Fuentes de verdad — SAP HANA Cloud

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `hana.sqlscript` | **SQLScript Reference (HANA Cloud)** | Procedures, table functions, handlers, semántica de cada statement | [SQLScript Reference](https://help.sap.com/docs/hana-cloud-database/sqlscript-reference/sql-script) |
| `hana.database` | **SAP HANA Cloud, SAP HANA Database** | SQL, tipos de dato, particionado, vistas, privilegios | [help.sap.com/docs/hana-cloud-database](https://help.sap.com/docs/hana-cloud-database) |
| `hana.modeling` | **Modeling Guide for SAP HANA Cloud** | Calculation Views, nodos, analytic privileges, jerarquías | [Modeling Guide](https://help.sap.com/docs/hana-cloud-database/modeling-guide-for-sap-hana-cloud/modeling-guide) |
| `hana.platform` | **SAP HANA Cloud (plataforma)** | Instancias, sizing, HANA Cloud Central, backup, alertas | [help.sap.com/docs/hana-cloud](https://help.sap.com/docs/hana-cloud) |
| `cap.databases` | **capire → databases** | HDI containers y `cds deploy` **cuando el consumidor es CAP** | [capire → databases](https://cap.cloud.sap/docs/guides/databases/) |
| — | Skill `sap-sqlscript` (vendored) | Llegar rápido al patrón de un procedure o AMDP | material de trabajo — **no es norma** |

**El plan de ejecución no se cita: se mide.** Cualquier afirmación de
performance (índice usado, engine, pushdown) sale de `EXPLAIN PLAN` / PlanViz
sobre el volumen real, no de la documentación ni de la intuición.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| Documentación de HANA 2.0 on-premise | HANA Cloud difiere en features, límites y sintaxis soportada |
| SQL de otro motor (Oracle, SQL Server, PostgreSQL) | Las funciones escalares y el manejo de NULL no coinciden |
| capire para SQLScript | Define el modelo CDS, no la semántica del procedure |
| ABAP Keyword Documentation para AMDP | Documenta el envoltorio ABAP; el cuerpo es SQLScript |
| Un límite de tamaño o de partición "de memoria" | Cambia por release de HANA Cloud; se verifica en la doc |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| `db/src/**/*.hdbcalculationview` | Calculation Views, nodos, medidas, atributos |
| `db/src/**/*.hdbprocedure`, `*.hdbfunction` | Procedures y table functions desplegados |
| `db/src/**/*.hdbtable`, `*.hdbtabledata` | Tablas, particionado, datos de carga inicial |
| `db/src/**/*.hdbsynonym`, `*.hdbgrants` | Acceso cross-schema y permisos del container |
| `db/src/**/*.hdbanalyticprivilege` | Seguridad a nivel fila |
| `.hdiconfig` / `.hdinamespace` | Plugins activos y namespace del HDI container |
| `mta.yaml` → módulo `db-deployer` | Cómo y dónde se despliega el container |
| Clases AMDP en el sistema ABAP | Lógica SQLScript embebida que vive del lado ABAP |

**Transacciones / herramientas:** HANA Cloud Central, SAP HANA Database Explorer,
PlanViz, `ST05` (cuando el consumidor es ABAP).
