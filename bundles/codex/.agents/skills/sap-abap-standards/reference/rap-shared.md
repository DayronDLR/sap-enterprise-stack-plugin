# RAP — RESTful ABAP Programming Model (Referencia Compartida)

> **Uso:** Referencia consolidada para Agente 04 (Fiori/UI5) y Agente 06 (ABAP Developer).
> Contiene los patrones RAP esenciales: CDS, BDEF, Service, EML.

## Tipos de RAP Business Objects

- **Managed**: SAP gestiona CRUD automáticamente sobre tabla persistente. Usar para entidades nuevas.
- **Unmanaged**: Lógica CRUD propia (legado). Usar para wrapping de BAPIs/FMs existentes.
- **Abstract**: Sin persistencia, para servicios de cálculo/acción.

## CDS Interface View (Base View)

```abap
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory: #M,
  dataClass: #TRANSACTIONAL
}
define view entity ZI_<Entity>
  as select from <db_table> as header
  association [0..1] to <related> as _Child on $projection.Key = _Child.key_field
{
  key header.key_field       as KeyField,
      header.field1          as Field1,
      header.field2          as Field2,
      @Semantics.amount.currencyCode: 'Currency'
      header.amount          as Amount,
      header.waers           as Currency,
      @Semantics.systemDateTime.lastChangedAt: true
      header.last_changed    as LastChangedAt,
      -- Associations expuestas
      _Child
}
```

## CDS Projection View (Consumption View)

```abap
@EndUserText.label: '<Entity Label>'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define root view entity ZC_<Entity>
  provider contract transactional_query
  as projection on ZI_<Entity>
{
  key KeyField,
      Field1,
      Field2,
      Amount,
      Currency,
      LastChangedAt,
      _Child : redirected to composition child ZC_<ChildEntity>
}
```

## Behavior Definition (Managed con Draft)

```abap
managed implementation in class ZBP_<Entity> unique;
strict ( 2 );
with draft;

define behavior for ZC_<Entity> alias <Alias>
persistent table <z_table>
draft table <z_draft_table>
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
{
  -- Campos de sistema (read-only):
  field ( readonly ) KeyField, CreatedBy, LastChangedAt, LocalLastChangedAt;

  -- Campos obligatorios:
  field ( mandatory : create ) Field1, Field2;

  -- Feature control:
  field ( features : instance ) Status;

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
  action ( features : instance ) Approve result [1] $self;
  action ( features : instance ) Reject
    parameter <z_param_structure>
    result [1] $self;

  -- Determinaciones:
  determination setInitialStatus on modify { create; }

  -- Validaciones:
  validation validateField1 on save { create; update; }

  -- Side effects:
  side effects {
    field Field1 affects field Field2;
    action Approve affects field Status;
  }

  -- Mapeo a tabla persistente:
  mapping for <z_table> corresponding including additional fields
  {
    KeyField = key_field;
    Status   = status;
  }
}

"-- Child entity (composicion):
define behavior for ZC_<ChildEntity> alias <ChildAlias>
persistent table <z_child_table>
draft table <z_draft_child_table>
lock dependent by _Parent
authorization dependent by _Parent
etag master LocalLastChangedAt
{
  field ( readonly ) KeyField, ItemNo;
  update;
  delete;
  field ( mandatory : create ) Material, Quantity;
  validation validateMaterial on save { create; update; }
  mapping for <z_child_table> corresponding;
}
```

## Service Definition + Service Binding

```abap
"-- Service Definition:
@EndUserText.label: '<Entity> Service'
define service ZUI_<Entity>_O4 {
  expose ZC_<Entity>      as <Entity>;
  expose ZC_<ChildEntity> as <ChildEntity>;
}

"-- Service Binding:
"-- Tipo: OData V4 - UI (para Fiori Elements con Draft)
"-- Tipo: OData V4 - Web API (para APIs REST consumidas por BTP/CAP)
"-- Publicar → genera URL: /sap/opu/odata4/...
```

## EML (Entity Manipulation Language) — Ejemplos Basicos

```abap
"-- READ ENTITIES:
READ ENTITIES OF ZC_<Entity>
  ENTITY <Alias>
    FIELDS ( KeyField Field1 Amount Status )
    WITH VALUE #( ( %key-KeyField = '<value>' ) )
  RESULT DATA(lt_result)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).

"-- MODIFY — CREATE:
MODIFY ENTITIES OF ZC_<Entity>
  ENTITY <Alias>
    CREATE FIELDS ( Field1 Field2 )
      WITH VALUE #( ( %cid       = 'CID_1'
                      Field1     = 'value1'
                      Field2     = 'value2' ) )
  MAPPED   DATA(lt_mapped)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES
  RESPONSE OF ZC_<Entity>
  FAILED   DATA(lt_commit_failed)
  REPORTED DATA(lt_commit_reported).

"-- MODIFY — EXECUTE ACTION:
MODIFY ENTITIES OF ZC_<Entity>
  ENTITY <Alias>
    EXECUTE Approve
      FROM VALUE #( ( %key-KeyField = '<value>' ) )
  RESULT   DATA(lt_result)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES.

"-- DEEP INSERT (con composicion hijo):
MODIFY ENTITIES OF ZC_<Entity>
  ENTITY <Alias>
    CREATE FIELDS ( Field1 Field2 )
      WITH VALUE #( ( %cid = 'P1' Field1 = 'val1' Field2 = 'val2' ) )
  ENTITY <ChildAlias>
    CREATE BY \_Child
      FROM VALUE #( ( %cid_ref = 'P1'
                      %target  = VALUE #(
                        ( %cid = 'ITEM1' Material = 'MAT001' Quantity = '10' ) ) ) )
  MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
COMMIT ENTITIES.
```

## Naming Convention (S/4HANA Clean)

```text
CDS Interface View:   ZI_[Objeto]         → ZI_PurchaseOrder
CDS Projection View:  ZC_[Objeto]         → ZC_PurchaseOrder
Behavior Definition:  misma raiz que CDS  → ZC_PurchaseOrder
Behavior Impl Class:  ZBP_[CDS]           → ZBP_C_PurchaseOrder
Service Definition:   ZUI_[Obj]_O4        → ZUI_PurchaseOrder_O4
Service Binding:      ZUI_[Obj]_O4        → ZUI_PurchaseOrder_O4
Draft Table:          ZDRAFT_[OBJETO]     → ZDRAFT_PURCHASEORDER
```

## Checklist RAP BO Completo

- [ ] Tabla persistente (si es managed)
- [ ] Draft table (si usa Draft)
- [ ] CDS Interface View con @AccessControl y @ObjectModel
- [ ] CDS Projection View con provider contract
- [ ] Access Control (DCL) para Interface View
- [ ] Metadata Extension (.MDE) con @UI annotations
- [ ] Behavior Definition con lock, etag, authorization
- [ ] Behavior Implementation (handler + saver si unmanaged)
- [ ] ABAP Unit Tests (cl_abap_behv_test_environment)
- [ ] Service Definition
- [ ] Service Binding publicado (OData V4)
