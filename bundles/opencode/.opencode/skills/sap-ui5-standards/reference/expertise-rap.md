# RAP desde el lado Fiori

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## El modelo RAP no se duplica acá

El modelo completo y verificado —CDS root/composition, BDEF base `managed` sobre
`ZI_` con draft, BDEF `projection` sobre `ZC_`, behavior pool, EML, naming y límites
de nombre— está en **`sap-abap-standards/reference/rap-shared.md`** (plantillas) y
**`sap-abap-standards/reference/rap.md`** (ejemplo completo). El RAP de fondo lo
diseña `/sap-abap`; el agente Fiori consume el servicio.

Lo que el agente Fiori tiene que verificar del lado del servicio antes de generar
la app:

| Pieza | Qué tiene que tener para Fiori Elements |
| --- | --- |
| CDS root (`ZI_`) | `define root view entity` sobre una tabla **Z propia** (nunca `vbak` u otra tabla estándar: Clean Core), con `composition` a los hijos |
| Projection (`ZC_`) | `provider contract transactional_query`, `@Metadata.allowExtensions: true` y los hijos `redirected to composition child` |
| BDEF base | `managed` **sobre `ZI_`**, nunca sobre la projection; con draft: `total etag`, las draft actions y `association … { create; with draft; }` |
| BDEF projection | `projection; strict ( 2 ); use draft;` y `use action` de cada draft action y acción propia |
| Metadata Extension (`ZC_….ddlx`) | `@UI.lineItem`, `@UI.selectionField`, `@UI.facet`, `@UI.identification` (botones de acción) |
| Draft table | `[tabla persistente]_D`, ≤ 16 caracteres |

### Service Definition y Binding

```abap
// Service Definition
@EndUserText.label: 'Sales Order Service'
define service ZUI_SalesOrder {
  expose ZC_SalesOrder as SalesOrder;
  expose ZC_SalesOrderItem as SalesOrderItem;
}

// Service Binding: tipo UI_V4_UI (OData V4 para Fiori Elements)
// Nombre: ZUI_SALESORDER_O4
// Binding Type: OData V4 - UI
// URL: /sap/opu/odata4/sap/zui_salesorder_o4/srvd/sap/zui_salesorder/0001/
```
