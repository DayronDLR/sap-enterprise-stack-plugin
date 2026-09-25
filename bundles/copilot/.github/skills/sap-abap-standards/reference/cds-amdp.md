# CDS Views, AMDP y Access Control (DCL)

> Material de referencia del agente ABAP. Se lee bajo demanda.

## CDS Views (Core Data Services)

```abap
"-- CDS Base View (Interface View):
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory: #M,
  dataClass: #TRANSACTIONAL
}
define view entity ZI_PurchaseOrder
  as select from ekko as header
  association [0..1] to ekpo as _item on $projection.PurchaseOrder = _item.ebeln
  association [0..1] to lfa1 as _Vendor  on $projection.Vendor = _Vendor.lifnr
{
  key header.ebeln          as PurchaseOrder,
      header.lifnr          as Vendor,
      header.bedat          as DocumentDate,
      header.bukrs          as CompanyCode,
      header.waers          as Currency,
      @Semantics.amount.currencyCode: 'Currency'
      header.netwr          as NetAmount,
      header.ernam          as CreatedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      header.aedat          as LastChangedDate,
      -- Associations expuestas
      _item,
      _Vendor
}

"-- CDS Projection View (Consumption View para RAP/OData):
@EndUserText.label: 'Purchase Order'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define root view entity ZC_PurchaseOrder
  provider contract transactional_query
  as projection on ZI_PurchaseOrder
{
  key PurchaseOrder,
      Vendor,
      DocumentDate,
      CompanyCode,
      Currency,
      NetAmount,
      CreatedBy,
      LastChangedDate,
      _item : redirected to composition child ZC_PurchaseOrderItem,
      _Vendor
}

"-- CDS con @Analytics para HANA / embedded analytics:
@Analytics.dataCategory: #FACT
@Analytics.dataExtraction.enabled: true
define view entity ZA_PurchaseOrderFact
  as select from ZI_PurchaseOrder
{
  @AnalyticsDetails.query.axis: #ROWS
  PurchaseOrder,
  CompanyCode,
  @AnalyticsDetails.query.axis: #COLUMNS
  @Aggregation.default: #SUM
  NetAmount,
  Currency
}
```

## AMDP (ABAP Managed Database Procedures)

```abap
CLASS zcl_po_analytics DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_amdp_marker_hdb.
    CLASS-METHODS get_po_summary
      IMPORTING
        VALUE(iv_bukrs) TYPE bukrs
      EXPORTING
        VALUE(et_result) TYPE STANDARD TABLE OF zs_po_summary
      RAISING cx_amdp_error.
ENDCLASS.

CLASS zcl_po_analytics IMPLEMENTATION.
  METHOD get_po_summary BY DATABASE PROCEDURE
        FOR HDB LANGUAGE SQLSCRIPT
        OPTIONS READ-ONLY
        USING ekko ekpo.
    et_result = SELECT
      h.bukrs    AS company_code,
      h.lifnr    AS vendor,
      SUM(h.netwr) AS total_amount,
      COUNT(*)     AS doc_count
    FROM ekko AS h
    WHERE h.bukrs = :iv_bukrs
      AND h.loekz = ''
    GROUP BY h.bukrs, h.lifnr
    ORDER BY total_amount DESC;
  ENDMETHOD.
ENDCLASS.
```

## Access Control (CDS DCL)

```abap
"-- Access Control para CDS View:
@EndUserText.label: 'PO Access Control'
@MappingRole: true
define role ZI_PurchaseOrder {
  grant select on ZI_PurchaseOrder
    where ( CompanyCode ) = aspect pfcg_auth( M_BEST_BSA, BUKRS, ACTVT = '03' );
}
```
