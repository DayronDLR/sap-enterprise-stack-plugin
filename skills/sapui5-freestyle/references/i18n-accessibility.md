# i18n & Accessibility — SAPUI5 FreeStyle

## Rule #1: Zero Hardcoded Text

```xml
<!-- ❌ NEVER — hardcoded text -->
<Button text="Guardar"/>
<Title text="Dashboard Principal"/>
<Label text="Nombre del Cliente"/>

<!-- ✅ ALWAYS — i18n binding -->
<Button text="{i18n>buttonSave}"/>
<Title text="{i18n>dashboardTitle}"/>
<Label text="{i18n>customerNameLabel}"/>
```

```typescript
// ❌ NEVER
MessageToast.show("Operación exitosa");
MessageBox.error("Error al guardar");

// ✅ ALWAYS
MessageToast.show(this.getResourceBundle().getText("operationSuccess"));
MessageBox.error(this.getResourceBundle().getText("errorSave"));

// With parameters
const sMsg = this.getResourceBundle().getText("itemCount", [iCount]);
// i18n: itemCount=Tiene {0} elemento(s)
```

## i18n File Structure

```
webapp/i18n/
├── i18n.properties       ← English (fallback — ALWAYS required)
├── i18n_es.properties    ← Spanish
├── i18n_pt.properties    ← Portuguese (if needed)
└── i18n_de.properties    ← German (if needed)
```

## Component.ts — i18n Model Setup

```typescript
import ResourceModel from "sap/ui/model/resource/ResourceModel";

// In Component.ts init() — or via manifest.json models section
this.setModel(new ResourceModel({
    bundleName: "com.myapp.i18n.i18n",
    supportedLocales: ["en", "es", "pt"],
    fallbackLocale: "en"
}), "i18n");
```

Or in manifest.json (preferred):

```json
{
  "sap.ui5": {
    "models": {
      "i18n": {
        "type": "sap.ui.model.resource.ResourceModel",
        "settings": {
          "bundleName": "com.myapp.i18n.i18n",
          "supportedLocales": ["en", "es"],
          "fallbackLocale": "en"
        }
      }
    }
  }
}
```

## Updating Keys — ALL Locales Required

When adding or modifying a key, update EVERY locale file:

```properties
# i18n.properties (English fallback)
buttonSave=Save
buttonSaveTooltip=Save the current record
operationSuccess=Operation completed successfully
itemCount=You have {0} item(s)

# i18n_es.properties (Spanish)
buttonSave=Guardar
buttonSaveTooltip=Guardar el registro actual
operationSuccess=Operación completada exitosamente
itemCount=Tiene {0} elemento(s)

# i18n_pt.properties (Portuguese)
buttonSave=Salvar
buttonSaveTooltip=Salvar o registro atual
operationSuccess=Operação concluída com sucesso
itemCount=Você tem {0} item(ns)
```

❌ Missing a locale = that language falls back to English silently. Always update all files.

## ARIA Labels — Required for All Interactive Controls

```xml
<!-- Buttons -->
<Button text="{i18n>buttonSave}"
        tooltip="{i18n>buttonSaveTooltip}"
        ariaLabelledBy="saveBtnLabel"/>
<Label id="saveBtnLabel" text="{i18n>buttonSaveAriaLabel}" visible="false"/>

<!-- Required inputs -->
<Input id="nameInput"
       value="{/name}"
       required="true"
       ariaRequired="true"
       ariaDescribedBy="nameError"
       ariaInvalid="{= ${/nameError} ? 'true' : 'false'}"/>
<Text id="nameError" text="{/nameErrorMsg}" visible="{= !!${/nameError}}"/>

<!-- Semantic regions -->
<Panel accessibleRole="Region" ariaLabelledBy="panelHeader">
    <headerToolbar>
        <Toolbar>
            <Title id="panelHeader" text="{i18n>sectionTitle}"/>
        </Toolbar>
    </headerToolbar>
</Panel>

<!-- Table -->
<Table ariaLabelledBy="tableTitle">
    <!-- ... -->
</Table>
<Title id="tableTitle" text="{i18n>tableTitle}" visible="false"/>
```

## Tab Order — Logical Flow

Controls receive focus in DOM order. Place inputs before action buttons:

1. Filter/search fields
2. Form inputs (top to bottom, left to right)
3. Primary action button last (Save, Submit)
4. Secondary actions (Cancel)

```xml
<!-- ✅ Correct tab order in toolbar -->
<Toolbar>
    <SearchField/>        <!-- 1st tab stop -->
    <ToolbarSpacer/>
    <Button text="{i18n>buttonCreate}" type="Emphasized"/>  <!-- last -->
</Toolbar>
```

## RTL & High Contrast

- Use `sapUiMarginBegin`/`sapUiMarginEnd` instead of `margin-left`/`margin-right` (RTL-safe)
- Themes `sap_horizon_hcb` and `sap_horizon_hcw` work automatically with standard controls
- Never use hardcoded colors in CSS — use `var(--sapTextColor)`, `var(--sapBackgroundColor)`

## Common i18n Key Naming Convention

```properties
# Buttons
buttonSave=Save
buttonCancel=Cancel
buttonCreate=Create
buttonEdit=Edit
buttonDelete=Delete
buttonBack=Back

# Titles & Headers
appTitle=My Application
pageMainTitle=Overview
pageDetailTitle=Details

# Table
tableNoData=No data found
colId=ID
colName=Name
colStatus=Status

# Messages
msgSaveSuccess=Changes saved successfully
msgSaveError=Error saving changes. Please try again.
msgDeleteConfirm=Are you sure you want to delete this record?
msgLoading=Loading...

# Validation
validationRequired={0} is required
validationEmail=Please enter a valid email address
```
