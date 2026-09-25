# Extensibilidad Clean Core: BAdIs y puntos de extensión

> Material de referencia del agente ABAP. Se lee bajo demanda.

## Extensibilidad Clean Core (BAdIs)

### Implementar BAdI con Enhancement Spot

```abap
"-- 1. Definir Enhancement Spot (SE18/ADT):
ENHANCEMENT-POINT zep_po_processing
  SPOTS zbadi_po_processing
  STATIC.

"-- 2. Definir BAdI dentro del spot:
ENHANCEMENT-SECTION zbadi_po_header
  FOR SPOT zbadi_po_processing.
  INTERFACE zbadi_if_po_header.
  METHODS:
    validate_po_header
      IMPORTING is_header    TYPE zs_po_header
      EXPORTING ev_rejected  TYPE abap_bool
                ev_message   TYPE string,
    enrich_po_header
      CHANGING  cs_header    TYPE zs_po_header.
ENDENHANCEMENT-SECTION.

"-- 3. Implementar BAdI (BADI_IMPL en SE19/ADT):
CLASS zbadi_impl_po_header DEFINITION PUBLIC
  INHERITING FROM cl_badi_default_implementation FINAL
  CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zbadi_if_po_header.
ENDCLASS.

CLASS zbadi_impl_po_header IMPLEMENTATION.
  METHOD zbadi_if_po_header~validate_po_header.
    ev_rejected = abap_false.
    IF is_header-netwr > 1000000.
      ev_rejected = abap_true.
      ev_message  = 'PO amount exceeds approval limit'.
    ENDIF.
  ENDMETHOD.

  METHOD zbadi_if_po_header~enrich_po_header.
    "-- Enriquecer con datos adicionales
    SELECT SINGLE name1 FROM lfa1 WHERE lifnr = @cs_header-lifnr
      INTO @cs_header-vendor_name.
  ENDMETHOD.
ENDCLASS.

"-- 4. Llamar BAdI desde el código (consumidor):
DATA(lo_badi) = zbadi_if_po_header~get_badi( ).
CALL BADI lo_badi->validate_po_header
  EXPORTING is_header   = ls_header
  IMPORTING ev_rejected = DATA(lv_rejected)
            ev_message  = DATA(lv_msg).
```
