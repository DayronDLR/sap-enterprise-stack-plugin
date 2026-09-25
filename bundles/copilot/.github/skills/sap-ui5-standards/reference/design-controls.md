# SAPUI5 Design & Controls - Reglas de Diseño

> **APLICABILIDAD**: Todas las aplicaciones SAPUI5 FreeStyle
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%

## 1. CSS Personalizado — Regla Cero

```css
/* ❌ PROHIBIDO ABSOLUTAMENTE: modificar CSS interno de controles UI5 */
.sapMBtn { background-color: red !important; }
.sapMList .sapMLIB { padding: 20px !important; }
```

```javascript
// ❌ PROHIBIDO: manipular DOM interno de controles
this.byId("myButton").getDomRef().style.backgroundColor = "red";
this.byId("myButton").$().addClass("custom-style");
```

```css
/* ✅ PERMITIDO: CSS solo en contenedores de aplicación propios */
.myAppContainer { margin: 1rem; padding: 1rem; }
.myCustomLayout { display: flex; justify-content: space-between; }
```

## 2. Temas Oficiales — Solo SAP

```html
<!-- ✅ Temas oficiales permitidos -->
data-sap-ui-theme="sap_horizon"       <!-- Recomendado S/4HANA 2023+ -->
data-sap-ui-theme="sap_horizon_dark"
data-sap-ui-theme="sap_horizon_hcb"  <!-- Alto contraste negro -->
data-sap-ui-theme="sap_horizon_hcw"  <!-- Alto contraste blanco -->
data-sap-ui-theme="sap_fiori_3"
```

```css
/* ❌ PROHIBIDO: Sobreescribir variables de tema SAP */
:root {
    --sapBrandColor: #custom-color;
    --sapHighlightColor: #another-color;
}
```

## 3. Controles Prohibidos

```javascript
// ❌ NUNCA usar controles deprecated
- sap.ui.commons.*   // Biblioteca obsoleta
- sap.ui.ux3.*      // Biblioteca obsoleta
- sap.ca.*          // Biblioteca obsoleta

// ❌ NUNCA crear elementos HTML nativos directamente
document.createElement("div");    // ❌
document.createElement("input");  // ❌
```

## 4. ARIA Labels Obligatorios

```xml
<!-- ✅ OBLIGATORIO: Todos los controles interactivos -->
<Button text="{i18n>buttonSave}"
        tooltip="{i18n>buttonSaveTooltip}"
        ariaLabelledBy="saveButtonLabel"/>

<Label id="saveButtonLabel" text="{i18n>saveButtonAriaLabel}" visible="false"/>

<!-- ✅ OBLIGATORIO: Roles semánticos en contenedores -->
<Panel accessibleRole="Region" ariaLabelledBy="panelHeader">
    <headerToolbar>
        <Toolbar>
            <Title id="panelHeader" text="{i18n>userInfoTitle}"/>
        </Toolbar>
    </headerToolbar>
</Panel>
```

## 5. Layouts — VBox/HBox — Regla Crítica

### ❌ NUNCA: VBox como contenedor principal de Page con tablas

```xml
<!-- ❌ CAUSA tabla cortada a la mitad -->
<Page>
    <content>
        <VBox>
            <Panel>Filter Bar</Panel>
            <Table/>  <!-- Se corta -->
        </VBox>
    </content>
</Page>
```

### ✅ CORRECTO: Contenido directo en Page o DynamicPage

```xml
<!-- ✅ Contenido directo -->
<Page>
    <content>
        <Panel>Filter Bar</Panel>
        <Table/>  <!-- Ocupa todo el espacio -->
    </content>
</Page>

<!-- ✅ RECOMENDADO: DynamicPage para List Report -->
<f:DynamicPage>
    <f:header>
        <f:DynamicPageHeader>
            <!-- FilterBar aquí -->
        </f:DynamicPageHeader>
    </f:header>
    <f:content>
        <Table/>  <!-- Ocupa todo el espacio -->
    </f:content>
</f:DynamicPage>
```

### Tabla de Decisión VBox/HBox

| Escenario | Usar VBox/HBox | Alternativa |
|---|---|---|
| **Contenedor principal de Page** | ❌ NO | Contenido directo |
| **Table + FilterBar** | ❌ NO | DynamicPage |
| **Organizar filtros en formulario** | ✅ SÍ | FlexBox |
| **Botones en toolbar** | ✅ SÍ | HBox |
| **Cards/Tiles en dashboard** | ✅ SÍ | Grid, FlexBox |
| **Header de página** | ✅ SÍ | VBox |
| **Contenido dentro de tabs** | ✅ SÍ | VBox |

### Solución para Scroll Extra

```xml
<!-- ❌ VBox con height fijo genera scroll extra -->
<VBox height="100%"><Table/></VBox>

<!-- ✅ FlexBox con fitContainer -->
<FlexBox fitContainer="true" direction="Column"><Table/></FlexBox>
```

> **Referencia Smart Controls completa** (SmartFilterBar, SmartTable, SmartField, SmartForm, manifest.json, OData metadata): ver `agents/04-fiori-ui5/system_prompt.md` sección "REFERENCIA TÉCNICA — Smart Controls en FreeStyle".

## 6. Formularios — Form + ColumnLayout (Regla Obligatoria)

### ❌ NUNCA usar SimpleForm

```xml
<!-- ❌ PROHIBIDO: SimpleForm no proporciona control adecuado de layout responsivo -->
<form:SimpleForm editable="true" layout="ResponsiveGridLayout">
    <Label text="{i18n>nameLabel}"/>
    <Input value="{/name}"/>
</form:SimpleForm>
```

### ✅ SIEMPRE usar Form con ColumnLayout

```xml
<!-- ✅ OBLIGATORIO: Form + ColumnLayout para diseño responsive correcto -->
<form:Form editable="true">
    <form:layout>
        <form:ColumnLayout
            columnsM="2"
            columnsL="3"
            columnsXL="4"/>
    </form:layout>
    <form:formContainers>
        <form:FormContainer title="{i18n>personalDataTitle}">
            <form:formElements>
                <form:FormElement label="{i18n>nameLabel}">
                    <form:fields>
                        <Input value="{/name}" required="true"/>
                    </form:fields>
                </form:FormElement>
                <form:FormElement label="{i18n>emailLabel}">
                    <form:fields>
                        <Input value="{/email}" type="Email"/>
                    </form:fields>
                </form:FormElement>
            </form:formElements>
        </form:FormContainer>
    </form:formContainers>
</form:Form>
```

### Namespace requerido

```xml
<!-- Agregar al tag raíz de la View -->
<mvc:View
    xmlns:form="sap.ui.layout.form"
    ...>
```

### Columnas por defecto (oficiales SAP)

| Breakpoint | Columnas recomendadas |
|---|---|
| **M** (tablet) | 2 |
| **L** (desktop) | 3 |
| **XL** (wide desktop) | 4 |

### Tabla de Decisión Form

| Escenario | Control correcto |
|---|---|
| **Formulario editable** | `Form` + `ColumnLayout` |
| **Formulario de solo lectura** | `Form` + `ColumnLayout` con `editable="false"` |
| **Formulario simple (1 columna)** | `Form` + `ColumnLayout` `columnsM="1"` |
| ~~SimpleForm~~ | ❌ NUNCA |
