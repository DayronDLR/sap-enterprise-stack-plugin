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
define root view entity ZI_<Entity>
  as select from <ztabla> as header
  composition [0..*] of ZI_<ChildEntity> as _Child
{
  key header.key_field       as KeyField,
      header.field1          as Field1,
      header.field2          as Field2,
      header.status          as Status,
      @Semantics.amount.currencyCode: 'Currency'
      header.amount          as Amount,
      header.waers           as Currency,
      @Semantics.user.createdBy: true
      header.created_by      as CreatedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      header.local_last_changed_at as LocalLastChangedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      header.last_changed    as LastChangedAt,
      -- Associations expuestas
      _Child
}

-- Hijo (composición): define view entity ZI_<ChildEntity> as select from <ztabla_itm>
--   association to parent ZI_<Entity> as _Parent on $projection.KeyField = _Parent.KeyField
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
      Status,
      Amount,
      Currency,
      CreatedBy,
      LocalLastChangedAt,
      LastChangedAt,
      _Child : redirected to composition child ZC_<ChildEntity>
}
```

## Behavior Definition (Managed con Draft)

> `managed` va **siempre** sobre la root view entity base `ZI_`; una projection
> BDEF empieza con `projection` y se basa en una CDS projection view
> (`abenbdl_bdef_projection_header.htm`). Con draft, `total etag` es obligatorio;
> en strict mode todas las draft actions se declaran explícitas en base y
> projection (`abenbdl_draft_action.htm`), y las asociaciones de composición
> llevan `with draft` (`abenbdl_with_draft.htm`). Comentarios BDL: `//`.

```abap
// BDEF base: mismo nombre que la root view entity ZI_<Entity>
managed implementation in class zbp_i_<entity> unique;
strict ( 2 );
with draft;

define behavior for ZI_<Entity> alias <Alias>
persistent table <ztabla>          // ≤ 16 caracteres
draft table <ztabla_d>             // ≤ 16 caracteres, sufijo _D
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
{
  field ( readonly ) KeyField, CreatedBy, LastChangedAt, LocalLastChangedAt;
  field ( mandatory : create ) Field1, Field2;
  field ( features : instance ) Status;

  create;
  update;
  delete;
  association _Child { create; with draft; }

  draft action Edit;
  draft action Activate optimized;
  draft action Discard;
  draft action Resume;
  draft determine action Prepare
  {
    validation validateField1;
  }

  action ( features : instance ) Approve result [1] $self;
  action ( features : instance ) Reject parameter <zs_param> result [1] $self;

  determination setInitialStatus on modify { create; }
  validation validateField1 on save { create; update; field Field1; }

  side effects
  {
    field Field1 affects field Field2;
    action Approve affects field Status;
  }

  mapping for <ztabla> corresponding
  {
    KeyField = key_field;
    Status   = status;
  }
}

define behavior for ZI_<ChildEntity> alias <ChildAlias>
persistent table <ztabla_itm>
draft table <ztabla_itm_d>
etag master LocalLastChangedAt
lock dependent by _Parent
authorization dependent by _Parent
{
  update;
  delete;
  field ( readonly ) KeyField, ItemNo;
  field ( mandatory : create ) Material, Quantity;
  association _Parent { with draft; }
  validation validateMaterial on save { create; update; field Material; }
  mapping for <ztabla_itm> corresponding;
}
```

### Behavior Definition de Projection

```abap
// BDEF projection: mismo nombre que ZC_<Entity> (provider contract transactional_query)
projection;
strict ( 2 );
use draft;
use side effects;

define behavior for ZC_<Entity> alias <Alias>
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

  use association _Child { create; with draft; }
}

define behavior for ZC_<ChildEntity> alias <ChildAlias>
use etag
{
  use update;
  use delete;
  use association _Parent { with draft; }
}
```

## Service Definition + Service Binding

```abap
// Service Definition:
@EndUserText.label: '<Entity> Service'
define service ZUI_<Entity> {
  expose ZC_<Entity>      as <Entity>;
  expose ZC_<ChildEntity> as <ChildEntity>;
}

// Service Binding:
// Tipo: OData V4 - UI (para Fiori Elements con Draft)
// Tipo: OData V4 - Web API (para APIs REST consumidas por BTP/CAP)
// Publicar → genera URL: /sap/opu/odata4/...
```

## EML (Entity Manipulation Language) — Ejemplos Basicos

```abap
"-- READ ENTITIES:
READ ENTITIES OF ZI_<Entity>
  ENTITY <Alias>
    FIELDS ( KeyField Field1 Amount Status )
    WITH VALUE #( ( %key-KeyField = '<value>' ) )
  RESULT DATA(lt_result)
  FAILED DATA(lt_failed)
  REPORTED DATA(lt_reported).

"-- MODIFY — CREATE:
MODIFY ENTITIES OF ZI_<Entity>
  ENTITY <Alias>
    CREATE FIELDS ( Field1 Field2 )
      WITH VALUE #( ( %cid       = 'CID_1'
                      Field1     = 'value1'
                      Field2     = 'value2' ) )
  MAPPED   DATA(lt_mapped)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES
  RESPONSE OF ZI_<Entity>
  FAILED   DATA(lt_commit_failed)
  REPORTED DATA(lt_commit_reported).

"-- MODIFY — EXECUTE ACTION:
MODIFY ENTITIES OF ZI_<Entity>
  ENTITY <Alias>
    EXECUTE Approve
      FROM VALUE #( ( %key-KeyField = '<value>' ) )
  RESULT   DATA(lt_result)
  FAILED   DATA(lt_failed)
  REPORTED DATA(lt_reported).
COMMIT ENTITIES.

"-- DEEP INSERT (con composicion hijo):
MODIFY ENTITIES OF ZI_<Entity>
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
BDEF base:            = root entity ZI_   → ZI_PurchaseOrder
BDEF projection:      = root entity ZC_   → ZC_PurchaseOrder
Behavior Pool:        ZBP_I_[Objeto]      → ZBP_I_PurchaseOrder
Service Definition:   ZUI_[Obj]           → ZUI_PurchaseOrder
Service Binding:      ZUI_[Obj]_O4        → ZUI_PurchaseOrder_O4
Tabla persistente:    Z[OBJ] (≤ 16)       → ZPURCHORD
Draft Table:          [tabla persist.]_D  → ZPURCHORD_D
```

> Límites DDIC/BDL: tabla ≤ 16; CDS entity, BDEF, clase ≤ 30. Si no entra, se
> abrevia el objeto, nunca el sufijo `_D`.

## Checklist RAP BO Completo

- [ ] Tabla persistente (si es managed)
- [ ] Draft table (si usa Draft)
- [ ] CDS Interface View con @AccessControl y @ObjectModel
- [ ] CDS Projection View con provider contract
- [ ] Access Control (DCL) para Interface View
- [ ] Metadata Extension (.MDE) con @UI annotations
- [ ] Behavior Definition base (`managed` sobre ZI_) con lock, total etag, authorization
- [ ] Behavior Definition de projection (`projection` sobre ZC_, draft actions con `use`)
- [ ] Behavior Implementation (handler + saver si unmanaged)
- [ ] ABAP Unit Tests (cl_abap_behv_test_environment)
- [ ] Service Definition
- [ ] Service Binding publicado (OData V4)
