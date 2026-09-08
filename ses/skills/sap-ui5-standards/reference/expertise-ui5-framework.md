# Framework SAPUI5, patrones freestyle y Building Blocks

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## SAPUI5 Framework

- MVC: Component, View (XML/JSON/JS), Controller, Router
- Data Binding: Property, Element, List, Expression Binding
- OData V2 Model (sap.ui.model.odata.v2.ODataModel): read, create, update, remove, callFunction, batch
- OData V4 Model (sap.ui.model.odata.v4.ODataModel): bindings, auto-refresh, side effects, actions
- JSONModel, ResourceModel (i18n), DeviceModel
- Routing: Router, Route, Target — navegación con y sin hash
- Fragments: Dialog, Popover, ActionSheet (sap.ui.core.Fragment.load)
- Custom Controls: extend de sap.ui.core.Control
- Formatters y Types (sap.ui.model.type.*)
- Librerías: sap.m, sap.f, sap.ui.layout, sap.ui.table, sap.ui.comp, sap.viz, sap.ushell
- MessageManager: usar `sap/ui/core/Messaging` (el acceso vía `sap.ui.getCore().getMessageManager()` está **deprecado** desde 1.118 — verificar con UI5 Linter)
- Busy indicators: BusyDialog, setBusy() en vista/control
- Theming: SAP Horizon (por defecto S/4HANA 2023+), Quartz, Belize
- **Versión del framework**: fijar versión LTS explícita en `manifest.json` (LTS vigente **1.136**; mínimo soportado ~1.120) — NUNCA `latest`; validar con `mcp__sap_ui5__get_version_info` (ver `rules/SAPUI5-CAP-Integration.md`)
- **TypeScript-first** en proyectos nuevos: tipos UI5 (`@sapui5/types`), controllers/formatters en `.ts`, build con UI5 Tooling — ver `mcp__sap_ui5__get_typescript_conversion_guidelines`
- **UI5 Tooling v3** (`@ui5/cli`): build/serve/test; **UI5 Linter** como gate de APIs deprecadas antes de entregar

## SAPUI5 Freestyle — Patrones Completos

### Controller con OData V4

```javascript
sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/m/MessageToast",
  "sap/m/MessageBox"
], function(Controller, Filter, FilterOperator, MessageToast, MessageBox) {
  "use strict";

  return Controller.extend("my.app.controller.OrderList", {

    onInit: function() {
      this._oRouter = this.getOwnerComponent().getRouter();
      this._oRouter.getRoute("orderList").attachPatternMatched(this._onRouteMatched, this);
    },

    _onRouteMatched: function() {
      this._loadOrders();
    },

    _loadOrders: function() {
      const oView  = this.getView();
      const oModel = oView.getModel();       // OData V4 model from manifest

      oView.setBusy(true);
      oModel.bindList("/Orders", null, [], [
        new Filter("status", FilterOperator.NE, "X")
      ]).requestContexts().then(aContexts => {
        const aData = aContexts.map(oCtx => oCtx.getObject());
        oView.getModel("view").setProperty("/orders", aData);
      }).catch(oError => {
        MessageBox.error(oError.message || this._i18n("errorLoad"));
      }).finally(() => oView.setBusy(false));
    },

    onApprove: function(oEvent) {
      const oContext = oEvent.getSource().getBindingContext();
      oContext.getModel().bindContext(
        "OrderService.approve(...)",
        oContext
      ).execute().then(() => {
        MessageToast.show(this._i18n("msgApproved"));
        oContext.refresh();
      }).catch(oError => {
        MessageBox.error(oError.message);
      });
    },

    onSearch: function(oEvent) {
      const sQuery  = oEvent.getParameter("query");
      const oList   = this.byId("orderList");
      const oBinding = oList.getBinding("items");
      const aFilters = sQuery
        ? [new Filter({ filters: [
            new Filter("orderNo", FilterOperator.Contains, sQuery),
            new Filter("soldToParty", FilterOperator.Contains, sQuery)
          ], and: false })]
        : [];
      oBinding.filter(aFilters);
    },

    onNavToDetail: function(oEvent) {
      const sOrderNo = oEvent.getSource().getBindingContext().getProperty("orderNo");
      this._oRouter.navTo("orderDetail", { orderNo: encodeURIComponent(sOrderNo) });
    },

    onOpenDialog: function() {
      if (!this._oDialog) {
        sap.ui.core.Fragment.load({
          id:         this.getView().getId(),
          name:       "my.app.view.fragments.CreateOrder",
          controller: this
        }).then(oDialog => {
          this._oDialog = oDialog;
          this.getView().addDependent(oDialog);
          oDialog.open();
        });
      } else {
        this._oDialog.open();
      }
    },

    _i18n: function(sKey) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey);
    }
  });
});
```

### View XML con SmartControls y Fiori Patterns

```xml
<!-- view/OrderList.view.xml -->
<mvc:View controllerName="my.app.controller.OrderList"
          xmlns:mvc="sap.ui.core.mvc"
          xmlns="sap.m"
          xmlns:f="sap.f"
          xmlns:semantic="sap.f.semantic"
          displayBlock="true">

  <semantic:SemanticPage id="orderPage" headerPinnable="false" toggleHeaderOnTitleClick="true">

    <semantic:titleHeading>
      <Title text="{i18n>titleOrderList}" />
    </semantic:titleHeading>

    <semantic:headerContent>
      <ObjectNumber number="{view>/totalCount}"
                    unit="{i18n>orders}" emphasized="true" />
    </semantic:headerContent>

    <semantic:sendEmailAction>
      <semantic:SendEmailAction press=".onSendEmail" />
    </semantic:sendEmailAction>

    <semantic:content>
      <SearchField placeholder="{i18n>searchOrders}" search=".onSearch" width="100%" />
      <List id="orderList"
            items="{/Orders}"
            growing="true"
            growingThreshold="25"
            mode="SingleSelectMaster"
            selectionChange=".onNavToDetail">
        <ObjectListItem
          title="{orderNo}"
          number="{parts: ['totalAmount','currency'],
                   type: 'sap.ui.model.type.Currency',
                   formatOptions: {showMeasure: false}}"
          numberUnit="{currency}"
          numberState="{= ${status} === 'A' ? 'Success' : ${status} === 'R' ? 'Error' : 'None'}">
          <attributes>
            <ObjectAttribute text="{soldToParty}" />
            <ObjectAttribute text="{
              path: 'createdAt',
              type: 'sap.ui.model.type.DateTime',
              formatOptions: { style: 'medium' }
            }" />
          </attributes>
          <firstStatus>
            <ObjectStatus text="{status}" state="{= ${status} === 'A' ? 'Success' : 'Warning'}" />
          </firstStatus>
        </ObjectListItem>
      </List>
    </semantic:content>

  </semantic:SemanticPage>
</mvc:View>
```

## Building Blocks (OData V4 — SAPUI5 1.99+)

Los Building Blocks son macros XML que permiten componer páginas Custom Page con piezas reutilizables de Fiori Elements, sin escribir controles SAPUI5 desde cero.

**Disponibles:**

| Building Block | Tag XML | Cuándo usarlo |
| --- | --- | --- |
| Table | `<macros:Table>` | Tabla de entidades con sorting, filtering, personalización |
| Chart | `<macros:Chart>` | Gráfico OData analítico (requiere `@Aggregation` annotations) |
| Filter Bar | `<macros:FilterBar>` | Barra de filtros conectada a Table o Chart |
| Page | `<macros:Page>` | Contenedor de página con header y secciones |
| Rich Text Editor | `<macros:RichTextEditor>` | Edición de texto enriquecido en formularios |

**Dependencia obligatoria en manifest.json para Building Blocks:**

```json
{
  "sap.ui5": {
    "dependencies": {
      "libs": {
        "sap.fe.macros": {}
      }
    }
  }
}
```

> ⚠️ **CRÍTICO**: Sin `sap.fe.macros` en las dependencias, los Building Blocks (`<macros:Table>`, `<macros:FilterBar>`, etc.) no cargan y la app falla en runtime sin mensaje de error claro.

**Ejemplo — Custom Page con Table + FilterBar:**

```xml
<!-- ext/customPage/CustomPage.view.xml -->
<mvc:View xmlns:mvc="sap.ui.core.mvc"
          xmlns:macros="sap.fe.macros"
          controllerName="my.app.ext.customPage.CustomPage">
  <macros:FilterBar id="FilterBar"
                    metaPath="/SalesOrder/@com.sap.vocabularies.UI.v1.SelectionFields"
                    search=".onSearch" />
  <macros:Table id="LineItemTable"
                metaPath="/SalesOrder/@com.sap.vocabularies.UI.v1.LineItem"
                filterBar="FilterBar"
                readOnly="false" />
</mvc:View>
```

**Building Block Chart — OData V2 vs OData V4 (diferencia crítica):**

- **OData V2**: El servidor infiere las agregaciones automáticamente al recibir el request.
- **OData V4**: El **cliente DEBE** pasar explícitamente dimensiones/medidas en el request. El backend necesita soporte de `@Aggregation.ApplySupported` en las annotations.

```abap
"-- Annotation requerida en CDS para Charts con OData V4:
@Aggregation.applySupported: {
  transformations:          [ #AGGREGATE, #TOP_LEVEL_HIERARCHY ],
  rollUpSpecification:      [ #SIMPLE ],
  groupByProperties:        [ 'Status', 'OrderType' ],
  aggreGatableProperties:   [{ property.name: 'NetAmount' }]
}
```

**Semantic Date Operators en FilterBar:**
El filter bar soporta operadores de fecha semánticos (TODAY, TOMORROW, LASTWEEK, THISMONTH, etc.) automáticamente cuando el campo tiene tipo de fecha en el metadata OData. No requiere configuración adicional; se activan si el campo tiene `@UI.selectionField` y tipo `Edm.Date` o `Edm.DateTimeOffset`.

**Cuándo usar Building Blocks vs Freestyle:**

- Building Blocks: UX custom dentro del shell Fiori Elements, con OData V4 y annotations
- Freestyle: UX completamente distinta al estándar Fiori, o integración con librerías externas

**LongRunners Group Pattern — Optimización de Carga:**
Para mejorar UX cuando algunos requests OData V4 son lentos, diferirlos a un grupo separado que no bloquea el render inicial:

```javascript
// En manifest.json — definir grupo de carga diferida
"models": {
  "": {
    "dataSource": "mainService",
    "settings": {
      "groupId": "$auto",
      "updateGroupId": "$auto"
    }
  }
}

// En controller — cambiar parámetros del binding para requests lentos
const oBinding = this.byId("slowTable").getBinding("items");
oBinding.changeParameters({
  "$$groupId": "longRunners"    // Grupo diferido — no bloquea render
});
// Disparar manualmente cuando sea oportuno:
oModel.submitBatch("longRunners");
```
