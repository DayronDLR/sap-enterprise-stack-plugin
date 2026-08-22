# REFERENCIA TECNICA -- Smart Controls en FreeStyle (OData V2)

> **Contenido**: SmartFilterBar, SmartTable, SmartField, SmartForm -- configuracion obligatoria, layout patterns, manifest.json para OData V2, y OData metadata requerido.
> **Fuente**: Extraido de `agents/04-fiori-ui5/system_prompt.md` para lazy-load.
> **Cuanto consultar**: Cuando se necesiten Smart Controls individuales en SAPUI5 FreeStyle (NO Fiori Elements). Tipicamente apps con OData V2.

---

> **NOTA**: Esta seccion cubre Smart Controls **individuales** en SAPUI5 FreeStyle. NO es Fiori Elements.

## SmartFilterBar -- Configuracion Obligatoria

```xml
<!-- Propiedades obligatorias: entitySet, persistencyKey, search -->
<smartFilterBar:SmartFilterBar
    id="smartFilterBar"
    entitySet="Products"
    persistencyKey="myApp_ProductFilters_v1"
    search="onSearch"
    xmlns:smartFilterBar="sap.ui.comp.smartfilterbar">
</smartFilterBar:SmartFilterBar>
```

## SmartTable -- Configuracion Obligatoria

```xml
<!-- Propiedades obligatorias: entitySet, smartFilterId, tableType, enableAutoBinding -->
<smartTable:SmartTable
    id="smartTable"
    entitySet="Products"
    smartFilterId="smartFilterBar"
    tableType="ResponsiveTable"
    useExportToExcel="true"
    enableAutoBinding="true"
    showRowCount="true"
    header="Products"
    xmlns:smartTable="sap.ui.comp.smarttable">
</smartTable:SmartTable>
```

**CRITICO -- Layout:** Nunca envolver SmartFilterBar + SmartTable en VBox. Usar contenido directo en Page o DynamicPage:

```xml
<!-- CORRECTO: Sin VBox contenedor -->
<Page>
    <content>
        <smartFilterBar:SmartFilterBar id="smartFilterBar" entitySet="Products"/>
        <smartTable:SmartTable entitySet="Products" smartFilterId="smartFilterBar" enableAutoBinding="true"/>
    </content>
</Page>

<!-- MEJOR: Con DynamicPage (patron Fiori) -->
<f:DynamicPage>
    <f:header>
        <f:DynamicPageHeader pinnable="true">
            <smartFilterBar:SmartFilterBar id="smartFilterBar" entitySet="Products"/>
        </f:DynamicPageHeader>
    </f:header>
    <f:content>
        <smartTable:SmartTable entitySet="Products" smartFilterId="smartFilterBar" enableAutoBinding="true"/>
    </f:content>
</f:DynamicPage>
```

## SmartTable -- onBeforeRebindTable

```javascript
onBeforeRebindTable: function(oEvent) {
    const mBindingParams = oEvent.getParameter("bindingParams");
    mBindingParams.filters.push(new Filter("Status", FilterOperator.EQ, "Active"));
    mBindingParams.sorter.push(new Sorter("ProductName", false));
    mBindingParams.parameters.select = "ProductID,ProductName,Price";
}
```

## SmartField y SmartForm

```xml
<!-- SmartField detecta tipo desde OData metadata automaticamente -->
<smartForm:SmartForm id="productForm" editable="true" title="Product Details">
    <smartForm:Group label="General Information">
        <smartForm:GroupElement label="Product Name">
            <smartField:SmartField value="{ProductName}" editable="true" mandatory="true"/>
        </smartForm:GroupElement>
        <smartForm:GroupElement label="Price">
            <smartField:SmartField value="{Price}" editable="true"/>
        </smartForm:GroupElement>
    </smartForm:Group>
</smartForm:SmartForm>
```

## manifest.json para Smart Controls (OData V2)

```json
{
  "sap.app": {
    "dataSources": {
      "mainService": {
        "uri": "/sap/opu/odata/sap/MY_SERVICE/",
        "type": "OData",
        "settings": {
          "odataVersion": "2.0",
          "localUri": "localService/metadata.xml",
          "annotations": ["annotation0"]
        }
      },
      "annotation0": {
        "type": "ODataAnnotation",
        "uri": "annotations/annotation.xml"
      }
    }
  },
  "sap.ui5": {
    "models": {
      "": {
        "dataSource": "mainService",
        "preload": true,
        "settings": {
          "defaultBindingMode": "TwoWay",
          "defaultCountMode": "Inline",
          "refreshAfterChange": false
        }
      }
    }
  }
}
```

## OData Metadata requerido para Smart Controls

```xml
<EntityType Name="Product">
    <Property Name="ProductID" Type="Edm.String" Nullable="false"/>
    <Property Name="ProductName" Type="Edm.String"
              sap:label="Product Name" sap:filterable="true" sap:sortable="true"/>
    <Property Name="Price" Type="Edm.Decimal"
              sap:label="Price" sap:unit="Currency" sap:filterable="true"/>
    <Property Name="Currency" Type="Edm.String" sap:semantics="currency-code"/>
    <Property Name="Status" Type="Edm.String"
              sap:label="Status" sap:value-list="fixed-values"/>
</EntityType>
```
