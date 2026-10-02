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
// Tabla persistente del BO (nombre ≤ 16):
@EndUserText.label: 'Z Purchase Order Extension'
define table zpurchord {
  key client      : abap.clnt not null;
  key po_number   : abap.char(10) not null;
  approval_status : abap.char(1);
  approved_by     : abap.char(12);
  local_last_changed_at : abp_locinst_lastchange_tstmpl;
  last_changed_at : abp_lastchange_tstmpl;
  created_at      : abp_creation_tstmpl;
}

// Draft table: generarla con el quick fix del BDEF en ADT. Campos = elementos CDS. Nombre ≤ 16.
@EndUserText.label : 'Draft - Z Purchase Order Extension'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zpurchord_d {
  key client         : abap.clnt not null;
  key purchaseorder  : abap.char(10) not null;
  approvalstatus     : abap.char(1);
  approvedby         : abap.char(12);
  locallastchangedat : abp_locinst_lastchange_tstmpl;
  lastchangedat      : abp_lastchange_tstmpl;
  createdat          : abp_creation_tstmpl;
  "%admin"           : include sych_bdl_draft_admin_inc;
}
```

### Behavior Definition Managed con Draft

> `managed` va sobre la root view entity base `ZI_PurchaseOrder`; la projection
> `ZC_PurchaseOrder` lleva su propio BDEF `projection`. Comentarios BDL: `//`.

```abap
// BDEF base: mismo nombre que la root view entity ZI_PurchaseOrder
managed implementation in class zbp_i_purchaseorder unique;
strict ( 2 );
with draft;

define behavior for ZI_PurchaseOrder alias PurchaseOrder
persistent table zpurchord          // ≤ 16 caracteres
draft table zpurchord_d             // ≤ 16 caracteres, sufijo _D
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
{
  // Campos de sistema (read-only siempre):
  field ( readonly )
    PurchaseOrder, CreatedBy, LastChangedAt, LocalLastChangedAt;

  // Campos obligatorios:
  field ( mandatory : create )
    Vendor, CompanyCode;

  // Feature control (habilita/deshabilita campos por estado):
  field ( features : instance )
    ApprovalStatus;

  // Operaciones estándar:
  create;
  update;
  delete;
  association _POItem { create; with draft; }

  // Draft workflow (strict: todas explícitas):
  draft action Edit;
  draft action Activate optimized;
  draft action Discard;
  draft action Resume;
  draft determine action Prepare
  {
    validation validateVendor;
    validation validateAmount;
  }

  // Acciones de negocio:
  action ( features : instance ) Approve result [1] $self;
  action ( features : instance ) Reject parameter zs_reject_param result [1] $self;

  // Determinaciones (se ejecutan automáticamente):
  determination setInitialStatus on modify { create; }
  determination recalculateTotals on modify { field NetAmount; }

  // Validaciones (se ejecutan en Save):
  validation validateVendor on save { create; update; field Vendor; }
  validation validateAmount on save { create; update; field NetAmount; }

  // Side effects (refresca campos en UI cuando otro cambia):
  side effects
  {
    field Vendor affects field VendorName;
    field CompanyCode affects field Currency;
    action Approve affects field ApprovalStatus;
  }

  // Mapeo a tabla persistente:
  mapping for zpurchord corresponding
  {
    PurchaseOrder      = po_number;
    ApprovalStatus     = approval_status;
    ApprovedBy         = approved_by;
    LocalLastChangedAt = local_last_changed_at;
    LastChangedAt      = last_changed_at;
    CreatedAt          = created_at;
  }
}

// Child entity (composición):
define behavior for ZI_PurchaseOrderItem alias POItem
persistent table zpurchord_itm
draft table zpurchord_itm_d
etag master LocalLastChangedAt
lock dependent by _PurchaseOrder
authorization dependent by _PurchaseOrder
{
  update;
  delete;
  field ( readonly ) PurchaseOrder, ItemNo;
  field ( mandatory : create ) Material, Quantity;
  association _PurchaseOrder { with draft; }
  validation validateMaterial on save { create; update; field Material; }
  mapping for zpurchord_itm corresponding;
}
```

### Behavior Definition de Projection

```abap
// BDEF projection: mismo nombre que ZC_PurchaseOrder (provider contract transactional_query)
projection;
strict ( 2 );
use draft;
use side effects;

define behavior for ZC_PurchaseOrder alias PurchaseOrder
use etag
{
  use create;
  use update;
  use delete;

  use action Edit;
  use action Activate;
  use action Discard;
  use action Resume;
  use action Prepare;

  use action Approve;
  use action Reject;

  use association _POItem { create; with draft; }
}

define behavior for ZC_PurchaseOrderItem alias POItem
use etag
{
  use update;
  use delete;
  use association _PurchaseOrder { with draft; }
}
```

### Behavior Implementation — Clase Global

```abap
CLASS zbp_i_purchaseorder DEFINITION PUBLIC ABSTRACT FINAL
  FOR BEHAVIOR OF ZI_PurchaseOrder.
ENDCLASS.
CLASS zbp_i_purchaseorder IMPLEMENTATION.
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
    READ ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( ApprovalStatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED failed.   "-- el parámetro implícito, no un local que lo tape

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
    MODIFY ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus )
        WITH VALUE #( FOR key IN keys ( %tky = key-%tky ApprovalStatus = 'P' ) )
      REPORTED DATA(lt_upd_reported).
    reported = CORRESPONDING #( DEEP lt_upd_reported ).
  ENDMETHOD.

  METHOD validateVendor.
    READ ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( Vendor ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED failed.   "-- el parámetro implícito, no un local que lo tape

    CHECK lt_po IS NOT INITIAL.  "-- FOR ALL ENTRIES con tabla vacía lee todo

    "-- I_Supplier (released) en vez de LFA1 (notToBeReleased)
    SELECT Supplier FROM I_Supplier
      FOR ALL ENTRIES IN @lt_po
      WHERE Supplier = @lt_po-Vendor
      INTO TABLE @DATA(lt_vendors).

    LOOP AT lt_po INTO DATA(lo_po).
      IF NOT line_exists( lt_vendors[ Supplier = lo_po-Vendor ] ).
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
    READ ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder FIELDS ( ApprovalStatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_po) FAILED failed.   "-- el parámetro implícito, no un local que lo tape

    MODIFY ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus ApprovedBy )
        WITH VALUE #( FOR po IN lt_po
          ( %tky           = po-%tky
            ApprovalStatus = 'A'
            ApprovedBy     = sy-uname ) )
      REPORTED reported FAILED failed.   "-- los parámetros del handler: un local los perdería

    result = VALUE #( FOR po IN lt_po
      ( %tky    = po-%tky
        %param  = CORRESPONDING #( po ) ) ).
  ENDMETHOD.

  METHOD reject.
    MODIFY ENTITIES OF ZI_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder UPDATE FIELDS ( ApprovalStatus )
        WITH VALUE #( FOR key IN keys
          ( %tky = key-%tky ApprovalStatus = 'R' ) )
      REPORTED reported FAILED failed.   "-- los parámetros del handler: un local los perdería
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
READ ENTITIES OF ZI_PurchaseOrder
  ENTITY PurchaseOrder
    FIELDS ( PurchaseOrder Vendor NetAmount ApprovalStatus )
    WITH VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
  RESULT DATA(lt_po)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).

"-- READ con ALL FIELDS:
READ ENTITIES OF ZI_PurchaseOrder
  ENTITY PurchaseOrder ALL FIELDS
    WITH CORRESPONDING #( lt_keys )
  RESULT DATA(lt_result).

"-- MODIFY — CREATE:
MODIFY ENTITIES OF ZI_PurchaseOrder
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
  RESPONSE OF ZI_PurchaseOrder
  FAILED   DATA(lt_commit_failed)
  REPORTED DATA(lt_commit_reported).

"-- MODIFY — EXECUTE ACTION:
MODIFY ENTITIES OF ZI_PurchaseOrder
  ENTITY PurchaseOrder
    EXECUTE Approve
      FROM VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
  RESULT   DATA(lt_result)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES.

"-- DEEP INSERT (con composición hijo):
MODIFY ENTITIES OF ZI_PurchaseOrder
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
               entity_name = 'ZI_PURCHASEORDER' ).
  ENDMETHOD.

  METHOD class_teardown.
    mo_env->destroy( ).
  ENDMETHOD.

  METHOD test_approve_changes_status.
    "-- Arrange: crear PO de prueba
    DATA lt_po TYPE STANDARD TABLE OF zpurchord WITH EMPTY KEY.
    lt_po = VALUE #( ( po_number = '4500000001' approval_status = 'P' ) ).
    mo_env->insert_test_data( EXPORTING instances = lt_po ).

    "-- Act: ejecutar acción Approve via EML
    MODIFY ENTITIES OF ZI_PurchaseOrder
      ENTITY PurchaseOrder EXECUTE Approve
        FROM VALUE #( ( %key-PurchaseOrder = '4500000001' ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES.

    "-- Assert: verificar estado
    READ ENTITIES OF ZI_PurchaseOrder
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
// Service Definition:
@EndUserText.label: 'Purchase Order Service'
define service ZUI_PurchaseOrder {
  expose ZC_PurchaseOrder     as PurchaseOrder;
  expose ZC_PurchaseOrderItem as PurchaseOrderItem;
}

// Service Binding:
// Tipo: OData V4 - UI (para Fiori Elements con Draft)
// Tipo: OData V4 - Web API (para APIs REST consumidas por BTP/CAP)
// Publicar → genera URL: /sap/opu/odata4/...
```
