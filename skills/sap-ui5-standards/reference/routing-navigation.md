# SAPUI5 Routing & Navigation - Reglas de Enrutamiento

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%

## 1. Configuración Obligatoria en manifest.json

```json
{
  "sap.ui5": {
    "routing": {
      "config": {
        "routerClass": "sap.m.routing.Router",
        "type": "View",
        "viewType": "XML",
        "path": "com.myapp.view",
        "controlId": "app",
        "controlAggregation": "pages",
        "transition": "slide",
        "async": true
      },
      "routes": [
        { "pattern": "",                  "name": "main",   "target": "main" },
        { "pattern": "detail/{objectId}", "name": "detail", "target": "detail" }
      ],
      "targets": {
        "main":     { "id": "main",     "name": "Main" },
        "detail":   { "id": "detail",   "name": "Detail" },
        "notFound": { "id": "notFound", "name": "NotFound" }
      }
    }
  }
}
```

**Reglas críticas:** `async: true` SIEMPRE. `routerClass: "sap.m.routing.Router"` para apps móviles.

## 2. BaseController — Patrón Obligatorio

```javascript
// controller/BaseController.js — extender en TODOS los controllers
sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/core/routing/History"
], function(Controller, History) {
    "use strict";

    return Controller.extend("com.myapp.controller.BaseController", {

        getRouter: function() {
            return this.getOwnerComponent().getRouter();
        },

        navTo: function(sRouteName, oParameters, bReplace) {
            this.getRouter().navTo(sRouteName, oParameters, bReplace);
        },

        onNavBack: function(sFallbackRoute, oFallbackParameters) {
            const sPreviousHash = History.getInstance().getPreviousHash();
            if (sPreviousHash !== undefined) {
                window.history.go(-1);
            } else {
                this.navTo(sFallbackRoute || "main", oFallbackParameters, true);
            }
        }
    });
});
```

```javascript
// Component.js — inicializar router SIEMPRE en init()
init: function() {
    UIComponent.prototype.init.apply(this, arguments);
    this.getRouter().initialize();  // ✅ OBLIGATORIO
}
```

## 3. Manejo de Parámetros de Ruta

```javascript
// controller/Detail.controller.js
onInit: function() {
    this.getRouter().getRoute("detail").attachPatternMatched(this._onObjectMatched, this);
},

_onObjectMatched: function(oEvent) {
    const sObjectId = oEvent.getParameter("arguments").objectId;

    // ✅ OBLIGATORIO: Validar parámetros antes de bindear
    if (!sObjectId) {
        this.navTo("main");
        return;
    }

    const sDecodedId = decodeURIComponent(sObjectId);  // ✅ Decodificar
    this._bindView(sDecodedId);
},

_bindView: function(sObjectId) {
    this.getView().bindElement({
        path: this.getModel().createKey("/Objects", { ID: sObjectId }),
        events: {
            dataRequested: () => this.getView().setBusy(true),
            dataReceived:  () => this.getView().setBusy(false)
        }
    });
}
```

## 4. Error Handling de Routing

```javascript
// Component init o App.controller.js
this.getRouter().attachBypassed(function(oEvent) {
    const sHash = oEvent.getParameter("hash");
    MessageBox.information(
        this.getResourceBundle().getText("routeNotFound", [sHash]),
        { onClose: () => this.navTo("main") }
    );
}, this);
```

## ❌ ANTI-PATRÓN: `viewPath` deprecado en manifest v2

**NUNCA usar `viewPath` en `routing.config` ni en targets.** Este campo está deprecado desde manifest v2 y causa `LaunchpadError` en FLP:

```text
LaunchpadError: sap.ui5/routing/targets/viewPath is deprecated and not supported
with manifest version 2. Use the option 'path' instead.
```

```json
// ❌ MAL — genera LaunchpadError en FLP
"routing": {
  "config": {
    "path": "com.myapp.view",
    "viewPath": "com.myapp.view"   // ← ELIMINAR SIEMPRE
  }
}

// ✅ CORRECTO — solo "path"
"routing": {
  "config": {
    "path": "com.myapp.view"
  }
}
```

> El generador `@sap/generator-fiori:basic` puede incluir ambas claves simultáneamente. Al hacer scaffold, **verificar y eliminar `viewPath` antes de hacer deploy**.

## Checklist

- [ ] `async: true` en config de routing
- [ ] `path` usado en routing.config — **`viewPath` ausente** (verificar tras scaffold)
- [ ] BaseController implementado y extendido en todos los controllers
- [ ] `this.getRouter().initialize()` en Component.init()
- [ ] Parámetros de ruta validados antes de bindear vista
- [ ] Parámetros URL codificados con `encodeURIComponent` / decodificados con `decodeURIComponent`
- [ ] Ruta `notFound` configurada en targets
