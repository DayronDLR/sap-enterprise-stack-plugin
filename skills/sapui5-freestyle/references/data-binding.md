# Data Binding & Formatters — SAPUI5 FreeStyle

## Type Hierarchy — Always Follow This Order

### 1st Choice: OData Types (for OData services)

```xml
<!-- Numbers with grouping -->
<Text text="{
    path: 'price',
    type: 'sap.ui.model.odata.type.Decimal',
    formatOptions: { groupingEnabled: true, minFractionDigits: 2 }
}"/>

<!-- Currency -->
<Text text="{
    parts: ['amount', 'currency'],
    type: 'sap.ui.model.odata.type.Currency'
}"/>

<!-- Dates -->
<Text text="{
    path: 'createdAt',
    type: 'sap.ui.model.odata.type.DateTime',
    formatOptions: { style: 'medium' }
}"/>
```

Common OData types: `Decimal`, `DateTime`, `Currency`, `Unit`, `String`, `Boolean`, `Int32`

### 2nd Choice: Standard Types (for JSON models)

```xml
<Input value="{
    path: '/quantity',
    type: 'sap.ui.model.type.Integer',
    constraints: { minimum: 0, maximum: 9999 }
}"/>
```

### Last Resort: Custom Formatter (unique presentation logic only)

```xml
<ObjectStatus
    state="{path: 'status', formatter: 'Formatter.statusState'}"
    text="{path: 'status', formatter: 'Formatter.statusText'}"/>
```

## Formatters — All in webapp/model/formatter.ts

```typescript
// webapp/model/formatter.ts — ONLY location for formatters
const Formatter = {
    // ✅ function expression — 'this' available if needed
    statusState: function(sStatus: string): string {
        const mMap: Record<string, string> = {
            "PENDING":  "Warning",
            "APPROVED": "Success",
            "REJECTED": "Error"
        };
        return mMap[sStatus] || "None";
    },

    statusText: function(sStatus: string): string {
        if (!sStatus) return "";
        // Use i18n via controller context when using dot notation
        return sStatus.charAt(0).toUpperCase() + sStatus.slice(1).toLowerCase();
    },

    // ✅ arrow function only for pure transforms (no 'this' needed)
    toUpperCase: (sValue: string): string => sValue ? sValue.toUpperCase() : ""
};

export default Formatter;
```

### Using formatter in XML View

```xml
<!-- Modern: core:require (preferred) -->
<mvc:View xmlns:core="sap.ui.core"
          core:require="{ Formatter: 'com/myapp/model/formatter' }">
    <ObjectStatus state="{path: 'status', formatter: 'Formatter.statusState'}"/>
</mvc:View>

<!-- Traditional: dot notation via controller -->
<ObjectStatus state="{path: 'status', formatter: '.formatter.statusState'}"/>
```

For dot notation, attach formatter to controller:

```typescript
import Formatter from "../model/formatter";
export default class MainController extends BaseController {
    public formatter = Formatter;
}
```

## ❌ Forbidden Formatter Patterns

```typescript
// ❌ Business logic in formatters
calculateTotal: (price: number, qty: number) => price * qty // → use model

// ❌ Side effects
countCalls: function(v: string) { this.counter++; return v; }

// ❌ Async operations
fetchLabel: async (id: string) => await fetch(`/api/${id}`) // → never

// ❌ Inline formatters in XML
// <Text text="{= ${status} === 'A' ? 'Active' : 'Inactive' }"/> for complex logic
```

## OData V4 Model Setup (manifest.json)

```json
{
  "sap.app": {
    "dataSources": {
      "mainService": {
        "uri": "/odata/v4/MyService/",
        "type": "OData",
        "settings": { "odataVersion": "4.0" }
      }
    }
  },
  "sap.ui5": {
    "models": {
      "": {
        "dataSource": "mainService",
        "settings": {
          "synchronizationMode": "None",
          "operationMode": "Server",
          "autoExpandSelect": true
        }
      }
    }
  }
}
```

## OData V4 Binding Patterns

```typescript
// List binding
const oList = this.byId("table") as Table;
const oBinding = oList.getBinding("items") as ListBinding;
oBinding.filter([new Filter("Status", FilterOperator.EQ, "PENDING")]);

// Context binding (detail view)
this.getView()!.bindElement({
    path: `/Orders(${sOrderId})`,
    events: {
        dataRequested: () => this.getView()!.setBusy(true),
        dataReceived: () => this.getView()!.setBusy(false)
    }
});

// Property update (V4 — no submitChanges)
const oContext = oItem.getBindingContext() as Context;
await oContext.setProperty("Status", "APPROVED");

// Batch submit (V4)
const oModel = this.getView()!.getModel() as ODataModel;
await oModel.submitBatch("myUpdateGroup");
```

## JSONModel — Local State

```typescript
import JSONModel from "sap/ui/model/json/JSONModel";

// In onInit
const oViewModel = new JSONModel({
    busy: false,
    items: [],
    selectedCount: 0,
    currency: "ARS"
});
this.getView()!.setModel(oViewModel, "view");

// Usage in XML
// <Button enabled="{= !${view>/busy} }"/>
// <List items="{view>/items}">
```
