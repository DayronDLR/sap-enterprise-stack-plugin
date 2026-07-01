# Core Standards — SAPUI5 FreeStyle

## Module Imports — Never Global Access

```typescript
// ❌ NEVER — global namespace access
const oBtn = new sap.m.Button();
sap.m.MessageToast.show("Hello");

// ✅ ALWAYS — ES6 imports
import Button from "sap/m/Button";
import MessageToast from "sap/m/MessageToast";
const oBtn = new Button();
```

```xml
<!-- XML Views: use core:require for programmatic APIs -->
<mvc:View
    xmlns:core="sap.ui.core"
    core:require="{ Formatter: 'com/myapp/model/formatter' }">
    <Text text="{path: 'status', formatter: 'Formatter.statusState'}"/>
</mvc:View>
```

## Variables — ES6+ Mandatory

```typescript
// ❌ NEVER
var sTitle = "Hello";

// ✅ ALWAYS
const sTitle = "Hello";   // immutable
let iCount = 0;           // mutable
```

**Hungarian notation:**

- `s` = string, `i` = integer, `b` = boolean, `a` = array, `o` = object, `f` = function

## sap.ui.getCore() — Deprecated

```typescript
// ❌ DEPRECATED (UI5 >= 1.118)
sap.ui.getCore().attachInit(fn);
sap.ui.getCore().byId("id");

// ✅ MODERN
import Core from "sap/ui/core/Core";
Core.ready().then(fn);
Core.byId("id");
```

## Data Binding — Never Direct UI Manipulation

```typescript
// ❌ NEVER — direct DOM manipulation
this.byId("myButton").setText("New Text");
this.byId("myButton").setEnabled(false);

// ✅ ALWAYS — via model
this.getView()!.getModel()!.setProperty("/buttonText", "New Text");
this.getView()!.getModel()!.setProperty("/buttonEnabled", false);
```

## BaseController — Always Create

```typescript
// controller/BaseController.ts
import Controller from "sap/ui/core/mvc/Controller";
import History from "sap/ui/core/routing/History";
import UIComponent from "sap/ui/core/UIComponent";
import ResourceBundle from "sap/base/i18n/ResourceBundle";
import ResourceModel from "sap/ui/model/resource/ResourceModel";
import Router from "sap/m/routing/Router";

export default class BaseController extends Controller {

    public getRouter(): Router {
        return (this.getOwnerComponent() as UIComponent).getRouter();
    }

    public getResourceBundle(): ResourceBundle {
        const oModel = this.getOwnerComponent()!.getModel("i18n") as ResourceModel;
        return oModel.getResourceBundle() as ResourceBundle;
    }

    public navTo(sRoute: string, oParams?: object, bReplace?: boolean): void {
        this.getRouter().navTo(sRoute, oParams, bReplace);
    }

    public onNavBack(): void {
        const sPreviousHash = History.getInstance().getPreviousHash();
        if (sPreviousHash !== undefined) {
            window.history.go(-1);
        } else {
            this.getRouter().navTo("main", {}, true);
        }
    }
}
```

## Component.ts — Router Init Mandatory

```typescript
import UIComponent from "sap/ui/core/UIComponent";
import models from "./model/models";

export default class Component extends UIComponent {

    public static metadata = {
        manifest: "json"
    };

    public init(): void {
        super.init();
        this.setModel(models.createDeviceModel(), "device");
        this.getRouter().initialize(); // ← MANDATORY
    }
}
```

## App Initialization — ComponentSupport (CSP-compliant)

```html
<!-- index.html — NEVER use inline scripts -->
<script id="sap-ui-bootstrap"
    src="resources/sap-ui-core.js"
    data-sap-ui-on-init="module:sap/ui/core/ComponentSupport"
    data-sap-ui-async="true"
    data-sap-ui-theme="sap_horizon"
    data-sap-ui-resource-roots='{"com.myapp": "./"}'>
</script>
<body class="sapUiBody">
    <div data-sap-ui-component
         data-name="com.myapp"
         data-id="container"
         data-settings='{"id": "myapp"}'>
    </div>
</body>
```

## TypeScript — Correct Casting

```typescript
import JSONModel from "sap/ui/model/json/JSONModel";
import Button from "sap/m/Button";
import { Button$PressEvent } from "sap/m/Button"; // UI5 >= 1.115

export default class MainController extends BaseController {

    public onInit(): void {
        const oButton = this.byId("saveBtn") as Button;
        oButton.setEnabled(false);
    }

    public getViewModel(): JSONModel {
        return this.getView()!.getModel("view") as JSONModel;
    }

    // Typed event (UI5 >= 1.115)
    public onSavePress(oEvent: Button$PressEvent): void {
        // oEvent is fully typed
    }
}
```
