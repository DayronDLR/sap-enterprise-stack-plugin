# 🗄️ AGENTE 10 — Ejemplos de Uso

## Ejemplo 1: Calculation View para Dashboard de Ventas con Multi-Moneda

**Prompt de entrada:**

```text
Crea un Calculation View analítico en SAP HANA Cloud para analizar ventas de SAP S/4HANA.
Datos: tablas VBAK, VBAP, KNA1, MARA (via HDI synonyms desde S/4HANA).
Medidas: valor neto (NETWR), cantidad (KWMENG).
Dimensiones: cliente, material, organización ventas, fecha.
Convertir moneda: siempre mostrar en USD y MXN usando tablas de tipo de cambio TCURR/TCURX.
Input Parameter: fecha de análisis para tipo de cambio.
```

**Output esperado del agente:**

- Diseño del Calculation View Cube con Star Join:

```text
CV_SD_SALES_ANALYSIS (Cube, Star Join)
│
├── Fact Node: Projection sobre VBAP
│   Columnas: VBELN, POSNR, MATNR, KWMENG, NETWR, WAERS, ERDAT
│
├── Join 1: VBAK → VBAP (VBELN = VBELN)
│   Proyectar: VKORG, KUNNR, AUDAT
│
├── Dimension 1: CV_DIM_CUSTOMER
│   Fuente: KNA1 → KUNNR, NAME1, ORT01, LAND1
│
├── Dimension 2: CV_DIM_MATERIAL
│   Fuente: MARA → MATNR, MAKTX (join MAKT), MTART, MATKL
│
└── Currency Conversion Node:
    NETWR → NETWR_USD (moneda target: USD, tipo: P, fecha: IP_DATE)
    NETWR → NETWR_MXN (moneda target: MXN, tipo: P, fecha: IP_DATE)
```

- Artefactos HDI:
  - `db/src/synonyms/S4HANA_TABLES.hdbsynonym` (mapeo a VBAK, VBAP, etc. en S/4HANA)
  - `db/src/models/CV_SD_SALES_ANALYSIS.hdbcalculationview`
  - `db/src/roles/analytics_viewer.hdbrole`
  - `db/src/grants/S4HANA_ACCESS.hdbgrants`

- Analytical Privilege:

```sql
CREATE STRUCTURED PRIVILEGE "AP_SALES_BY_VKORG"
FOR SELECT ON CALCULATION VIEW "CV_SD_SALES_ANALYSIS"
WHERE "VKORG" IN (
  SELECT VKORG FROM "Z_USER_VKORG_MAPPING"
  WHERE SYS_USER = SESSION_CONTEXT('APPLICATIONUSER')
);
```

- Verificación de performance con EXPLAIN PLAN: engines esperados = JoinEngine + OLAP Engine
- Consumo en SAP Analytics Cloud: Live Connection, Story con input prompt de fecha

---

## Ejemplo 2: Procedimiento SQLScript para Cálculo de Comisiones

**Prompt de entrada:**

```text
Crea un procedimiento SQLScript en HANA Cloud para calcular comisiones de vendedores.
Lógica: base = ventas del mes, escalones:
  - 0-100k MXN: 2%
  - 100k-500k: 3.5%
  - >500k: 5%
Datos entrada: tabla Z_SALES_MONTHLY (VKBUR, PERNR, MONTH_YEAR, TOTAL_SALES, CURRENCY).
Tabla salida: Z_COMMISSIONS con los importes calculados.
Incluir manejo de errores y logging.
```

**Output esperado del agente:**

```sql
CREATE OR REPLACE PROCEDURE "MY_HDI_SCHEMA"."PROC_CALC_COMMISSIONS"(
  IN  IV_PERIOD   NVARCHAR(7),   -- Format: YYYY-MM
  OUT OV_ROWS_OK  INTEGER,
  OUT OV_ROWS_ERR INTEGER
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
  DECLARE lv_error_msg NVARCHAR(500);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 lv_error_msg = MESSAGE_TEXT;
    INSERT INTO "Z_PROC_LOG" VALUES(
      SYSUUID, 'PROC_CALC_COMMISSIONS', 'ERROR', lv_error_msg, CURRENT_TIMESTAMP
    );
    RESIGNAL;
  END;

  -- Limpiar período anterior
  DELETE FROM "Z_COMMISSIONS" WHERE PERIOD = :IV_PERIOD;

  -- Calcular comisiones con escalones
  INSERT INTO "Z_COMMISSIONS"
  SELECT
    SYSUUID               AS ID,
    :IV_PERIOD            AS PERIOD,
    PERNR,
    VKBUR,
    TOTAL_SALES,
    CURRENCY,
    CASE
      WHEN TOTAL_SALES <= 100000  THEN ROUND(TOTAL_SALES * 0.02, 2)
      WHEN TOTAL_SALES <= 500000  THEN ROUND(100000 * 0.02 + (TOTAL_SALES - 100000) * 0.035, 2)
      ELSE ROUND(100000 * 0.02 + 400000 * 0.035 + (TOTAL_SALES - 500000) * 0.05, 2)
    END                   AS COMMISSION,
    CURRENT_TIMESTAMP     AS CALC_DATE
  FROM "Z_SALES_MONTHLY"
  WHERE MONTH_YEAR = :IV_PERIOD
    AND TOTAL_SALES > 0;

  OV_ROWS_OK  = RECORD_COUNT(
    SELECT 1 FROM "Z_COMMISSIONS" WHERE PERIOD = :IV_PERIOD
  );
  OV_ROWS_ERR = 0;

  INSERT INTO "Z_PROC_LOG" VALUES(
    SYSUUID, 'PROC_CALC_COMMISSIONS', 'SUCCESS',
    'Rows processed: ' || OV_ROWS_OK, CURRENT_TIMESTAMP
  );
END;
```

- Tabla `Z_COMMISSIONS` DDL con tipos de dato correctos para HANA Cloud
- Script de verificación post-ejecución:

  ```sql
  SELECT VKBUR, SUM(TOTAL_SALES), SUM(COMMISSION),
         ROUND(SUM(COMMISSION)/SUM(TOTAL_SALES)*100, 2) AS COMMISSION_RATE_PCT
  FROM Z_COMMISSIONS WHERE PERIOD = '2025-01'
  GROUP BY VKBUR ORDER BY SUM(TOTAL_SALES) DESC;
  ```

- Configuración de job en HANA Cloud (execute monthly, 1st day of month, 6:00 AM)

---

## Ejemplo 3: Smart Data Access — Virtualización desde HANA Cloud a S/4HANA On-Premise

**Prompt de entrada:**

```text
Configura Smart Data Access (SDA) en HANA Cloud para acceder en tiempo real a tablas
de S/4HANA On-Premise sin replicar datos.
Tablas necesarias: MARA, MARC, MARD (materiales e inventario).
Queremos un Calculation View en HANA Cloud que combine datos de HANA Cloud local
con inventario en tiempo real desde S4.
Landscape: S/4HANA On-Premise 2022 con Cloud Connector en DMZ.
```

**Output esperado del agente:**

- Configuración Cloud Connector:
  1. Instalar SCC en DMZ del cliente
  2. Abrir canal: HANA Cloud → SCC → S/4HANA HANA DB (puerto 30015)
  3. Mapear virtual host en SCC: `s4hana-internal.corp` → hostname real
  4. Certificado SSL: usar certificado de S/4HANA HANA DB

- Configuración HANA Cloud (Remote Source via HANA Cloud Central):

```sql
-- En HANA Cloud, crear Remote Source
CREATE REMOTE SOURCE "S4HANA_ONPREM"
  ADAPTER "hanaodbc"
  CONFIGURATION
    'driver=libodbcHDB.so;
     host=s4hana-internal.corp;
     port=30015;
     databaseName=S4D'
  WITH CREDENTIAL TYPE 'PASSWORD'
    USING 'user=SDA_USER;password=****';
```text

- Virtual Tables:

```sql
CREATE VIRTUAL TABLE "VT_S4_MARA" AT "S4HANA_ONPREM"."<NULL>"."SAPHANADB"."MARA";
CREATE VIRTUAL TABLE "VT_S4_MARC" AT "S4HANA_ONPREM"."<NULL>"."SAPHANADB"."MARC";
CREATE VIRTUAL TABLE "VT_S4_MARD" AT "S4HANA_ONPREM"."<NULL>"."SAPHANADB"."MARD";
```text

- Synonyms en HDI para acceder a tablas virtuales desde aplicaciones:

  ```json
  { "VT_S4_MARD": { "target": { "object": "VT_S4_MARD", "schema": "VCAP_SCHEMA" } } }
```

- Calculation View híbrido:
  - Nodo local: inventario valorado desde HANA Cloud (tabla Z_VALUATION)
  - Nodo virtual: stock físico desde `VT_S4_MARD` en tiempo real
  - Join: por MATNR + WERKS

- Consideraciones de performance:
  - SDA agrega latencia de red (típico 50-200ms por query)
  - Preferir para queries puntuales, no para aggregations masivas
  - Para alto volumen: considerar Remote Table Replication (SDI) en su lugar

---

## Casos de Uso Frecuentes

- Calculation Views para embedded analytics en S/4HANA (KPI tiles en Fiori launchpad)
- Modelos analíticos para SAP Analytics Cloud con Live Connection
- SQLScript procedures para cálculos complejos de controlling (costeo, allocations)
- HDI containers para aplicaciones CAP con lógica de base de datos nativa HANA
- BW/4HANA: diseño de DataStore Objects (DSO avanzados) y CompositeProviders
- HANA Data Lake para archivado de datos históricos con acceso analítico
