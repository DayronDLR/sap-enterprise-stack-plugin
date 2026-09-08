# Floorplans de Fiori Elements, annotations CDS y adaptation projects

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## Fiori Elements — Floorplans Completos

- List Report + Object Page (LR+OP): el más usado, para entidades con lista y detalle
- Worklist: lista sin barra de filtros, para tareas simples
- Analytical List Page (ALP): con KPI header y tabla analítica
- Form Object Page: para formularios simples de captura
- Custom Page: OData V4 (SAPUI5 1.99+) — páginas extensibles con Building Blocks, para UX compleja dentro de Fiori Elements
- Fiori Elements con OData V4: mandatory en nuevos proyectos S/4HANA 2021+
- **Flexible Programming Model** (OData V4): añadir lógica/UI custom dentro del shell estándar de Fiori Elements sin abandonarlo — Building Blocks (`sap.fe.macros`: Table, Chart, Field, FilterBar), Custom Sections/Columns/Actions y `sap.fe.core.PageController` con extension API. Preferir esto sobre Freestyle cuando sólo se necesita extender, no reescribir.

## Annotations CDS para Fiori Elements

### @UI Annotations esenciales

```abap
"-- En CDS Projection View o Metadata Extension:
annotate view ZC_SalesOrder with {

  @UI.facet: [
    { id: 'GeneralData', type: #COLLECTION, label: 'General', position: 10 },
    { id: 'BasicData',   type: #IDENTIFICATION_REFERENCE, parentId: 'GeneralData',
      label: 'Basic Data', position: 10 },
    { id: 'Items',       type: #LINEITEM_REFERENCE, targetElement: '_Items',
      label: 'Items', position: 20 }
  ]

  @UI.headerInfo: {
    typeName: 'Sales Order',
    typeNamePlural: 'Sales Orders',
    title: { value: 'SalesOrder', type: #STANDARD },
    description: { value: 'SoldToParty', type: #STANDARD }
  }

  @UI.lineItem: [
    { position: 10, label: 'Order No.' },
    { position: 20 },
    { type: #FOR_ACTION, dataAction: 'Approve', label: 'Approve', position: 30 }
  ]
  @UI.selectionField: [{ position: 10 }]
  @UI.identification: [{ position: 10 }]
  SalesOrder;

  @UI.lineItem:      [{ position: 20 }]
  @UI.selectionField:[{ position: 20 }]
  @UI.identification:[{ position: 20 }]
  SoldToParty;

  @UI.lineItem:      [{ position: 30 }]
  @UI.identification:[{ position: 30 }]
  NetAmount;

  @UI.hidden: true
  Currency;
}

"-- Metadata Extensions (preferido sobre anotaciones inline):
@Metadata.layer: #CUSTOMER
annotate view ZC_SalesOrder with @(
  UI.selectionVariant #sv_approved: {
    Text: 'Approved Orders',
    SelectOptions: [{ PropertyName: Status, Ranges: [{ Sign: #I, Option: #EQ, Low: 'A' }] }]
  }
);
```

### @Search, @Semantics, @ObjectModel

```abap
  @Search.searchable: true
  @Search.defaultSearchElement: true
  SalesOrder;

  @Semantics.amount.currencyCode: 'Currency'
  NetAmount;

  @Semantics.currencyCode: true
  Currency;

  @ObjectModel.text.association: '_SoldToPartyText'
  SoldToParty;
```

### @Common, @Core.SideEffects — Annotations Críticas

```abap
"-- @Common.Text: DEBE apuntar a propiedad SEPARADA de descripción, NUNCA a la key property
  @Common.Text: { $value: '_SoldToPartyText.BusinessPartnerFullName', textArrangement: #TEXT_ONLY }
  @Common.Label: 'Sold To Party'
  SoldToParty;   "-- ✅ key apunta a propiedad separada de texto

"-- ❌ INCORRECTO: @Common.Text apuntando a sí mismo (la misma key property)
"-- @Common.Text: { $value: 'SalesOrder' }  ← NUNCA así

"-- @Common.ValueHelpWithFixedValues: validación estricta — solo valores del value help permitidos
  @Common.ValueHelpWithFixedValues: true
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_StatusVH', element: 'Status' } }]
  Status;

"-- @Common.ValueListForValidation: valida el campo incluso sin ValueHelpWithFixedValues
  @Common.ValueListForValidation: ''
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_OrderTypeVH', element: 'OrderType' } }]
  OrderType;

"-- @Core.SideEffects: declara qué propiedades se refrescan cuando otras cambian
annotate entity ZC_SalesOrder with @(
  Core.SideEffects #SoldToPartyChanged: {
    SourceProperties: [ SoldToParty ],
    TargetProperties: [ 'NetAmount', 'Currency' ]
  },
  Core.SideEffects #StatusChanged: {
    SourceProperties: [ Status ],
    TargetElements:   [ '_Items' ]
  }
);
```

> **Regla crítica `@Common.Text`**: Esta anotación DEBE referenciar una **propiedad separada** que contiene la descripción legible. Si apunta a la misma key property, Fiori Elements entra en bucle o muestra datos incorrectos.

## Adaptation Projects — Extensión de Apps Estándar

Un Adaptation Project permite **extender apps Fiori estándar SAP** (como ME23N, F-01, etc.) sin modificar el código fuente original. Es el patrón Clean Core para personalizar Fiori On-Premise.

**Cuándo aplica:**

- Agregar campos a una app Fiori estándar
- Cambiar labels, visibilidad o orden de campos
- Agregar botones o acciones custom
- Modificar lógica de controlador via extension points

**Flujo básico:**

```text
1. Crear: SAP Business Application Studio → New Project → Adaptation Project
   - Seleccionar la app base (e.g., sap.fe.managedapproval)
   - Sistema: conectar a S/4HANA On-Premise o BTP
2. Adaptar: Page Editor → Add Fragments / Override Controllers
   - UI Changes: agregar campos, mover secciones, renombrar labels
   - Controller Extensions: implementar onInit, onBeforeRendering, etc.
3. Preview: Vista previa en BAS con datos mock o live
4. Deploy:
   - On-Premise: abapGit o /UI5/UI5_REPOSITORY_LOAD → activar en SICF
   - BTP: cf deploy (MTA) → HTML5 Application Repository
```

**Artefactos generados:**

- `webapp/manifest.appdescr_variant` — variante del descriptor de la app base
- `webapp/changes/` — fragmentos XML de cambios de UI
- `webapp/ext/` — extensiones de controlador

## Fiori Tools AI / Joule — Generación Acelerada

SAP Fiori Tools incluye integración con **Joule (Project Accelerator)** para generar scaffolding inicial y artefactos ongoing sin configuración manual.

**Cuándo usar Joule:**

- Scaffolding inicial de una app Fiori Elements completa (entidades, relaciones, páginas UI)
- Generación de data model, service definition, y UI artifacts desde una descripción
- Iteración rápida de prototipos antes de refinar manualmente

**Flujo con Project Accelerator:**

```text
1. Abrir SAP Business Application Studio → Joule → "Generate App"
2. Proporcionar JSON estructurado con:
   {
     "entities": [{ "name": "SalesOrder", "properties": [...] }],
     "relations": [{ "from": "SalesOrder", "to": "SalesOrderItem", "type": "composition" }],
     "uiPages": [{ "type": "ListReport", "entity": "SalesOrder" }]
   }
3. Joule genera: CDS schema + service + annotations + manifest.json + vistas Fiori Elements
4. Refinar el código generado con las reglas de este agente (annotations, draft, seguridad)
```

> **Nota**: El código generado por Joule es punto de partida — siempre revisar y completar annotations faltantes (`@Core.SideEffects`, `@Common.ValueHelpWithFixedValues`, etc.) y agregar validaciones de Behavior Definition.
