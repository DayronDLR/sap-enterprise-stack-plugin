# ABAP Clasico — Reports y ALV Legacy

> **Uso:** Referencia para patrones ABAP clasicos. Consultar cuando se trabaje con
> reports ALV, Module Pool, o codigo legacy pre-RAP.

## Reports y ALV Moderno (CL_SALV_TABLE)

```abap
REPORT zfi_r_aging_ar.

TYPES: BEGIN OF ty_result,
         kunnr  TYPE kunnr,
         name1  TYPE name1,
         netwr  TYPE netwr,
         bucket TYPE string,    "0-30, 31-60, 61-90, +90
       END OF ty_result.

DATA: lt_result TYPE STANDARD TABLE OF ty_result,
      lo_alv    TYPE REF TO cl_salv_table.

PARAMETERS p_bukrs TYPE bukrs OBLIGATORY.

START-OF-SELECTION.
  PERFORM get_data.
  PERFORM display_alv.

FORM get_data.
  DATA: lv_days TYPE i.
  SELECT bsid~kunnr, kna1~name1, bsid~dmbtr AS netwr, bsid~bldat
    FROM bsid
    INNER JOIN kna1 ON kna1~kunnr = bsid~kunnr
    WHERE bsid~bukrs = @p_bukrs
      AND bsid~augdt = '00000000'
    INTO TABLE @DATA(lt_open_items).

  LOOP AT lt_open_items INTO DATA(ls_item).
    lv_days = cl_abap_context_info=>get_system_date( ) - ls_item-bldat.
    APPEND VALUE ty_result(
      kunnr  = ls_item-kunnr
      name1  = ls_item-name1
      netwr  = ls_item-netwr
      "-- SWITCH sólo compara valores exactos: los rangos van con COND
      bucket = COND #( WHEN lv_days <= 30 THEN '0-30'
                       WHEN lv_days <= 60 THEN '31-60'
                       WHEN lv_days <= 90 THEN '61-90'
                       ELSE '+90' )
    ) TO lt_result.
  ENDLOOP.
ENDFORM.

FORM display_alv.
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_result ).

    DATA(lo_cols) = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    DATA(lo_functions) = lo_alv->get_functions( ).
    lo_functions->set_all( abap_true ).

    DATA(lo_display) = lo_alv->get_display_settings( ).
    lo_display->set_striped_pattern( abap_true ).

    lo_alv->display( ).
  CATCH cx_salv_msg INTO DATA(lx_msg).
    MESSAGE lx_msg TYPE 'E'.
  ENDTRY.
ENDFORM.
```

## ABAP Clasico y OO — Expertise

- Reports: Selection screen, ALV (CL_SALV_TABLE, CL_GUI_ALV_GRID), eventos
- Module Pool: PAI/PBO, dynpros, tabstrips, subscreen
- ABAP OO: Clases, Interfaces, herencia, polimorfismo, Design Patterns (Factory, Strategy, Observer)
- Function Modules y RFCs: creacion, documentacion, manejo de excepciones
- BAPIs: uso y wrapping de BAPIs estandar
- Enhancement Framework: BAdIs (GET_BADI/CALL_BADI), Enhancement Spots, Implicit/Explicit Points
- User Exits: obsoletos pero reconocidos para legado
- DDIC: Tablas Z, Estructuras, Type Groups, Data Elements, Domains, Search Helps, Views
- ALV: CL_SALV_TABLE (recomendado), CL_GUI_ALV_GRID, field catalog, layout, events
- Performance: SELECT optimizado, FOR ALL ENTRIES, indices secundarios, SET/GET parameters, buffering
- BAPI Transactions: BAPI_TRANSACTION_COMMIT/ROLLBACK
