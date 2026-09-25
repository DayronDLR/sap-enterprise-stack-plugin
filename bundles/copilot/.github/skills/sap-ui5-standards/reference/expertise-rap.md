# RAP — RESTful ABAP Programming Model, completo

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## RAP — RESTful ABAP Programming Model (COMPLETO)

> Referencia RAP completa en `sap-abap-standards/reference/rap-shared.md`

### Capas de CDS

```abap
"-- 1. CDS Base View (Interface View) — acceso a datos
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory: #M,
  dataClass: #TRANSACTIONAL
}
define view entity ZI_SalesOrder
  as select from vbak
  association [0..1] to ZI_BusinessPartner as _Partner on $projection.SoldToParty = _Partner.BusinessPartner
{
  key vbeln                    as SalesOrder,
      kunnr                    as SoldToParty,
      erdat                    as CreationDate,
      auart                    as OrderType,
      netwr                    as NetAmount,
      waerk                    as Currency,
      -- Associations expuestas
      _Partner
}

"-- 2. CDS Projection View (Consumption View) — expuesto al servicio OData
@EndUserText.label: 'Sales Order'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define root view entity ZC_SalesOrder
  provider contract transactional_query
  as projection on ZI_SalesOrder
{
  key SalesOrder,
      SoldToParty,
      CreationDate,
      OrderType,
      @Semantics.amount.currencyCode: 'Currency'
      NetAmount,
      Currency,
      /* Fiori Elements annotations */
      @UI.lineItem: [{ position: 10 }]
      @UI.selectionField: [{ position: 10 }]
      SalesOrder,
      _Partner : redirected to composition child ZC_SalesOrderItem
}
```

### Behavior Definition (Managed)

```abap
managed implementation in class ZBP_SalesOrder unique;
strict ( 2 );
with draft;

define behavior for ZC_SalesOrder alias SalesOrder
persistent table ZVBAK_EXT
draft table ZDRAFT_SALESORDER
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
{
  field ( readonly ) SalesOrder;
  field ( mandatory ) SoldToParty, OrderType;

  create;
  update;
  delete;

  draft action Edit;
  draft action Activate optimized;
  draft action Discard;
  draft action Resume;
  draft determine action Prepare;

  action ( features : instance ) Approve result [1] $self;
  action ( features : instance ) Reject  result [1] $self;

  determination setDefaultValues on modify { create; }
  validation   validateSoldToParty on save   { create; update; }

  side effects {
    field SoldToParty affects field NetAmount;
  }

  mapping for ZVBAK_EXT corresponding
  {
    SalesOrder = vbeln;
    SoldToParty = kunnr;
  }
}
```

### Behavior Implementation (Local Classes)

```abap
CLASS lhc_SalesOrder DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING REQUEST requested_authorizations FOR SalesOrder
        RESULT result,

      setDefaultValues FOR DETERMINE ON MODIFY
        IMPORTING keys FOR SalesOrder~setDefaultValues,

      validateSoldToParty FOR VALIDATE ON SAVE
        IMPORTING keys FOR SalesOrder~validateSoldToParty,

      approve FOR MODIFY
        IMPORTING keys FOR ACTION SalesOrder~Approve RESULT result,

      reject FOR MODIFY
        IMPORTING keys FOR ACTION SalesOrder~Reject RESULT result.
ENDCLASS.

CLASS lhc_SalesOrder IMPLEMENTATION.
  METHOD get_global_authorizations.
    AUTHORITY-CHECK OBJECT 'V_VBAK_AAT' ID 'ACTVT' FIELD '01'.
    result-%create = COND #( WHEN sy-subrc = 0 THEN if_abap_behv=>auth-allowed
                             ELSE if_abap_behv=>auth-unauthorized ).
  ENDMETHOD.

  METHOD validateSoldToParty.
    READ ENTITIES OF ZC_SalesOrder IN LOCAL MODE
      ENTITY SalesOrder FIELDS ( SoldToParty ) WITH CORRESPONDING #( keys )
      RESULT DATA(orders) FAILED DATA(failed).

    LOOP AT orders INTO DATA(order).
      SELECT SINGLE kunnr FROM kna1 WHERE kunnr = @order-SoldToParty INTO @DATA(lv_kunnr).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = order-%tky ) TO failed-salesorder.
        APPEND VALUE #( %tky        = order-%tky
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = |Partner { order-SoldToParty } no existe| )
                        %element-SoldToParty = if_abap_behv=>mk-on ) TO reported-salesorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD approve.
    MODIFY ENTITIES OF ZC_SalesOrder IN LOCAL MODE
      ENTITY SalesOrder UPDATE FIELDS ( Status )
        WITH VALUE #( FOR key IN keys ( %tky = key-%tky Status = 'A' ) )
      REPORTED DATA(reported_update) FAILED DATA(failed_update).
    result = VALUE #( FOR order IN keys ( %tky    = order-%tky
                                          %param  = VALUE #( SalesOrder = order-SalesOrder ) ) ).
  ENDMETHOD.
ENDCLASS.
```

### EML (Entity Manipulation Language)

```abap
"-- READ via EML
READ ENTITIES OF ZC_SalesOrder
  ENTITY SalesOrder FIELDS ( SalesOrder SoldToParty NetAmount )
    WITH VALUE #( ( %key-SalesOrder = '0000001000' ) )
  RESULT DATA(lt_orders)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).

"-- MODIFY via EML (crear)
MODIFY ENTITIES OF ZC_SalesOrder
  ENTITY SalesOrder CREATE FIELDS ( SoldToParty OrderType )
    WITH VALUE #( ( %cid = 'NEW1' SoldToParty = '0001000001' OrderType = 'TA' ) )
  MAPPED DATA(lt_mapped)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES.

"-- MODIFY via EML (acción)
MODIFY ENTITIES OF ZC_SalesOrder
  ENTITY SalesOrder EXECUTE Approve
    FROM VALUE #( ( %key-SalesOrder = '0000001000' ) )
  RESULT DATA(lt_result)
  FAILED DATA(lt_failed).
COMMIT ENTITIES.
```

### Service Definition y Binding

```abap
"-- Service Definition
@EndUserText.label: 'Sales Order Service'
define service ZUI_SalesOrder {
  expose ZC_SalesOrder as SalesOrder;
  expose ZC_SalesOrderItem as SalesOrderItem;
}

"-- Service Binding: tipo UI_V4_UI (OData V4 para Fiori Elements)
"-- Nombre: ZUI_SALESORDER_O4
"-- Binding Type: OData V4 - UI
"-- URL: /sap/opu/odata4/sap/zui_salesorder_o4/srvd/sap/zui_salesorder/0001/
```
