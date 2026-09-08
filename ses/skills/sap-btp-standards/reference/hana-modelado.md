# HANA Cloud: expertise técnico y catálogo de objetos

> Referencia del agente HANA Cloud. Se lee bajo demanda.

## EXPERTISE TÉCNICO

### SAP HANA Cloud (HaaS)

- SAP HANA Cloud provisioning y configuración en BTP
- HANA Cloud Connections: on-premise HANA, Data Lake, remote sources
- SAP HANA Data Lake (INA/Files): casos de uso, particionamiento
- HDI (HANA Deployment Infrastructure): contenedores, roles, grants
- Réplica de datos: SDA (Smart Data Access), SDI (Smart Data Integration)
- HANA Cloud vs HANA on-premise: diferencias críticas de features
- SAP HANA Cloud Central: monitoreo, alertas, backups, sizing

### Modelado HANA

- Calculation Views: Graphical y SQL-based
  - Tipos: Dimension, Cube (sin star join), Cube con star join
  - Nodos: Projection, Aggregation, Join, Union, Rank, Non-Equi Join
  - Input Parameters y Variables
  - Currency conversion y Unit conversion
  - Jerarquías: Level-based y Parent-Child
- CDS Views HANA-specific (@Analytics annotations)
- Analytical Privileges (row-level security)

> **Legacy (no usar en proyectos nuevos):** Information Composer → reemplazar por SAP Analytics Cloud Stories. Modelado HANA "live" / XS Classic → migrar a HDI + CAP.

### SQL y SQLScript

- SQL HANA extensions: WINDOW functions, SERIES, SPATIAL, GRAPH
- SQLScript: procedimientos, funciones de tabla, scalar functions
- APPLY_FILTER, CE_COLUMN_TABLE, CE_PROJECTION
- Manejo de errores: SIGNAL, RESIGNAL, DECLARE CONDITION
- Cursores, bucles, condicionales en SQLScript
- CALL con parámetros IN/OUT/INOUT
- Dynamic SQL en HANA (EXEC, EXECUTE IMMEDIATE)
- Operadores UNNEST, LATERAL, WITH (CTE)

### Performance y Optimización

- EXPLAIN PLAN: lectura e interpretación
- M_SQL_PLAN_CACHE: identificar queries pesados
- HANA Studio / SAP HANA Cockpit: Performance Analysis
- Column Store vs Row Store: cuándo usar cada uno
- Data aging y particionamiento de tablas
- índices: inverted individual, composite, full-text
- Buffer Cache, Column Store Cache
- Parallel execution en Calculation Views
- HANA Statistics Server, HANA Embedded Statistics

### Administración HANA Cloud

- Backup & Recovery: HANA Cloud backups automáticos, point-in-time recovery
- Tenant databases y multitenant architecture
- User management: users, roles, privileges en HANA Cloud
- Row-Level Security: analytic privileges, structured privileges
- Auditing: audit policies, SAP HANA Audit Log
- Monitoring: M_* system views, SAP HANA Cockpit, Cloud ALM
- Sizing: memory, storage, compute recommendations
- Instance updates y patch management en HANA Cloud
- **Release cycle (QRC)**: HANA Cloud entrega Quarterly Release Cycles — revisar What's New y deprecation timeline por QRC antes de adoptar features; validar compatibilidad pre-upgrade

### BW/4HANA y SAP Analytics

- BW/4HANA: DataStore Objects (DSO), CompositeProviders, OpenHub
- BW Transformations, DTPs, Process Chains
- Mixed scenarios: BW on HANA → BW/4HANA migration
- SAP Analytics Cloud (SAC): Live Connection vs Import
- Embedded Analytics in S/4HANA via CDS + KPI tiles
- SAP Datasphere (ex Data Warehouse Cloud): Spaces, Views (graphical/SQL), Data Flows / Replication Flows, Analytic/Fact Models, capa semántica de negocio, federación con HANA Cloud (sin replicar) y Database Access; integración con SAC y con HANA Cloud native SQL

### HDI (HANA Deployment Infrastructure)

- Artefactos HDI: .hdbview, .hdbtable, .hdbprocedure, .hdbcalculationview
- .hdbgrants: permisos entre contenedores
- .hdbsynonym: objetos remotos y cross-schema
- Deploy con @sap/hdi-deploy y MTA
- Roles de acceso: #DI_USER, #RT_USER
- Cross-container access patterns

### Integración y Conectividad

- Smart Data Access (SDA): virtual tables hacia fuentes externas
- Smart Data Integration (SDI): replicación en tiempo real
- HANA Cloud Connections: conectar HANA Cloud con HANA on-premise
- Data Provisioning Agent: configuración y uso
- Remote Table Replication: snapshot vs real-time
- OData exposure: vía CAP / HDI en proyectos nuevos. *HANA XS Advanced (XSA) y XS Classic son legacy en sunset — no diseñar nuevo sobre XSA; migrar a CAP + Cloud Foundry/Kyma.*

## OBJETOS HANA QUE PRODUCES

### 1. Calculation View (Cube con Star Join)

```sql
-- Representación textual de un Calculation View
-- CV_VENTAS_ANALISIS (Cube, Star Join)
-- Fact: VBAP (posiciones pedido)
-- Dim1: CV_DIM_MATERIAL → DD_MARA
-- Dim2: CV_DIM_CLIENTE  → DD_KNA1
-- Dim3: CV_DIM_TIEMPO   → DD_CALDAY
-- Medidas: NETWR (suma), KWMENG (suma)
-- Input Parameter: IP_BUKRS (Sociedad)
```

### 2. Procedimiento SQLScript

```sql
CREATE OR REPLACE PROCEDURE "MY_SCHEMA"."PROC_CALCULA_SALDO"(
  IN  IV_BUKRS    NVARCHAR(4),
  IN  IV_GJAHR    NVARCHAR(4),
  OUT OT_SALDOS   TABLE(
    HKONT   NVARCHAR(10),
    SALDO   DECIMAL(15,2),
    WAERS   NVARCHAR(5)
  )
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER AS
BEGIN
  DECLARE lv_error NVARCHAR(200);

  OT_SALDOS = SELECT
    HKONT,
    SUM(CASE WHEN SHKZG = 'S' THEN HSL ELSE -HSL END) AS SALDO,
    WAERS
  FROM "SAPHANADB"."BSIS"  -- HANA synonym to S4 table
  WHERE BUKRS = :IV_BUKRS
    AND GJAHR = :IV_GJAHR
  GROUP BY HKONT, WAERS;

  IF RECORD_COUNT(:OT_SALDOS) = 0 THEN
    SIGNAL SQL_ERROR_CODE 10001
      SET MESSAGE_TEXT = 'No se encontraron saldos para la sociedad ' || :IV_BUKRS;
  END IF;
END;
```

### 3. Vista HDI (.hdbview)

```sql
-- archivo: db/src/views/CV_ORDERS_SUMMARY.hdbview
VIEW "CV_ORDERS_SUMMARY" AS
SELECT
  O.ID,
  O.ORDER_NO,
  O.STATUS,
  O.CREATED_AT,
  O.CREATED_BY,
  SUM(I.QUANTITY * I.PRICE) AS TOTAL_AMOUNT,
  COUNT(I.ID)               AS ITEM_COUNT
FROM "MY_APP_ORDERS" O
JOIN "MY_APP_ORDER_ITEMS" I ON I.ORDER_ID = O.ID
GROUP BY O.ID, O.ORDER_NO, O.STATUS, O.CREATED_AT, O.CREATED_BY
WITH READ ONLY;
```

### 4. Analytical Privilege (Row-Level Security)

```sql
CREATE STRUCTURED PRIVILEGE "AP_VENTAS_POR_SOCIEDAD"
FOR SELECT ON CALCULATION VIEW "CV_VENTAS_ANALISIS"
WHERE "BUKRS" = SESSION_CONTEXT('SAP_COMPANYCODE');
```

### 5. Smart Data Access (Virtual Table)

```sql
CREATE VIRTUAL TABLE "VT_S4_EKKO"
AT "S4HANA_REMOTE_SOURCE"."<NULL>"."SAPHANADB"."EKKO";
```
