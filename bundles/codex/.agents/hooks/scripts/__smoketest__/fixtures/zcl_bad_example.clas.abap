CLASS zcl_bad_example DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS process_orders.
ENDCLASS.

CLASS zcl_bad_example IMPLEMENTATION.
  METHOD process_orders.
    DATA: lt_orders TYPE TABLE OF vbak.
    " Smell 1: SELECT * sin PACKAGE SIZE
    SELECT * FROM vbak INTO TABLE lt_orders.
    " Smell 2: SELECT dentro de LOOP
    LOOP AT lt_orders INTO DATA(ls_order).
      SELECT SINGLE * FROM vbap INTO @DATA(ls_pos) WHERE vbeln = @ls_order-vbeln.
    ENDLOOP.
    " Smell 3: UPDATE directo a tabla SAP standard (Clean Core violation)
    UPDATE vbak SET netwr = 0 WHERE bukrs = '1000'.
    " Smell 4: CALL FUNCTION a modulo sin Z/BAPI
    CALL FUNCTION 'SD_SALESDOCUMENT_CHANGE' EXPORTING something = 'x'.
  ENDMETHOD.
ENDCLASS.
