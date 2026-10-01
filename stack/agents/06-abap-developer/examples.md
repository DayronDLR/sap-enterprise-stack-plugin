# ⚙️ AGENTE 02 — Ejemplos de Uso

## Ejemplo 1: Report de Aging de Cuentas por Cobrar

**Prompt de entrada:**

```text
Crea un report ABAP de aging de cuentas por cobrar en SAP S/4HANA.
Datos origen: BSID (partidas abiertas clientes).
Pantalla de selección: Sociedad, Organización de ventas, Fecha clave.
Salida: ALV con columnas Cliente, Nombre, Moneda, 0-30 días, 31-60 días, 61-90 días, +90 días, Total.
Lógica: calcular bucket por diferencia entre fecha clave y fecha vencimiento (FAEDT).
```

**Output esperado del agente:**

- Report `ZFI_R_AGING_AR` completo con SE38 — **Standard ABAP** justificado (report + ALV); la alternativa Clean Core es CDS sobre `I_OperationalAcctgDocItem` + Fiori Elements
- Estructura `ZS_FI_AGING_LINE` con todos los buckets
- `SELECT` optimizado sobre BSID con índice secundario
- Cálculo de buckets con `DATEDIFF` o aritmética de fechas ABAP
- `CL_SALV_TABLE` con colores condicionales (rojo para +90 días)
- Manejo de moneda con conversión a moneda de display
- Transport instructions: TR con objetos PROG, TABD

---

## Ejemplo 2: BAdI para Bloqueo de Entrega por Crédito

**Prompt de entrada:**

```text
Implementa el BAdI SD_DELIVERY_PROCESSING en el método CHECK_DELIVERIES.
El objetivo es bloquear entregas de clientes que tengan facturas vencidas > 30 días
en SAP S/4HANA MM/SD.
La lógica debe consultar BSID, calcular el vencimiento y agregar mensaje de error al log.
```

**Output esperado del agente:**

- Verificar primero en SE18 que el BAdI y su método existan en el release del cliente
- Clase de implementación `ZBDI_SD_DELIVERY_CREDIT` en SE24
- Implementación de `CHECK_DELIVERIES` con lógica SELECT sobre BSID
- Uso de `MESSAGE` tipo E con clase de mensajes Z propia
- Manejo de excepciones con TRY/CATCH
- Documentación del Enhancement Spot y filtro de BAdI
- Casos de prueba: cliente con deuda vencida, cliente al día, cliente sin historial
- Objetos DDIC necesarios: ninguno (usa tablas estándar)

---

## Ejemplo 3: Code Review de Programa Existente

**Prompt de entrada:**

```text
Revisa este código ABAP e identifica problemas:

REPORT zsd_ventas.
TABLES: vbak, vbap, kna1.
SELECT * FROM vbak INTO TABLE @DATA(lt_vbak)
  WHERE vkorg = '1000'.
LOOP AT lt_vbak INTO DATA(ls_vbak).
  SELECT SINGLE * FROM kna1 INTO @DATA(ls_kna1)
    WHERE kunnr = ls_vbak-kunnr.
  SELECT * FROM vbap INTO TABLE @DATA(lt_vbap)
    WHERE vbeln = ls_vbak-vbeln.
  LOOP AT lt_vbap INTO DATA(ls_vbap).
    WRITE: / ls_vbak-vbeln, ls_vbap-posnr, ls_kna1-name1.
  ENDLOOP.
ENDLOOP.
```

**Output esperado del agente:**

1. 🔴 CRÍTICO: SELECT * en VBAK, KNA1, VBAP (seleccionar solo campos necesarios)
2. 🔴 CRÍTICO: SELECT dentro de LOOP → N+1 queries problem (usar JOIN o FOR ALL ENTRIES)
3. 🟡 MEDIO: WRITE sin ALV (usar CL_SALV_TABLE para output moderno)
4. 🟡 MEDIO: Sin manejo de SY-SUBRC en SELECT SINGLE
5. 🟢 SUGERENCIA: Usar CDS View ZC_SD_VENTAS si S/4HANA

- Código refactorizado completo con las correcciones
- Estimación de mejora de performance: 80-95% en datasets grandes

---

## Casos de Uso Frecuentes

- Reports de análisis financiero: aging, conciliación, balance de comprobación
- BAdIs de validación: ventas, compras, FI, producción
- RFCs para integración con sistemas externos (retorno de datos complejos)
- Programas de ajuste masivo de datos: application job en ABAP Cloud (`CL_PROGRESS_INDICATOR` sólo en Standard ABAP)
- ALV con opciones de exportación, sub-totales y variantes de visualización
- CDS Views con anotaciones para Fiori Embedded Analytics
