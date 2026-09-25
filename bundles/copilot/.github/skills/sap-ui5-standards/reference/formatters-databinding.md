# SAPUI5 Formatters & Data Binding - Reglas Fundamentales

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%

## 1. Ubicación y Uso de Formatters

### ✅ OBLIGATORIO: Siempre en webapp/model/formatter.js

```javascript
// webapp/model/formatter.js — ÚNICA ubicación válida
sap.ui.define([], function() {
    "use strict";
    return {
        upperFirstLetter: function(sName) {
            if (!sName) return "";
            return sName.charAt(0).toUpperCase() + sName.slice(1);
        }
    };
});
```

### ❌ PROHIBIDO: Formatters Inline en XML

```xml
<!-- ❌ NUNCA: expression binding para lógica compleja -->
<Text text="{= ${status} === 'PENDING' ? 'En Proceso' : 'Completado' }"/>

<!-- ❌ NUNCA: formatter definido directamente en vista -->
<Text text="{path: 'name', formatter: function(v){return v.toUpperCase();}}"/>
```

### ✅ Uso Correcto en XML View

```xml
<!-- Método moderno: core:require -->
<mvc:View xmlns:core="sap.ui.core"
          core:require="{ Formatter: 'com/myapp/model/formatter' }">
    <Text text="{path: 'name', formatter: 'Formatter.upperFirstLetter'}"/>
</mvc:View>

<!-- Método tradicional: dot notation via controller -->
<Text text="{path: 'name', formatter: '.formatter.upperFirstLetter'}"/>
```

## 2. Contexto `this` en Formatters — CRÍTICO

| Método de uso | `this` dentro del formatter |
|---|---|
| `core:require` + `'Formatter.fn'` | Objeto formatter |
| Dot notation `.formatter.fn` | Controller instance |
| `.bind($control)` | Control instance |
| `.bind($controller)` | Controller instance |

```xml
<!-- Forzar contexto explícitamente -->
<Text text="{path: 'name', formatter: 'Formatter.fn.bind($controller)'}"/>
```

**Restricción:** Argumentos de `.bind()` no pueden empezar con `$` excepto `$control` y `$controller`.

## 3. Function Expressions vs Arrow Functions

```javascript
return {
    // ✅ RECOMENDADO: function expression — 'this' disponible según contexto
    statusState: function(sStatus) {
        const mStates = { "PENDING": "Warning", "VALIDATED": "Success", "REJECTED": "Error" };
        return mStates[sStatus] || "None";
    },

    // ⚠️ LIMITADO: arrow function — 'this' NO disponible (lexical scope)
    // Solo usar para formatters puros sin dependencias de contexto
    simpleFormat: (sValue) => sValue ? sValue.toUpperCase() : ""
};
```

## 4. Jerarquía de Tipos y Formatters — Decisión Oficial

La documentación oficial SAP establece una jerarquía obligatoria. Seguirla en este orden:

### 🥇 PRIMERO: OData Types (`sap.ui.model.odata.type.*`)

```xml
<!-- ✅ OBLIGATORIO: Usar OData types cuando el campo viene de un servicio OData -->
<!-- Para número con separador de miles → OData Decimal, NO formatter custom -->
<Text text="{
    path: 'price',
    type: 'sap.ui.model.odata.type.Decimal',
    formatOptions: { groupingEnabled: true, minFractionDigits: 2 }
}"/>

<!-- Para fechas OData -->
<Text text="{
    path: 'createdAt',
    type: 'sap.ui.model.odata.type.DateTime',
    formatOptions: { style: 'medium' }
}"/>

<!-- Para moneda OData -->
<Text text="{
    parts: ['amount', 'currency'],
    type: 'sap.ui.model.odata.type.Currency'
}"/>
```

**Tipos OData más usados:**

- `sap.ui.model.odata.type.Decimal` — números decimales con agrupación
- `sap.ui.model.odata.type.DateTime` — fechas y timestamps
- `sap.ui.model.odata.type.Currency` — monedas con código de divisa
- `sap.ui.model.odata.type.Unit` — cantidades con unidad de medida
- `sap.ui.model.odata.type.String` — strings con constraints de longitud

### 🥈 SEGUNDO: Standard Types (`sap.ui.model.type.*`)

Solo cuando no existe equivalente en OData types:

```xml
<!-- ✅ Solo si no hay OData type equivalente -->
<Input value="{
    path: '/quantity',
    type: 'sap.ui.model.type.Integer',
    constraints: { minimum: 0, maximum: 1000 }
}"/>
```

### 🥉 ÚLTIMO RECURSO: Formatter Custom

Solo para lógica de presentación única que no puede modelarse con tipos:

```xml
<!-- ✅ Solo para lógica de negocio de presentación que no cubre ningún type -->
<ObjectStatus
    state="{path: 'status', formatter: 'Formatter.statusToState'}"
    text="{path: 'status', formatter: 'Formatter.statusToText'}"/>
```

### Tabla comparativa completa

| Característica | OData Type | Standard Type | Formatter |
|---|---|---|---|
| **Dirección** | Two-way | Two-way | One-way |
| **Parsing** | ✅ Sí | ✅ Sí | ❌ No |
| **Validación** | ✅ Sí | ✅ Sí | ❌ No |
| **Localización** | ✅ Automática | ✅ Automática | Manual |
| **Prioridad** | 🥇 Primera opción | 🥈 Segunda opción | 🥉 Último recurso |
| **Cuándo usar** | Datos OData | Datos locales/JSON | Lógica única presentación |

## 5. Patrones Prohibidos

```javascript
// ❌ NUNCA: lógica de negocio en formatters
calculateDiscount: function(nPrice, nQuantity) { /* lógica de negocio */ }

// ❌ NUNCA: side effects
formatAndCount: function(sValue) { this.counter++; return sValue; }

// ❌ NUNCA: llamadas asíncronas
formatWithAPI: function(sId) { fetch(`/api/${sId}`).then(...); return "..."; }
```

## Checklist

- [ ] Todos los formatters en `webapp/model/formatter.js`
- [ ] No hay formatters inline en XML views
- [ ] Usar `function()` cuando se necesita `this`; arrow function solo para formatters puros
- [ ] Validar parámetros null/undefined en cada formatter
- [ ] Sin lógica de negocio ni side effects en formatters
