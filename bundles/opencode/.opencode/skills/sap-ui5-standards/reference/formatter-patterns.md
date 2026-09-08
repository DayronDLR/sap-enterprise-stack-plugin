# REFERENCIA TECNICA -- Formatter Patterns

> **Contenido**: Patrones estandar de formatters SAPUI5 (`webapp/model/formatter.js`) y su uso en XML Views.
> **Fuente**: Extraido de `agents/04-fiori-ui5/system_prompt.md` para lazy-load.
> **Cuanto consultar**: Cuando se necesiten formatters para status states, iconos, numeros, booleanos o nombres compuestos.

---

Todos los formatters en `webapp/model/formatter.js`. Nunca inline en XML.

```javascript
// webapp/model/formatter.js
sap.ui.define([], function() {
    "use strict";

    const STATUS_STATE_MAP = {
        "APPROVED": "Success", "PENDING": "Warning",
        "REJECTED": "Error",   "DRAFT": "Information"
    };
    const STATUS_ICON_MAP = {
        "APPROVED": "sap-icon://accept",  "PENDING": "sap-icon://pending",
        "REJECTED": "sap-icon://decline", "DRAFT": "sap-icon://edit"
    };

    return {
        /** Estado semantico para ObjectStatus/HighlightColor */
        statusState: function(sStatus) {
            return STATUS_STATE_MAP[sStatus] || "None";
        },
        /** Icono segun estado */
        statusIcon: function(sStatus) {
            return STATUS_ICON_MAP[sStatus] || "sap-icon://question-mark";
        },
        /** Numero con separador de miles */
        numberFormat: function(nValue) {
            return nValue == null ? "0" : nValue.toLocaleString();
        },
        /** Valor en millones */
        toMillions: function(fValue) {
            return !fValue ? "0 M" : `${Math.floor(fValue / 1000000)} M`;
        },
        /** Booleano a texto */
        booleanText: function(bValue) {
            return bValue ? "Si" : "No";
        },
        /** Invertir booleano para visibilidad */
        invertBoolean: function(bValue) {
            return !bValue;
        },
        /** Nombre completo desde partes (composite binding) */
        fullName: function(sFirstName, sLastName) {
            if (!sFirstName && !sLastName) return "";
            return `${sFirstName || ""} ${sLastName || ""}`.trim();
        }
    };
});
```

**Uso en XML View:**

```xml
<mvc:View core:require="{ Formatter: 'com/myapp/model/formatter' }">
    <ObjectStatus state="{path: 'status', formatter: 'Formatter.statusState'}"
                  icon="{path: 'status', formatter: 'Formatter.statusIcon'}"/>
    <Text text="{parts: [{path: 'firstName'}, {path: 'lastName'}],
                 formatter: 'Formatter.fullName'}"/>
</mvc:View>
```
