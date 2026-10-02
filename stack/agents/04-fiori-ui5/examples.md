# 🎨 AGENTE 06 — Ejemplos de Uso

## Ejemplo 1: App Fiori Elements de Aprobación de Solicitudes de Compra

**Prompt de entrada:**

```text
Crea una aplicación Fiori Elements para aprobar/rechazar solicitudes de compra (ME54N digital).
Objeto: Solicitudes de Compra pendientes de mi aprobación.
Módulo: SAP MM S/4HANA 2023.
Lista: Número SC, Proveedor, Material, Cantidad, Valor, Fecha necesidad.
Detalle: todas las posiciones + historial de liberación.
Acciones: Aprobar (individual y masivo), Rechazar con motivo obligatorio.
Sistema: S/4HANA On-Premise con BAS.
```

**Output esperado del agente:**

**CDS Views:**

```abap
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Purchase Requisitions for Approval'
@Metadata.ignorePropagatedAnnotations: true
@UI.headerInfo: { typeName: 'Purchase Requisition', title: { value: 'PurchaseRequisition' } }

define root view entity ZC_MM_PR_APPROVAL
  provider contract transactional_query
  as projection on ZI_MM_PR_APPROVAL
{
  // La acción no es un elemento: su botón se declara en el @UI.lineItem de un campo
  @UI.lineItem: [{ position: 10, importance: #HIGH },
                 { type: #FOR_ACTION, dataAction: 'approve', label: 'Approve' }]
  @UI.selectionField: [{ position: 10 }]
  key PurchaseRequisition,
  @UI.lineItem: [{ position: 20 }]
  Supplier,
  @UI.lineItem: [{ position: 30 }]
  Material
}
```

- Behavior Definition con actions `approve` y `reject`
- `manifest.json` con routing y service bindings
- Launchpad config: semanticObject `PurchaseRequisition`, action `approve`
- Rol Fiori: Business Catalog `SAP_MM_BC_PO_APPROVE_PC` + role customization
- OPA5 test: verificar botón Approve aparece solo con status correcto

---

## Ejemplo 2: App UI5 Freestyle — Dashboard de KPIs de Ventas

**Prompt de entrada:**

```text
Crea una app SAPUI5 Freestyle para mostrar un dashboard de KPIs de ventas.
KPIs: Ventas del mes (vs mes anterior), Top 10 clientes, Ventas por región (mapa/barra),
Órdenes pendientes de entrega.
Datos: OData V4 desde CDS View ZC_SD_SALES_DASHBOARD.
Plataforma: SAP BTP con BAS, desplegada en SAP Build Work Zone.
```

**Output esperado del agente:**

**Estructura:**

```text
webapp/
├── Component.js
├── manifest.json          (OData V4 model, routing)
├── controller/
│   ├── App.controller.js
│   └── Dashboard.controller.js  (KPI logic, formatters)
├── view/
│   ├── App.view.xml
│   └── Dashboard.view.xml      (sap.suite.ui.commons.NumericContent, sap.viz.ui5.controls.VizFrame)
├── model/
│   └── models.js              (JSONModel para KPIs locales)
├── formatter/
│   └── formatter.js           (formatMoney, formatDelta, colorByTrend)
└── i18n/i18n.properties
```

**Dashboard.view.xml:**

```xml
<mvc:View controllerName="myapp.controller.Dashboard"
          xmlns:mvc="sap.ui.core.mvc"
          xmlns="sap.m"
          xmlns:f="sap.f"
          xmlns:viz="sap.viz.ui5.controls"
          displayBlock="true">
  <!-- ✅ DynamicPage: patrón correcto para dashboards con contenido variado -->
  <f:DynamicPage id="dashboardPage" headerPinnable="false" toggleHeaderOnTitleClick="false">
    <f:title>
      <f:DynamicPageTitle>
        <f:heading>
          <Title text="{i18n>dashboardTitle}"/>
        </f:heading>
      </f:DynamicPageTitle>
    </f:title>
    <f:content>
      <!-- KPI Cards — HBox directo, sin VBox contenedor extra -->
      <HBox wrap="Wrap" class="sapUiMediumMargin">
        <GenericTile headerImage="sap-icon://sales-order"
          header="{i18n>monthlySales}"
          subheader="{= ${sales>/currentMonth} > ${sales>/prevMonth} ? '▲' : '▼' }"
          class="sapUiSmallMarginEnd sapUiSmallMarginBottom">
          <NumericContent value="{sales>/currentMonth}"
            valueColor="{formatter>/trendColor}"/>
        </GenericTile>
      </HBox>
      <!-- Chart Top 10 Clientes — contenido directo, no anidado en VBox -->
      <viz:VizFrame id="topCustomersChart" vizType="bar" height="300px"
                    class="sapUiMediumMargin"/>
    </f:content>
  </f:DynamicPage>
</mvc:View>
```

- `VizFrame` binding con `FlattenedDataset` para chart de clientes
- `NumericContent` con color rojo/verde según tendencia
- Filtros de periodo con `DateRangeSelection`
- Responsive para tablet y desktop

---

## Ejemplo 3: Extensión RAP — Agregar Campo Custom y Validación a Sales Order

**Prompt de entrada:**

```text
Necesito extender el Fiori app estándar de Sales Orders en S/4HANA para agregar:
1. Campo custom "Motivo de urgencia" (ZZ1_MOTIVO_URGENCIA_SDH) en cabecera
2. Validación: si el campo está lleno, la fecha de entrega no puede ser > 3 días hábiles desde hoy
3. El campo debe ser editable al crear y modificar, visible en el detalle
Sistema: S/4HANA 2023 with BAS.
```

**Output esperado del agente:**

- Extension Field via ABAP ADT: `ZZ1_MOTIVO_URGENCIA_SDH` en tabla VBAK
- Extensión del BO transaccional: el campo tiene que llegar a `I_SalesOrderTP`
  (su extension include), no sólo a la vista de lectura `I_SalesOrder`
- Behavior Extension con validación en método `validateUrgencyDate`:

```abap
METHOD validateUrgencyDate.
  "-- EML: ENTITY + campos + claves (WITH) + RESULT; I_SalesOrderTP es la interfaz released del BO
  READ ENTITIES OF I_SalesOrderTP
    ENTITY SalesOrder
      FIELDS ( ZZ1_MOTIVO_URGENCIA_SDH RequestedDeliveryDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(lt_orders).

  "-- Sólo los pedidos con urgencia: un problema con el calendario no puede
  "-- bloquear el guardado de los demás.
  DELETE lt_orders WHERE ZZ1_MOTIVO_URGENCIA_SDH IS INITIAL.
  IF lt_orders IS INITIAL.
    RETURN.
  ENDIF.

  "-- Días hábiles con la API released de calendario de fábrica (no CL_SCAL_API:
  "-- no es released). El ID del calendario es parametrización, no un literal.
  TRY.
      DATA(lo_calendar) = cl_fhc_calendar_runtime=>create_factorycalendar_runtime(
                            iv_factorycalendar_id = zcl_sd_urgency_config=>get_factory_calendar( ) ).
      DATA(lv_max_date) = lo_calendar->add_workingdays_to_date(
                            iv_start                 = cl_abap_context_info=>get_system_date( )
                            iv_number_of_workingdays = 3 ).
    CATCH cx_fhc_runtime INTO DATA(lx_calendar).
      LOOP AT lt_orders INTO DATA(ls_failed).
        APPEND VALUE #( %tky = ls_failed-%tky ) TO failed-salesorder.
        APPEND VALUE #( %tky = ls_failed-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = lx_calendar->get_text( ) ) ) TO reported-salesorder.
      ENDLOOP.
      RETURN.
  ENDTRY.

  LOOP AT lt_orders INTO DATA(ls_order) WHERE RequestedDeliveryDate > lv_max_date.
    APPEND VALUE #( %tky = ls_order-%tky ) TO failed-salesorder.
    APPEND VALUE #(
      %tky = ls_order-%tky
      %element-RequestedDeliveryDate = if_abap_behv=>mk-on
      %msg = new_message_with_text(
               severity = if_abap_behv_message=>severity-error
               text     = 'Con urgencia, fecha entrega max 3 días hábiles' )
    ) TO reported-salesorder.
  ENDLOOP.
ENDMETHOD.
```

- UI Annotation extension para posicionar campo en Fiori Elements Object Page
- Adaptación en BAS: Add Field to Fiori app sin modificar standard

---

## Casos de Uso Frecuentes

- Fiori Elements List Report + Object Page para aprobaciones (PO, SC, Facturas)
- Dashboards analíticos con sap.viz charts y Live Data de CDS Views
- Apps de entrada de datos custom (registro de incidencias, surveys, captura de tiempos)
- Extensiones de apps estándar S/4HANA vía Extension Points y BAdIs de UI
- SAP Build Apps (low-code) para procesos simples de aprobación móvil
