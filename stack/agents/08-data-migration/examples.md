# 📦 AGENTE 07 — Ejemplos de Uso

## Ejemplo 1: Migración de Materiales desde Oracle EBS a SAP S/4HANA

**Prompt de entrada:**

```text
Genera el mapeo de campos para migrar materiales de manufactura desde Oracle EBS a SAP S/4HANA.
Sistema legacy: Oracle EBS R12 (tabla MTL_SYSTEM_ITEMS_B).
Objeto SAP: Material Master vistas: Basic, MRP1, MRP2, Storage, Purchasing, Accounting.
Volumen: 8,500 materiales activos.
Herramienta: LTMC (SAP S/4HANA Migration Cockpit).
```

**Output esperado del agente:**

- Mapeo de campos completo en formato tabla:

| # | Campo EBS | Tipo EBS | Campo SAP | Tabla SAP | Obligatorio | Transformación |
| --- | ----------- | ---------- | ----------- | ----------- | ------------- | ---------------- |
| 1 | SEGMENT1 | VARCHAR2(40) | MATNR | MARA | Sí | LPAD(SEGMENT1, 18, '0') |
| 2 | DESCRIPTION | VARCHAR2(240) | MAKTX | MAKT | Sí | SUBSTR(0,40) → truncar |
| 3 | PRIMARY_UOM_CODE | VARCHAR2(3) | MEINS | MARA | Sí | MAP: 'EA'→'UN', 'KG'→'KG', 'LB'→'LB' |
| 4 | ITEM_TYPE | VARCHAR2(30) | MTART | MARA | Sí | MAP: 'FINISHED'→'FERT', 'RAW'→'ROH' |
| 5 | PLANNER_CODE | VARCHAR2(10) | DISPO | MARC | No | Lookup en tabla de planificadores Z |
| ... | ... | ... | ... | ... | ... | ... |

- Script SQL de extracción Oracle con WHERE ENABLED_FLAG='Y' AND ORGANIZATION_ID=204
- Script Python de transformación y validación:
  - Longitud de MATNR ≤ 18 caracteres
  - MTART válido en tabla T134
  - MEINS válido en tabla T006
  - Deduplicación por MATNR
- Plantilla LTMC: objeto `MM_MATERIAL` con hojas por vista
- Reporte de calidad: % campos obligatorios llenos, distribución por MTART
- Volumen de errores esperados: ~3-5% (materiales sin unidad de medida SAP equivalente)

---

## Ejemplo 2: Migración de Saldos GL para Cutover Financiero

**Prompt de entrada:**

```text
Diseña el proceso de migración de saldos de cuentas de mayor (GL) para el cutover.
Sistema legacy: SAP ECC 6.0.
Objeto: Saldos iniciales de todas las cuentas GL al 31/12/2024 (fecha de corte).
Sociedad: 1000, Moneda: MXN, con moneda paralela USD.
Volumen: 450 cuentas GL activas.
Restricción: los débitos deben igual a créditos por cada período.
Herramienta: FB01 / LTMC Financial Accounting Opening Balances.
```

**Output esperado del agente:**

- Script SQL para extraer saldos de ECC (tablas GLT0 o FAGLFLEXT):

```sql
SELECT
  RYEAR,    -- Año fiscal
  RACCT,    -- Cuenta GL
  RBUKRS,   -- Sociedad
  SUM(CASE WHEN DRCRK='S' THEN HSL ELSE 0 END) AS DEBIT_LOCAL,
  SUM(CASE WHEN DRCRK='H' THEN HSL ELSE 0 END) AS CREDIT_LOCAL,
  SUM(CASE WHEN DRCRK='S' THEN KSL ELSE 0 END) AS DEBIT_USD,
  SUM(CASE WHEN DRCRK='H' THEN KSL ELSE 0 END) AS CREDIT_USD
FROM FAGLFLEXT
WHERE RBUKRS = '1000' AND RYEAR = '2024'
GROUP BY RYEAR, RACCT, RBUKRS
```

- Validación de cuadre: `SUM(DEBIT) = SUM(CREDIT)` por período (tolerancia 0)
- Mapeo a plantilla FB01: CoCd, PostingDate=31122024, DocType=SA, Account, D/C, Amount
- Proceso de carga en 2 pasos: simulación (sin batch input posting) → validación → carga real
- Reporte de conciliación: saldo ECC vs saldo S/4HANA post-carga (diferencia = 0 requerido)
- Runbook de go-live: ventana de 4 horas, no hay opción de rollback parcial (reversión completa con transacción FBRA)

---

## Ejemplo 3: Script Python de Transformación — Proveedores desde Excel Consolidado

**Prompt de entrada:**

```text
Crea un script Python para transformar y validar un archivo Excel con datos de proveedores
para cargar en SAP S/4HANA como Business Partners.
El Excel tiene: RazonSocial, RFC, Calle, Ciudad, Estado, CP, Banco, CLABE.
SAP espera: BP con rol FI-Vendor (FLVN00) + datos bancarios.
Validaciones: RFC válido (México), CLABE 18 dígitos, datos obligatorios presentes.
Herramienta destino: LTMC objeto BP_SUPPLIER.
```

**Output esperado del agente:**

```python
import pandas as pd
import re
from pathlib import Path

def validate_rfc_mx(rfc: str) -> bool:
    """Valida formato RFC México (personas morales y físicas)"""
    pattern = r'^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$'
    return bool(re.match(pattern, str(rfc).strip().upper()))

def validate_clabe(clabe: str) -> bool:
    """Valida CLABE interbancaria 18 dígitos con dígito verificador"""
    clabe = str(clabe).strip()
    if len(clabe) != 18 or not clabe.isdigit():
        return False
    weights = [3,7,1,3,7,1,3,7,1,3,7,1,3,7,1,3,7]
    check = (10 - sum(int(c)*w for c,w in zip(clabe[:17], weights)) % 10) % 10
    return check == int(clabe[17])

def transform_suppliers(input_file: str, output_file: str):
    df = pd.read_excel(input_file, dtype=str)
    errors = []

    # Validaciones
    for idx, row in df.iterrows():
        if not validate_rfc_mx(row.get('RFC', '')):
            errors.append(f"Fila {idx+2}: RFC inválido '{row.get('RFC')}'")
        if not validate_clabe(row.get('CLABE', '')):
            errors.append(f"Fila {idx+2}: CLABE inválida '{row.get('CLABE')}'")
        for field in ['RazonSocial', 'RFC', 'Calle', 'Ciudad', 'CP']:
            if pd.isna(row.get(field)) or str(row.get(field,'')) == '':
                errors.append(f"Fila {idx+2}: Campo obligatorio vacío '{field}'")

    # Transformación a plantilla LTMC
    ltmc_df = pd.DataFrame({
        'BusinessPartnerName': df['RazonSocial'].str[:80],
        'TaxNumber1': df['RFC'].str.upper(),
        'StreetName': df['Calle'].str[:60],
        'CityName': df['Ciudad'].str[:40],
        'Region': df['Estado'].map({'CDMX':'CMX','JAL':'JAL','NL':'NLE'}),
        'PostalCode': df['CP'].str.zfill(5),
        'BankAccount': df['CLABE'],
        'BankCountryKey': 'MX',
        'BankNumber': df['CLABE'].str[:6],  # Primeros 6 dígitos = banco + plaza
    })

    ltmc_df.to_excel(output_file, index=False)
    print(f"Procesados: {len(df)} | Errores: {len(errors)}")
    for e in errors[:20]:
        print(f"  ❌ {e}")

transform_suppliers('proveedores_legacy.xlsx', 'ltmc_bp_supplier.xlsx')
```

- Reporte de calidad: % registros válidos, top errores frecuentes
- Estimación de esfuerzo de cleansing por tipo de error

---

## Casos de Uso Frecuentes

- Migración de activos fijos con valores históricos y depreciación acumulada
- Carga de inventarios iniciales con MIGO + documento de ajuste
- Migración de órdenes de compra abiertas (órdenes marco, open POs)
- Migración de clientes con información de crédito desde CRM legacy
- Data quality assessment pre-migración con perfiles de calidad en BODS
