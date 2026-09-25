# Security & Performance — SAPUI5 FreeStyle

## Content Security Policy (CSP)

```html
<!-- index.html — CSP meta tag -->
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self'; script-src 'self' 'unsafe-eval';
               style-src 'self' 'unsafe-inline'; img-src 'self' data:;">

<!-- ✅ CSP-compliant bootstrap -->
<script id="sap-ui-bootstrap"
    src="resources/sap-ui-core.js"
    data-sap-ui-on-init="module:sap/ui/core/ComponentSupport"
    data-sap-ui-async="true">
</script>
```

```html
<!-- ❌ NEVER — violates CSP -->
<script>sap.ui.getCore().attachInit(function() { /* ... */ });</script>
<div style="color: red;">...</div>
```

## XSS Prevention

```typescript
// ❌ NEVER — direct HTML injection
this.byId("myDiv").getDomRef()!.innerHTML = sUserInput;
document.write(sUserInput);

// ✅ ALWAYS — UI5 controls encode automatically
const oText = new Text({ text: sUserInput }); // auto-encoded

// ✅ Manual encoding when needed
import encodeHTML from "sap/base/security/encodeHTML";
const sSafe = encodeHTML(sUserInput);
```

### Custom Renderer — apiVersion 2 Required

```typescript
import RenderManager from "sap/ui/core/RenderManager";

const MyControlRenderer = {
    apiVersion: 2, // ← MANDATORY: enables secure rendering (XSS protection)

    render(oRm: RenderManager, oControl: MyControl): void {
        oRm.openStart("div", oControl);
        oRm.class("myControlClass");
        oRm.openEnd();
        oRm.text(oControl.getText()); // auto-encoded
        oRm.close("div");
    }
};
```

## Input Validation

```typescript
import sanitizeHTML from "sap/base/security/sanitizeHTML";

public onInputChange(oEvent: Input$ChangeEvent): void {
    const sValue = oEvent.getParameter("value") as string;

    // Validate format
    if (!/^[a-zA-Z0-9\s.,@-]+$/.test(sValue)) {
        MessageBox.error(this.getResourceBundle().getText("validationInvalidChar"));
        return;
    }

    this.getView()!.getModel()!.setProperty("/field", sanitizeHTML(sValue));
}
```

## Logging — Never Log Sensitive Data

```typescript
import Log from "sap/base/Log";

// ✅ OK — log IDs and non-sensitive info
Log.info("Order loaded", sOrderId, "com.myapp");
Log.error("Failed to load data", oError.message, "com.myapp");

// ❌ NEVER — sensitive data in logs
Log.info("User password", sPassword);       // NEVER
Log.debug("Auth token", sToken);            // NEVER
console.log("Session data", oSessionData);  // NEVER (use Log module)
```

## Lazy Loading — Dialogs & Fragments

```typescript
private _oDialog: Dialog | undefined;

// ✅ Load on first use only
public async onOpenConfirmDialog(): Promise<void> {
    if (!this._oDialog) {
        this._oDialog = await Fragment.load({
            id: this.getView()!.getId(),
            name: "com.myapp.view.fragments.ConfirmDialog",
            controller: this
        }) as Dialog;
        this.getView()!.addDependent(this._oDialog);
    }
    this._oDialog.open();
}

// ✅ MANDATORY — clean up all dynamic resources
public onExit(): void {
    if (this._oDialog) {
        this._oDialog.destroy();
        this._oDialog = undefined;
    }
    if (this._iPollingTimer) {
        clearInterval(this._iPollingTimer);
    }
}
```

## Table Performance

```typescript
// ✅ Growing table — avoid loading all records
// In XML: growing="true" growingThreshold="20"

// ✅ Limit fields with $select
const oBinding = (this.byId("table") as Table).getBinding("items") as ListBinding;
oBinding.changeParameters({
    $select: "ID,Name,Status,CreatedAt",
    $top: 50
});

// ✅ Server-side filtering (operationMode: "Server" in manifest)
oBinding.filter([
    new Filter("Status", FilterOperator.EQ, "PENDING")
]);
```

## OData Batch — V2 vs V4

```typescript
// OData V4 — batch via submitBatch (no submitChanges)
const oModel = this.getView()!.getModel() as ODataModel;
try {
    await oModel.submitBatch("myUpdateGroup");
    MessageToast.show(this.getResourceBundle().getText("msgSaveSuccess"));
} catch (oError) {
    Log.error("Batch failed", (oError as Error).message, "com.myapp");
    MessageBox.error(this.getResourceBundle().getText("msgSaveError"));
}

// OData V4 — auto batch (default $auto group)
const oContext = oTable.getSelectedItem().getBindingContext() as Context;
await oContext.setProperty("Status", "APPROVED"); // goes to $auto batch
```

## Error Handling Pattern

```typescript
// ✅ Structured error handling for OData operations
private async _saveData(): Promise<void> {
    this.getView()!.setBusy(true);
    try {
        const oModel = this.getView()!.getModel() as ODataModel;
        await oModel.submitBatch("updateGroup");
        MessageToast.show(this.getResourceBundle().getText("msgSaveSuccess"));
        this.navTo("main");
    } catch (oError: unknown) {
        Log.error("Save failed", oError as string, "com.myapp");
        MessageBox.error(
            this.getResourceBundle().getText("msgSaveError"),
            { title: this.getResourceBundle().getText("errorTitle") }
        );
    } finally {
        this.getView()!.setBusy(false);
    }
}
```
