# SAPUI5 Core Standards - Reglas Fundamentales

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%
> **FUENTE**: Documentación oficial SAP UI5 MCP Servers

## 1. Gestión de Dependencias y Módulos

### ❌ PROHIBIDO ABSOLUTAMENTE

```javascript
// NUNCA usar variables globales para acceder a framework UI5
var oButton = new sap.m.Button(); // ❌ INCORRECTO
sap.m.MessageToast.show("Hello"); // ❌ INCORRECTO
```

### ✅ OBLIGATORIO

```javascript
// JavaScript: Usar sap.ui.define
sap.ui.define([
    "sap/m/Button",
    "sap/m/MessageToast"
], function (Button, MessageToast) {
    "use strict";
    
    const oButton = new Button(); // ✅ CORRECTO
    MessageToast.show("Hello");   // ✅ CORRECTO
});

// TypeScript: Usar ES6 imports
import Button from "sap/m/Button";
import MessageToast from "sap/m/MessageToast";
import { Button$PressEvent } from "sap/m/Button"; // Para eventos tipados
```

### XML Views - Declaración de Dependencias

```xml
<!-- Para controles, suficiente con XML tag -->
<m:Button text="{i18n>buttonText}" />

<!-- Para APIs programáticas, usar core:require -->
<ObjectListItem
    core:require="{
        Currency: 'sap/ui/model/type/Currency'
    }"
    number="{
        parts: ['invoice>ExtendedPrice', 'view>/currency'],
        type: 'Currency',
        formatOptions: { showMeasure: false }
    }" />
```

## 2. Declaración de Variables (ES6+ Obligatorio)

### ❌ PROHIBIDO

```javascript
var sTitle = "Hello World";        // ❌ NUNCA usar var
var iCount = 0;                    // ❌ Problemas de hoisting
var bVisible = true;               // ❌ Scope issues
```

### ✅ OBLIGATORIO

```javascript
const sTitle = "Hello World";      // ✅ Para valores inmutables
let iCount = 0;                    // ✅ Para variables mutables
const bVisible = true;             // ✅ Scope de bloque
```

**JUSTIFICACIÓN**: Evita problemas de hoisting, mejora legibilidad y previene errores de scope.

## 3. Convenciones de Nomenclatura

### Hungarian Notation (Recomendada)

```javascript
// Prefijos estándar SAP
const sMessage = "Hello";          // s = string
const iIndex = 0;                  // i = integer
const bEnabled = true;             // b = boolean
const aItems = [];                 // a = array
const oModel = new JSONModel();    // o = object
const fCallback = function() {};   // f = function

// Nombres de controles
const oButton = new Button();
const oTable = new Table();
const oDialog = new Dialog();
```

### CamelCase Obligatorio

```javascript
// ✅ CORRECTO
const sUserName = "john.doe";
const bIsVisible = true;
const aSelectedItems = [];

// ❌ INCORRECTO
const user_name = "john.doe";      // snake_case
const IsVisible = true;            // PascalCase para variables
const selected_items = [];         // snake_case
```

## 4. Arquitectura MVC Obligatoria

### Separación Estricta de Responsabilidades

#### Controller - Solo Lógica de Presentación

```javascript
sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/m/MessageToast"
], function (Controller, MessageToast) {
    "use strict";

    return Controller.extend("com.myapp.controller.Main", {
        
        // ✅ CORRECTO: Manejo de eventos UI
        onButtonPress: function(oEvent) {
            const sMessage = this.getView().getModel("i18n")
                .getResourceBundle().getText("buttonPressed");
            MessageToast.show(sMessage);
        },
        
        // ✅ CORRECTO: Navegación
        onNavigateToDetail: function() {
            this.getRouter().navTo("detail");
        },
        
        // ❌ INCORRECTO: Lógica de negocio en controller
        calculateTotalPrice: function(aItems) {
            // Esta lógica debe estar en un modelo o servicio
        }
    });
});
```

#### Model - Gestión de Datos

```javascript
// ✅ CORRECTO: Lógica de datos en modelos
const oModel = new JSONModel({
    items: [],
    totalPrice: 0,
    currency: "EUR"
});

// ✅ CORRECTO: Métodos de cálculo en modelos
oModel.calculateTotal = function() {
    const aItems = this.getProperty("/items");
    const fTotal = aItems.reduce((sum, item) => sum + item.price, 0);
    this.setProperty("/totalPrice", fTotal);
};
```

## 5. Data Binding Obligatorio

### ✅ SIEMPRE usar Data Binding en Views

```xml
<!-- ✅ CORRECTO: Property binding -->
<Button text="{i18n>buttonText}" 
        enabled="{model>/buttonEnabled}" />

<!-- ✅ CORRECTO: Aggregation binding -->
<List items="{model>/items}">
    <StandardListItem title="{model>name}" 
                      description="{model>description}" />
</List>

<!-- ✅ CORRECTO: Expression binding -->
<Text text="{= ${model>/firstName} + ' ' + ${model>/lastName} }" />
```

### ❌ NUNCA manipular UI directamente

```javascript
// ❌ INCORRECTO: Manipulación directa
this.byId("myButton").setText("New Text");
this.byId("myButton").setEnabled(false);

// ✅ CORRECTO: Usar data binding
this.getView().getModel().setProperty("/buttonText", "New Text");
this.getView().getModel().setProperty("/buttonEnabled", false);
```

## 6. `sap.ui.getCore()` — Deprecado en UI5 Moderno

### ❌ PROHIBIDO: `sap.ui.getCore()` (patrón obsoleto)

```javascript
// ❌ DEPRECADO: sap.ui.getCore() está deprecado en UI5 >= 1.118
sap.ui.getCore().attachInit(function() { ... });
sap.ui.getCore().byId("myControl");
sap.ui.getCore().getModel("myModel");
```

### ✅ OBLIGATORIO: Importar `Core` como módulo

```javascript
// ✅ CORRECTO: Importar Core directamente
sap.ui.define([
    "sap/ui/core/Core"
], function(Core) {
    "use strict";

    // El import devuelve el singleton directamente
    Core.byId("myControl");       // ✅ Equivalente a sap.ui.getCore().byId()
    Core.getModel("myModel");     // ✅ Equivalente a sap.ui.getCore().getModel()
    Core.ready().then(function() { // ✅ Equivalente a attachInit
        // App inicializada
    });
});
```

```typescript
// TypeScript
import Core from "sap/ui/core/Core";

Core.ready().then(() => {
    // App lista
});
```

### Tabla de equivalencias

| Patrón deprecado | Patrón moderno |
|---|---|
| `sap.ui.getCore().attachInit(fn)` | `Core.ready().then(fn)` |
| `sap.ui.getCore().byId(id)` | `Core.byId(id)` |
| `sap.ui.getCore().getModel(name)` | `Core.getModel(name)` |
| `sap.ui.getCore().getConfiguration()` | `Core.getConfiguration()` |

## 7. TypeScript Avanzado — Patrones Oficiales

### Casting correcto de métodos UI5

```typescript
import Controller from "sap/ui/core/mvc/Controller";
import JSONModel from "sap/ui/model/json/JSONModel";
import ODataModel from "sap/ui/model/odata/v4/ODataModel";
import Button from "sap/m/Button";
import UIComponent from "sap/ui/core/UIComponent";

export default class MainController extends Controller {

    // ✅ CORRECTO: Cast explícito de byId()
    public onInit(): void {
        const oButton = this.byId("myButton") as Button;
        oButton.setEnabled(false);
    }

    // ✅ CORRECTO: Cast de getModel()
    public getViewModel(): JSONModel {
        return this.getView()!.getModel("view") as JSONModel;
    }

    // ✅ CORRECTO: Cast de getOwnerComponent()
    public getAppComponent(): UIComponent {
        return this.getOwnerComponent() as UIComponent;
    }
}
```

### Controles Custom — MetadataOptions y Renderer seguro

```typescript
// ✅ CORRECTO: Renderer con apiVersion: 2 (protección XSS obligatoria)
import RenderManager from "sap/ui/core/RenderManager";
import MyControl from "./MyControl";

const MyControlRenderer = {
    apiVersion: 2,  // ✅ OBLIGATORIO: apiVersion 2 activa renderizado seguro

    render(oRm: RenderManager, oControl: MyControl): void {
        oRm.openStart("div", oControl);
        oRm.class("myControlClass");
        oRm.openEnd();
        oRm.text(oControl.getText()); // Encoding automático — protección XSS
        oRm.close("div");
    }
};

export default MyControlRenderer;
```

### Imports dinámicos: `sap.ui.require` → Promise

```typescript
// ❌ ANTIGUO: sap.ui.require con callback
sap.ui.require(["sap/m/Dialog"], function(Dialog) {
    new Dialog({ ... }).open();
});

// ✅ MODERNO: import() dinámico (UI5 >= 1.120)
const { default: Dialog } = await import("sap/m/Dialog");
new Dialog({ ... }).open();

// ✅ ALTERNATIVA compatible: Promise wrapper
const loadDialog = (): Promise<typeof import("sap/m/Dialog")> =>
    new Promise((resolve) => sap.ui.require(["sap/m/Dialog"], resolve));
```

## 8. Manejo de Eventos en TypeScript

### UI5 >= 1.115.0 (Tipado Específico)

```typescript
import { Button$PressEvent } from "sap/m/Button";
import { Table$RowSelectionChangeEvent } from "sap/ui/table/Table";

export default class MainController extends Controller {
    
    // ✅ CORRECTO: Evento tipado específico
    public onButtonPress(oEvent: Button$PressEvent): void {
        const sText = oEvent.getParameter("text");
        // TypeScript conoce los parámetros disponibles
    }
    
    public onRowSelectionChange(oEvent: Table$RowSelectionChangeEvent): void {
        const oContext = oEvent.getParameter("rowContext");
        // Autocompletado y validación de tipos
    }
}
```

### UI5 < 1.115.0 (Fallback)

```typescript
import Event from "sap/ui/base/Event";

export default class MainController extends Controller {
    
    // ✅ CORRECTO: Tipo genérico para versiones anteriores
    public onButtonPress(oEvent: Event): void {
        // Usar tipo genérico cuando tipos específicos no están disponibles
    }
}
```

## 9. Inicialización de Aplicaciones

### ✅ OBLIGATORIO: ComponentSupport

```html
<!-- index.html -->
<script id="sap-ui-bootstrap"
    src="resources/sap-ui-core.js"
    data-sap-ui-on-init="module:sap/ui/core/ComponentSupport"
    data-sap-ui-async="true"
    data-sap-ui-resource-roots='{ "com.myapp": "./" }'
    data-sap-ui-theme="sap_horizon">
</script>
```

### ❌ PROHIBIDO: Inline Scripts

```html
<!-- ❌ NUNCA usar scripts inline -->
<script>
    sap.ui.getCore().attachInit(function() {
        // Viola CSP y mejores prácticas
    });
</script>
```

---

## Herramientas de Validación

### UI5 Linter (Obligatorio)

```bash
# Ejecutar antes de cada commit
npx @ui5/linter --fix
```

### Verificación con MCP Tools

- Usar `get_api_reference` para consultar APIs
- Usar `run_ui5_linter` para validación automática
- Usar `get_project_info` para verificar configuración

---

**RECUERDA**: Estas reglas son OBLIGATORIAS para garantizar calidad, mantenibilidad y compatibilidad en todas las aplicaciones SAPUI5 FreeStyle.
