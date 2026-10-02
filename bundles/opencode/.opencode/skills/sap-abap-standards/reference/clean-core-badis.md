# Extensibilidad Clean Core: BAdIs y puntos de extensión

> Material de referencia del agente ABAP. Se lee bajo demanda.

## Extensibilidad Clean Core (BAdIs)

### Implementar BAdI con Enhancement Spot

El Enhancement Spot y la definición del BAdI **no se escriben como código**: son
objetos de repositorio que se crean en ADT (*New → Other ABAP Repository Object →
Enhancement Spot*) o en SE18. Lo que sí es código es la interfaz, la implementación
y la llamada:

```abap
"-- 1. Interfaz del BAdI (SE24/ADT). Toda interfaz de BAdI incluye IF_BADI_INTERFACE.
INTERFACE zif_badi_po_header PUBLIC.
  INTERFACES if_badi_interface.
  METHODS validate_po_header
    IMPORTING is_header   TYPE zs_po_header
    EXPORTING ev_rejected TYPE abap_bool
              ev_message  TYPE string.
  METHODS enrich_po_header
    CHANGING cs_header TYPE zs_po_header.
ENDINTERFACE.

"-- 2. Enhancement Spot ZES_PO_PROCESSING con el BAdI ZBADI_PO_HEADER (ADT/SE18),
"--    interfaz ZIF_BADI_PO_HEADER. Sin código: es un objeto de repositorio.
"--    BAdI de USO ÚNICO (sin «Multiple Use»): la interfaz devuelve EXPORTING, que
"--    un BAdI de uso múltiple no admite, y sólo GET BADI de uso único lanza
"--    CX_BADI_NOT_IMPLEMENTED cuando no hay implementación ni fallback.

"-- 3. Implementación (Enhancement Implementation en ADT/SE19): una clase que
"--    implementa la interfaz.
CLASS zcl_badi_po_header_impl DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_badi_po_header.   "-- trae IF_BADI_INTERFACE con la interfaz
ENDCLASS.

CLASS zcl_badi_po_header_impl IMPLEMENTATION.
  METHOD zif_badi_po_header~validate_po_header.
    ev_rejected = abap_false.
    IF is_header-netwr > 1000000.
      ev_rejected = abap_true.
      ev_message  = 'PO amount exceeds approval limit'.
    ENDIF.
  ENDMETHOD.

  METHOD zif_badi_po_header~enrich_po_header.
    SELECT SINGLE name1 FROM lfa1 WHERE lifnr = @cs_header-lifnr
      INTO @cs_header-vendor_name.
  ENDMETHOD.
ENDCLASS.

"-- 4. Llamada desde el consumidor: GET BADI con la referencia tipada al BAdI.
DATA lo_badi     TYPE REF TO zbadi_po_header.
DATA lv_rejected TYPE abap_bool.
DATA lv_msg      TYPE string.

TRY.
    GET BADI lo_badi.
    CALL BADI lo_badi->validate_po_header
      EXPORTING is_header   = ls_header
      IMPORTING ev_rejected = lv_rejected
                ev_message  = lv_msg.
  CATCH cx_badi_not_implemented.
    "-- Sin implementación activa y sin fallback: el BAdI no aplica.
    lv_rejected = abap_false.
  CATCH cx_badi_multiply_implemented INTO DATA(lx_multi).
    "-- Uso único con dos implementaciones activas sin filtro: es un error de
    "-- configuración. Se propaga (y se loguea en SLG1 quien la atrape): nunca
    "-- elegir una al azar ni seguir en silencio.
    RAISE EXCEPTION NEW zcx_po_processing( previous = lx_multi ).
ENDTRY.
```
