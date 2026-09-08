# SAPUI5 Security & Performance - Reglas de Seguridad y Rendimiento

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%

## 1. Content Security Policy (CSP)

```html
<!-- ✅ CSP header recomendado -->
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self'; script-src 'self' 'unsafe-eval';
               style-src 'self' 'unsafe-inline'; img-src 'self' data:;">
```

```html
<!-- ❌ PROHIBIDO: scripts inline (viola CSP) -->
<script>sap.ui.getCore().attachInit(function() { /* ... */ });</script>

<!-- ❌ PROHIBIDO: eval() -->
<script>eval("var x = 1;");</script>

<!-- ❌ PROHIBIDO: estilos inline -->
<div style="background-color: red;">...</div>
```

```javascript
// ✅ OBLIGATORIO: Inicialización via ComponentSupport (CSP-compliant)
// En index.html: data-sap-ui-on-init="module:sap/ui/core/ComponentSupport"
```

## 2. Prevención XSS

```javascript
// ❌ PROHIBIDO: inserción directa de HTML
this.byId("myDiv").getDomRef().innerHTML = sUserInput;
$("#myDiv").html(sUserInput);
document.write(sUserInput);

// ✅ CORRECTO: Controles UI5 encodean automáticamente
const oText = new Text({ text: sUserInput });

// ✅ CORRECTO: Encoding manual cuando sea necesario
sap.ui.define(["sap/base/security/encodeHTML"], function(encodeHTML) {
    const sSafeHTML = encodeHTML(sUserInput);
});
```

### Validación de Entrada

```javascript
sap.ui.define(["sap/base/security/sanitizeHTML"], function(sanitizeHTML) {
    onInputChange: function(oEvent) {
        const sValue = oEvent.getParameter("value");
        if (!/^[a-zA-Z0-9\s]+$/.test(sValue)) {
            this.showError("Formato inválido");
            return;
        }
        this.getModel().setProperty("/userInput", sanitizeHTML(sValue));
    }
});
```

## 3. Datos Sensibles

```javascript
// ✅ OK: IDs públicos
console.log("User logged in:", sUserId);

// ❌ PROHIBIDO: datos sensibles en logs
console.log("Password:", sPassword);
console.log("Token:", sAuthToken);
```

## 4. Performance — Lazy Loading y Memoria

```javascript
// ✅ OBLIGATORIO: Cargar dialogs/fragmentos bajo demanda
onOpenDialog: function() {
    if (!this._oDialog) {
        sap.ui.core.Fragment.load({
            id: this.getView().getId(),
            name: "my.app.view.fragments.MyDialog",
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

// ✅ OBLIGATORIO: Limpiar recursos en onExit
onExit: function() {
    if (this._oDialog) { this._oDialog.destroy(); this._oDialog = null; }
    if (this._iTimer)  { clearInterval(this._iTimer); this._iTimer = null; }
}
```

```javascript
// ✅ CORRECTO: Limitar datos con $select y paginación
const oBinding = this.byId("myTable").getBinding("items");
oBinding.changeParameters({ $select: "ID,Name,Status", $top: 50 });

const oTable = this.byId("myTable");
oTable.setGrowing(true);
oTable.setGrowingThreshold(20);
```

## 5. Error Handling Estructurado

```javascript
// ✅ CORRECTO: Usar sap/base/Log en lugar de console.log
sap.ui.define(["sap/base/Log"], function(Log) {
    Log.error("Failed to load data", oError, "com.myapp");
    Log.info("Application started", null, "com.myapp");
});

// ✅ CORRECTO: Manejo de errores OData + feedback al usuario
oModel.submitBatch("updateGroup")
    .then(() => MessageToast.show(this._i18n("dataSavedSuccess")))
    .catch(oError => {
        Log.error("Error saving", oError);
        MessageBox.error(this._i18n("dataSaveError"));
    });
```

## 6. Batch Requests — OData V2 vs OData V4

> ⚠️ **IMPORTANTE**: Las APIs de batch difieren completamente entre OData V2 y V4.
> Las apps modernas en BTP usan OData V4. Identifica la versión antes de aplicar el patrón.

### OData V2 — API Manual (`sap.ui.model.odata.v2.ODataModel`)

```javascript
// ✅ OData V2: batch manual con grupos diferidos
oModel.setDeferredGroups(["updateGroup"]);
oModel.create("/Items", oNewItem, { groupId: "updateGroup" });
oModel.update("/Items(1)", oUpdatedItem, { groupId: "updateGroup" });
oModel.submitChanges({ groupId: "updateGroup" }); // Envía todo en un batch
```

### OData V4 — Batch Automático (`sap.ui.model.odata.v4.ODataModel`)

```javascript
// ✅ OData V4: batch automático por grupos de binding (sin submitChanges)
// El modelo agrupa automáticamente las operaciones del mismo $batch group

// En manifest.json — configurar grupo de actualización
// "groupId": "$auto"  → batch automático por tick de UI
// "updateGroupId": "myGroup" → batch manual por grupo

// Batch manual en V4 — usar submitBatch()
oModel.submitBatch("myUpdateGroup")
    .then(() => MessageToast.show(this.getResourceBundle().getText("dataSaved")))
    .catch(oError => {
        Log.error("Batch failed", oError, "com.myapp");
        MessageBox.error(this.getResourceBundle().getText("dataSaveError"));
    });

// Operación individual en V4 — usa Context.delete() o Context.setProperty()
const oContext = oTable.getSelectedItem().getBindingContext();
oContext.setProperty("Status", "APPROVED"); // Va al grupo $auto por defecto
```

### Tabla de decisión

| Característica | OData V2 | OData V4 |
|---|---|---|
| **API batch** | `submitChanges({ groupId })` | `submitBatch(groupId)` |
| **Grupos** | `setDeferredGroups([])` | `groupId` en binding/manifest |
| **Batch automático** | ❌ Manual siempre | ✅ `$auto` por defecto |
| **Retorno** | Callback | Promise |
| **Apps nuevas BTP** | ❌ No recomendado | ✅ Usar V4 |

## Checklist

- [ ] No hay scripts inline en HTML
- [ ] No hay `eval()`, `innerHTML` directo, ni `document.write`
- [ ] No se loggean passwords, tokens ni datos sensibles
- [ ] Dialogs cargados lazy (Fragment.load, no new Dialog en onInit)
- [ ] `onExit` limpia todos los recursos creados dinámicamente
- [ ] Listas con `growing=true` y `growingThreshold ≤ 50`
- [ ] Errores OData capturados con `.catch()` y mostrados al usuario via MessageBox
