# RAP — RESTful ABAP Programming Model, completo

> Material de referencia del agente ABAP. Se lee bajo demanda.

## RAP — RESTful ABAP Programming Model (COMPLETO)

> Referencia RAP completa en `sap-abap-standards/reference/rap-shared.md`

### Tipos de RAP Business Objects

- **Managed**: SAP gestiona CRUD automáticamente sobre tabla persistente. Usar para entidades nuevas.
- **Unmanaged**: Lógica CRUD propia (legado). Usar para wrapping de BAPIs/FMs existentes.
- **Abstract**: Sin persistencia, para servicios de cálculo/acción.

### CDS para RAP — Capas Completas

```abap
"-- Tabla persistente del BO:
@EndUserText.label: 'Z Purchase Order Extension'
define table zpurchord_ext {
  key client      : abap.clnt not null;
  key po_number   : abap.char(10) not null;
  approval_status : abap.char(1);
  approved_by     : abap.char(12);
  local_last_changed_at : abp_lastchange_tstmpl;
  last_changed_at : abp_lastchange_tstmpl;
  created_at      : abp_creation_tstmpl;
}

"-- Draft table (para Draft handling):
define table zdraft_purchord {
  key mandt         : abap.clnt not null;
  key draftUUID     : sysuuid_x16 not null;
  po_number         : abap.char(10);
  approval_status   : abap.char(1);
  draftEntityCreationDateTime : abp_creation_tstmpl;
  draftEntityLastChangedDateTime : abp_lastchange_tstmpl;
  draftIsCreatedByMe : abp_boolean;
}
```

### Behavior Definition Managed con Draft

```abap
managed implementation in class zbp_c_purchaseorder unique;
strict ( 2 );
with draft;

define behavior for ZC_PurchaseOrder alias PurchaseOrder
persistent table zpurchord_ext
draft table zdraft_purchord
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
{
  -- Campos de sistema (read-only siempre):
  field ( readonly )
    PurchaseOrder, CreatedBy, LastChangedDate, LocalLastChangedAt;

  -- Campos obligatorios:
  field ( mandatory : create )
    Vendor, CompanyCode;

  -- Feature control (habilita/deshabilita campos por estado):
  field ( features : instance )
    ApprovalStatus;

  -- Operaciones estándar:
  create;
  update;
  delete;

  -- Draft workflow:
  draft action Edit;
  draft action Activate optimized;
  draft action Discard;
  draft action Resume;
  draft determine action Prepare;

  -- Acciones de negocio:
  action ( features : instance ) Approve
    result [1] $self;
  action ( features : instance ) Reject
    parameter zs_reject_param
    result [1] $self;

  -- Determinaciones (se ejecutan automáticamente):
  determination setInitialStatus on modify { create; }
  determination recalculateTotals on modify { field NetAmount; }

  -- Validaciones (se ejecutan en Save):
  validation validateVendor   on save { create; update; }
  validation validateAmount   on save { create; update; }

  -- Side effects (refresca campos en UI cuando otro cambia):
  side effects {
    field Vendor affects field VendorName;
    field CompanyCode affects field Currency;
    action Approve affects field ApprovalStatus;
  }

  -- Mapeo a tabla persistente:
  mapping for zpurchord_ext corresponding including additional fields
  {
    PurchaseOrder   = po_number;
    ApprovalStatus  = approval_status;
    ApprovedBy      = approved_by;
    LocalLastChangedAt = local_last_changed_at;
    LastChangedAt   = last_changed_at;
    CreatedAt       = created_at;
  }
}

"-- Child entity (composición):
define behavior for ZC_PurchaseOrderItem alias POItem
persistent table zpurchord_item_ext
draft table zdraft_purchord_item
lock dependent by _PurchaseOrder
authorization dependent by _PurchaseOrder
etag master LocalLastChangedAt
{
  field ( readonly ) PurchaseOrder, ItemNo;
  update;
  delete;
  field ( mandatory : create ) Material, Quantity;
  validation validateMaterial on save { create; update; }
  mapping for zpurchord_item_ext corresponding;
}
```

### Behavior Implementation — Clase Global

```abap
CLASS zbp_c_purchaseorder DEFINITION PUBLIC ABSTRACT FINAL
  FOR BEHAVIOR OF ZC_PurchaseOrder.
ENDCLASS.
CLASS zbp_c_purchaseorder IMPLEMENTATION.
ENDCLASS.

"-- Local handler class (dentro del global class include):
CLASS lhc_purchaseorder DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      "-- Authorization
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING REQUEST requested_authorizations FOR PurchaseOrder RESULT result,
      get_instance_features FOR INSTANCE FEATURES
        IMPORTING keys REQUEST requested_features FOR PurchaseOrder RESULT result,

      "-- Determinations
      setInitialStatus FOR DETERMINE ON MODIFY
        IMPORTING keys FOR PurchaseOrder~setInitialStatus,
      recalculateTotals FOR DETERMINE ON MODIFY
        IMPORTING keys FOR PurchaseOrder~recalculateTotals,

      "-- Validations
      validateVendor FOR VALIDATE ON SAVE
        IMPORTING keys FOR PurchaseOrder~validateVendor,
      validateAmount FOR VALIDATE ON SAVE
        IMPORTING keys FOR PurchaseOrder~validateAmount,

      "-- Actions
      approve FOR MODIFY
        IMPORTING keys FOR ACTION PurchaseOrder~Approve RESULT result,
      reject FOR MODIFY
        IMPORTING keys FOR ACTION PurchaseOrder~Reject RESULT result.
ENDCLASS.

CLASS lhc_purchaseorder IMPLEMENTATION.

  METHOD get_global_authorizations.
    AUTHORITY-CHECK OBJECT 'M_BEST_BSA' ID 'ACTVT' FIELD '01'.
    result-%create = COND #( WHEN sy-subrc = 0
      THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    result-%update = result-%create.
    result-%delete = result-%create.
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( ApprovalStatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED DATA(failed).

    result = VALUE #( FOR po IN lt_po
      ( %tky                           = po-%tky
        %action-Approve                = COND #( WHEN po-ApprovalStatus = 'A'
                                           THEN if_abap_behv=>fc-o-disabled
                                           ELSE if_abap_behv=>fc-o-enabled )
        %action-Reject                 = COND #( WHEN po-ApprovalStatus = 'R'
                                           THEN if_abap_behv=>fc-o-disabled
                                           ELSE if_abap_behv=>fc-o-enabled )
        %field-ApprovalStatus          = if_abap_behv=>fc-f-read_only ) ).
  ENDMETHOD.

  METHOD setInitialStatus.
    MODIFY ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus )
        WITH VALUE #( FOR key IN keys ( %tky = key-%tky ApprovalStatus = 'P' ) )
      REPORTED DATA(reported) FAILED DATA(failed).
  ENDMETHOD.

  METHOD validateVendor.
    READ ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( Vendor ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED DATA(failed).

    SELECT lifnr FROM lfa1
      FOR ALL ENTRIES IN @lt_po
      WHERE lifnr = @lt_po-Vendor
      INTO TABLE @DATA(lt_vendors).

    LOOP AT lt_po INTO DATA(lo_po).
      IF NOT line_exists( lt_vendors[ lifnr = lo_po-Vendor ] ).
        APPEND VALUE #( %tky = lo_po-%tky ) TO failed-purchaseorder.
        APPEND VALUE #(
          %tky           = lo_po-%tky
          %msg           = new_message_with_text(
                             severity = if_abap_behv_message=>severity-error
                             text     = |Vendor { lo_po-Vendor } does not exist| )
          %element-Vendor = if_abap_behv=>mk-on
        ) TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD approve.
    READ ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( ApprovalStatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED DATA(failed).

    MODIFY ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus ApprovedBy )
        WITH VALUE #( FOR po IN lt_po
          ( %tky           = po-%tky
            ApprovalStatus = 'A'
            ApprovedBy     = sy-uname ) )
      REPORTED DATA(rep) FAILED DATA(fail).

    result = VALUE #( FOR po IN lt_po
      ( %tky    = po-%tky
        %param  = CORRESPONDING #( po ) ) ).
  ENDMETHOD.

  METHOD reject.
    MODIFY ENTITIES OF ZC_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus )
        WITH VALUE #( FOR key IN keys
          ( %tky = key-%tky ApprovalStatus = 'R' ) )
      REPORTED DATA(rep) FAILED DATA(fail).
    result = VALUE #( FOR key IN keys ( %tky = key-%tky %param = VALUE #( ) ) ).
  ENDMETHOD.

ENDCLASS.

"-- Local Saver class (COMMIT/ROLLBACK para Unmanaged):
CLASS lsc_purchaseorder DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS check_before_save REDEFINITION.
    METHODS finalize          REDEFINITION.
    METHODS save              REDEFINITION.
    METHODS cleanup           REDEFINITION.
ENDCLASS.
```

### EML (Entity Manipulation Language) — Uso desde ABAP

```abap
"-- READ ENTITIES:
READ ENTITIES OF ZC_PurchaseOrder
  ENTITY PurchaseOrder
    FIELDS ( PurchaseOrder Vendor NetAmount ApprovalStatus )
    WITH VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
  RESULT DATA(lt_po)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).

"-- READ con ALL FIELDS:
READ ENTITIES OF ZC_PurchaseOrder
  ENTITY PurchaseOrder ALL FIELDS
    WITH CORRESPONDING #( lt_keys )
  RESULT DATA(lt_result).

"-- MODIFY — CREATE:
MODIFY ENTITIES OF ZC_PurchaseOrder
  ENTITY PurchaseOrder
    CREATE FIELDS ( Vendor CompanyCode DocumentDate )
      WITH VALUE #( ( %cid       = 'CID_1'
                      Vendor     = '0001000001'
                      CompanyCode = '1000'
                      DocumentDate = sy-datum ) )
  MAPPED   DATA(lt_mapped)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES
  RESPONSE OF ZC_PurchaseOrder
  FAILED   DATA(lt_commit_failed)
  REPORTED DATA(lt_commit_reported).

"-- MODIFY — EXECUTE ACTION:
MODIFY ENTITIES OF ZC_PurchaseOrder
  ENTITY PurchaseOrder
    EXECUTE Approve
      FROM VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
  RESULT   DATA(lt_result)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES.

"-- DEEP INSERT (con composición hijo):
MODIFY ENTITIES OF ZC_PurchaseOrder
  ENTITY PurchaseOrder
    CREATE FIELDS ( Vendor CompanyCode )
      WITH VALUE #( ( %cid = 'PO1' Vendor = '1000' CompanyCode = '1000' ) )
  ENTITY POItem
    CREATE BY \_POItem
      FROM VALUE #( ( %cid_ref = 'PO1'
                      %target  = VALUE #(
                        ( %cid = 'ITEM1' Material = 'MAT001' Quantity = '10' ) ) ) )
  MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
COMMIT ENTITIES.
```

### ABAP Unit Tests para RAP (CL_ABAP_BEHV_TEST_ENVIRONMENT)

```abap
CLASS ztc_po_behavior DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CLASS-DATA: mo_env TYPE REF TO if_abap_behv_test_environment.
    CLASS-METHODS: class_setup RAISING cx_static_check.
    CLASS-METHODS: class_teardown.

    METHODS: test_approve_changes_status FOR TESTING RAISING cx_static_check.
    METHODS: test_validate_vendor_fails  FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ztc_po_behavior IMPLEMENTATION.
  METHOD class_setup.
    mo_env = cl_abap_behv_test_environment=>create(
               entity_name = 'ZC_PURCHASEORDER' ).
  ENDMETHOD.

  METHOD class_teardown.
    mo_env->destroy( ).
  ENDMETHOD.

  METHOD test_approve_changes_status.
    "-- Arrange: crear PO de prueba
    mo_env->insert_test_data( EXPORTING instances = VALUE zpurchord_ext#(
      ( po_number = '4500000001' approval_status = 'P' ) ) ).

    "-- Act: ejecutar acción Approve via EML
    MODIFY ENTITIES OF ZC_PurchaseOrder
      ENTITY PurchaseOrder EXECUTE Approve
        FROM VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES.

    "-- Assert: verificar estado
    READ ENTITIES OF ZC_PurchaseOrder
      ENTITY PurchaseOrder FIELDS ( ApprovalStatus )
        WITH VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
      RESULT DATA(lt_result).

    cl_abap_unit_assert=>assert_equals(
      act = lt_result[ 1 ]-ApprovalStatus exp = 'A'
      msg = 'Status should be Approved' ).
  ENDMETHOD.

ENDCLASS.
```

## Service Definition y Binding

```abap
"-- Service Definition:
@EndUserText.label: 'Purchase Order Service'
define service ZUI_PurchaseOrder_O4 {
  expose ZC_PurchaseOrder    as PurchaseOrder;
  expose ZC_PurchaseOrderItem as PurchaseOrderItem;
}

"-- Service Binding:
"-- Tipo: OData V4 - UI (para Fiori Elements con Draft)
"-- Tipo: OData V4 - Web API (para APIs REST consumidas por BTP/CAP)
"-- Publicar → genera URL: /sap/opu/odata4/...
```
