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

### @UI Annotations esenciales (ABAP CDS — Metadata Extension)

```abap
// Metadata Extension (preferida sobre anotar la projection inline).
// La projection necesita @Metadata.allowExtensions: true.
@Metadata.layer: #CUSTOMER
@UI.headerInfo: {
  typeName: 'Sales Order',
  typeNamePlural: 'Sales Orders',
  title: { value: 'SalesOrder', type: #STANDARD },
  description: { value: 'SoldToParty', type: #STANDARD }
}
// Variante de selección: va en la cabecera, no con la sintaxis @( … ) de CAP
@UI.selectionVariant: [{ qualifier: 'sv_approved', text: 'Approved Orders', filter: 'Status EQ "A"' }]
annotate entity ZC_SalesOrder with {

  @UI.facet: [
    { id: 'GeneralData', type: #COLLECTION, label: 'General', position: 10 },
    { id: 'BasicData',   type: #IDENTIFICATION_REFERENCE, parentId: 'GeneralData',
      label: 'Basic Data', position: 10 },
    { id: 'Items',       type: #LINEITEM_REFERENCE, targetElement: '_Items',
      label: 'Items', position: 20 }
  ]
  @UI.lineItem: [
    { position: 10, label: 'Order No.' },
    { type: #FOR_ACTION, dataAction: 'Approve', label: 'Approve', position: 30 }
  ]
  @UI.selectionField: [{ position: 10 }]
  @UI.identification: [{ position: 10 }]
  SalesOrder;

  @UI.lineItem:      [{ position: 20 }]
  @UI.selectionField:[{ position: 20 }]
  @UI.identification:[{ position: 20 }]
  // Necesita @ObjectModel.text.element: ['SoldToPartyName'] en la projection:
  // sin un elemento de texto, textArrangement no tiene qué mostrar.
  @UI.textArrangement: #TEXT_ONLY
  SoldToParty;

  @UI.lineItem:      [{ position: 30 }]
  @UI.identification:[{ position: 30 }]
  NetAmount;

  @UI.hidden: true
  Currency;
}
```

### @Search, @Semantics, @ObjectModel (en la projection o la interface view)

<!-- ses:fragmento: elementos sueltos de la lista de una view entity, sin el define -->
```abap
  @Search.defaultSearchElement: true
  SalesOrder,

  @Semantics.amount.currencyCode: 'Currency'
  NetAmount,

  Currency,

  @ObjectModel.text.element: [ 'SoldToPartyName' ]
  SoldToParty,
```

`@Search.searchable: true` va en la cabecera de la vista, no en un elemento.

### Texto, value help y side effects — ABAP CDS y CAP no se anotan igual

| Necesidad | ABAP CDS (RAP) | CAP (`.cds`) |
| --- | --- | --- |
| Texto de un código | `@ObjectModel.text.element: ['…Name']` + `@UI.textArrangement` | `@Common.Text: …` + `@Common.TextArrangement` |
| Value help | `@Consumption.valueHelpDefinition` | `@Common.ValueList` |
| Dropdown de valores fijos | `@ObjectModel.resultSet.sizeCategory: #XS` en la vista del value help | `@Common.ValueListWithFixedValues` |
| Side effects | En el BDEF: `side effects { … }` | `@Common.SideEffects` |

> **Regla crítica del texto**: apunta a un elemento **separado** con la descripción
> legible (`SoldToPartyName`, `_Customer.Name`), nunca a la propia key. Si apunta a
> sí mismo, Fiori Elements muestra el código como texto o entra en bucle.

<!-- ses:fragmento: un elemento de la lista de la projection, sin el define -->
```abap
// ABAP CDS — value help sobre la projection
@Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_StatusVH', element: 'Status' } }]
@ObjectModel.text.element: [ 'StatusText' ]
@UI.textArrangement: #TEXT_ONLY
Status,
```

```abap
// BDEF de la projection o de la base — side effects (RAP, OData V4)
side effects
{
  field SoldToParty affects field NetAmount, field Currency;
  field Status affects entity _Items;
}
```

```cds
// CAP — el mismo comportamiento con el vocabulario Common
annotate CatalogService.SalesOrders with {
  soldToParty @Common.Text: soldToPartyName  @Common.TextArrangement: #TextOnly;
  status      @Common.ValueListWithFixedValues;
};

annotate CatalogService.SalesOrders with @(
  Common.SideEffects #SoldToPartyChanged: {
    SourceProperties: [ soldToParty ],
    TargetProperties: [ 'netAmount', 'currency' ]
  }
);
```

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
