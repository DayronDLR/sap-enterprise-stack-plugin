# SAPUI5 Accessibility & i18n - Accesibilidad e Internacionalización

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%

## 1. Regla Fundamental: NUNCA Textos Hardcodeados

```xml
<!-- ❌ PROHIBIDO ABSOLUTAMENTE -->
<Button text="Guardar"/>
<Title text="Dashboard Principal"/>
<Label text="Nombre del Cliente"/>

<!-- ✅ OBLIGATORIO: Solo binding i18n -->
<Button text="{i18n>buttonSave}"/>
<Title text="{i18n>dashboardTitle}"/>
<Label text="{i18n>customerNameLabel}"/>
```

```javascript
// ❌ PROHIBIDO
MessageToast.show("Operación exitosa");

// ✅ OBLIGATORIO
MessageToast.show(this.getResourceBundle().getText("operationSuccess"));
```

## 2. Accesibilidad — ARIA Labels Obligatorios

```xml
<!-- ✅ OBLIGATORIO: Labels descriptivos para todos los controles interactivos -->
<Button text="{i18n>buttonSave}"
        tooltip="{i18n>buttonSaveTooltip}"
        ariaLabelledBy="saveButtonLabel"/>

<Label id="saveButtonLabel"
       text="{i18n>saveButtonAriaLabel}"
       visible="false"/>

<!-- ✅ OBLIGATORIO: Roles semánticos -->
<Panel accessibleRole="Region" ariaLabelledBy="panelHeader">
    <headerToolbar>
        <Toolbar>
            <Title id="panelHeader" text="{i18n>sectionTitle}"/>
        </Toolbar>
    </headerToolbar>
</Panel>

<!-- ✅ OBLIGATORIO: Estados dinámicos en inputs -->
<Input value="{/customerName}"
       required="true"
       ariaRequired="true"
       ariaInvalid="{= ${/customerNameError} ? 'true' : 'false'}"
       ariaDescribedBy="customerNameError"/>
```

## 3. Internacionalización (i18n)

### Configuración en Component.js

```javascript
sap.ui.define([
    "sap/ui/core/UIComponent",
    "sap/ui/model/resource/ResourceModel"
], function(UIComponent, ResourceModel) {
    "use strict";
    return UIComponent.extend("com.myapp.Component", {
        init: function() {
            UIComponent.prototype.init.apply(this, arguments);
            this.setModel(new ResourceModel({
                bundleName: "com.myapp.i18n.i18n",
                supportedLocales: ["en", "es", "de", "fr"],
                fallbackLocale: "en"
            }), "i18n");
        }
    });
});
```

### Estructura de archivos i18n

```
webapp/i18n/
├── i18n.properties       # Inglés (fallback)
├── i18n_es.properties    # Español
├── i18n_de.properties    # Alemán
└── i18n_fr.properties    # Francés
```

### Pluralización y parámetros

```properties
# i18n.properties
itemCount=You have {0} item(s)
welcomeMessage=Welcome, {0}!
```

```javascript
const sMessage = this.getResourceBundle().getText("itemCount", [iCount]);
const sWelcome = this.getResourceBundle().getText("welcomeMessage", [sUserName]);
```

## 4. Regla: Aplicar Cambios a TODOS los Locales

> **Documentación oficial SAP**: "When making changes to *.properties files, ALWAYS apply the changes to **all** relevant locales"

### ❌ PROHIBIDO: Agregar clave solo al fallback

```properties
# ❌ INCORRECTO: Solo agregar en i18n.properties y olvidar los demás locales
# webapp/i18n/i18n.properties
newFeatureTitle=New Feature Title

# webapp/i18n/i18n_es.properties  ← FALTA → key faltante causa texto en inglés sin aviso
# webapp/i18n/i18n_de.properties  ← FALTA
```

### ✅ OBLIGATORIO: Agregar en todos los archivos de locale

```properties
# webapp/i18n/i18n.properties (fallback English)
newFeatureTitle=New Feature Title
newFeatureDescription=This feature allows you to...

# webapp/i18n/i18n_es.properties
newFeatureTitle=Título de Nueva Funcionalidad
newFeatureDescription=Esta funcionalidad te permite...

# webapp/i18n/i18n_de.properties
newFeatureTitle=Titel der neuen Funktion
newFeatureDescription=Mit dieser Funktion können Sie...

# webapp/i18n/i18n_fr.properties
newFeatureTitle=Titre de la nouvelle fonctionnalité
newFeatureDescription=Cette fonctionnalité vous permet de...
```

### Proceso obligatorio al agregar/modificar claves i18n

1. Agregar/modificar la clave en `i18n.properties` (fallback)
2. Agregar/modificar la clave en **todos** los `i18n_XX.properties` existentes
3. Verificar que ningún locale quede sin la clave

## 5. RTL y Alto Contraste

- **RTL**: UI5 maneja automáticamente la dirección en los controles estándar. Usar clases `sapUiMarginBegin/End` en lugar de `margin-left/right` en CSS propio.
- **Alto contraste**: Los temas `sap_horizon_hcb` y `sap_horizon_hcw` se soportan automáticamente si no se sobreescribe CSS de controles. No usar colores hardcodeados; usar variables `var(--sapTextColor)`, `var(--sapBackgroundColor)`.

## Checklist de Compliance

- [ ] Cero textos hardcodeados en XML — solo `{i18n>key}`
- [ ] Cero strings hardcodeados en JS — solo `this.getResourceBundle().getText()`
- [ ] Todos los controles interactivos tienen ARIA labels
- [ ] Orden de tabulación lógico (inputs → botones al final)
- [ ] i18n configurado con supportedLocales y fallbackLocale
- [ ] Parámetros dinámicos con `getText("key", [param])` — nunca concatenación
- [ ] **Toda clave nueva/modificada aplicada a TODOS los archivos de locale**
