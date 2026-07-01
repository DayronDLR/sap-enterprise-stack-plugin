# Design Patterns — SAPUI5 FreeStyle

## Themes — Official SAP Only

```html
data-sap-ui-theme="sap_horizon"       <!-- S/4HANA 2023+ recommended -->
data-sap-ui-theme="sap_horizon_dark"
data-sap-ui-theme="sap_horizon_hcb"   <!-- High contrast black -->
data-sap-ui-theme="sap_horizon_hcw"   <!-- High contrast white -->
```

❌ Never override SAP CSS classes or theme variables:

```css
/* NEVER */
.sapMBtn { background-color: red !important; }
:root { --sapBrandColor: #custom; }
```

## Layout Decision Table

| Scenario | Control |
|---|---|
| List + FilterBar as main page | `DynamicPage` |
| Dashboard with tiles/KPIs | `Page` → `VBox`/`HBox` |
| Create/Edit form | `Page` → `Form + ColumnLayout` |
| Master/Detail split | `SplitApp` or `FlexibleColumnLayout` |
| Buttons in toolbar | `HBox` |
| Cards in a grid | `CSSGrid` or `GridContainer` |
| Tabs with content | `IconTabBar` → `VBox` inside each tab |

## DynamicPage — List Report Pattern

```xml
<mvc:View xmlns:f="sap.f" xmlns:m="sap.m" xmlns:fb="sap.ui.comp.filterbar">
    <f:DynamicPage id="dynamicPage" headerExpanded="true">
        <f:header>
            <f:DynamicPageHeader expandedByDefault="true">
                <m:VBox>
                    <!-- SmartFilterBar or simple filter inputs here -->
                    <m:SearchField search=".onSearch" width="20rem"/>
                </m:VBox>
            </f:DynamicPageHeader>
        </f:header>
        <f:title>
            <f:DynamicPageTitle>
                <f:heading>
                    <m:Title text="{i18n>pageTitle}"/>
                </f:heading>
                <f:actions>
                    <m:Button text="{i18n>buttonCreate}" press=".onCreatePress" type="Emphasized"/>
                </f:actions>
            </f:DynamicPageTitle>
        </f:title>
        <f:content>
            <m:Table id="table"
                     items="{/Items}"
                     growing="true"
                     growingThreshold="20"
                     noDataText="{i18n>tableNoData}">
                <m:columns>
                    <m:Column><m:Text text="{i18n>colId}"/></m:Column>
                    <m:Column><m:Text text="{i18n>colName}"/></m:Column>
                    <m:Column><m:Text text="{i18n>colStatus}"/></m:Column>
                </m:columns>
                <m:items>
                    <m:ColumnListItem press=".onItemPress" type="Navigation">
                        <m:cells>
                            <m:Text text="{ID}"/>
                            <m:Text text="{Name}"/>
                            <m:ObjectStatus
                                text="{path: 'Status', formatter: 'Formatter.statusText'}"
                                state="{path: 'Status', formatter: 'Formatter.statusState'}"/>
                        </m:cells>
                    </m:ColumnListItem>
                </m:items>
            </m:Table>
        </f:content>
    </f:DynamicPage>
</mvc:View>
```

> ❌ NEVER: `<Page><content><VBox><Table/>` — the table gets cut off.
> ✅ ALWAYS: `DynamicPage` with table directly in `<f:content>`.

## Form — ColumnLayout (Never SimpleForm)

```xml
<mvc:View xmlns:form="sap.ui.layout.form">
    <form:Form editable="true">
        <form:layout>
            <form:ColumnLayout columnsM="2" columnsL="3" columnsXL="4"/>
        </form:layout>
        <form:formContainers>
            <form:FormContainer title="{i18n>sectionPersonal}">
                <form:formElements>
                    <form:FormElement label="{i18n>labelFirstName}">
                        <form:fields>
                            <Input value="{/firstName}"
                                   required="true"
                                   ariaRequired="true"
                                   placeholder="{i18n>placeholderFirstName}"/>
                        </form:fields>
                    </form:FormElement>
                    <form:FormElement label="{i18n>labelEmail}">
                        <form:fields>
                            <Input value="{/email}" type="Email"/>
                        </form:fields>
                    </form:FormElement>
                    <form:FormElement label="{i18n>labelDepartment}">
                        <form:fields>
                            <Select selectedKey="{/department}">
                                <items>
                                    <core:Item key="IT" text="{i18n>deptIT}"/>
                                    <core:Item key="HR" text="{i18n>deptHR}"/>
                                </items>
                            </Select>
                        </form:fields>
                    </form:FormElement>
                </form:formElements>
            </form:FormContainer>
        </form:formContainers>
    </form:Form>
</mvc:View>
```

Recommended column counts:

- `columnsM="2"` (tablet), `columnsL="3"` (desktop), `columnsXL="4"` (wide)

## Dashboard — KPI Tiles

```xml
<Page title="{i18n>dashboardTitle}">
    <content>
        <VBox class="sapUiResponsiveMargin">
            <HBox wrap="Wrap" justifyContent="SpaceBetween" class="sapUiSmallMarginBottom">
                <GenericTile class="sapUiTinyMarginBegin sapUiTinyMarginTop"
                             header="{i18n>kpiSalesTitle}"
                             subheader="{i18n>kpiSalesSubtitle}"
                             press=".onKpiPress">
                    <tileContent>
                        <TileContent unit="{i18n>kpiCurrency}">
                            <content>
                                <NumericContent
                                    value="{/kpi/totalSales}"
                                    indicator="{/kpi/salesTrend}"
                                    valueColor="{/kpi/salesColor}"
                                    scale="{i18n>kpiScale}"
                                    withMargin="false"/>
                            </content>
                        </TileContent>
                    </tileContent>
                </GenericTile>
            </HBox>
            <!-- Table with recent items below -->
            <Table items="{/recentItems}" growing="true" growingThreshold="10">
                <!-- columns -->
            </Table>
        </VBox>
    </content>
</Page>
```

## Dialog — Always Lazy (Fragment.load)

```typescript
// ✅ CORRECT: load on demand, reuse after first load
public async onOpenDialog(): Promise<void> {
    if (!this._oDialog) {
        this._oDialog = await Fragment.load({
            id: this.getView()!.getId(),
            name: "com.myapp.view.fragments.ConfirmDialog",
            controller: this
        });
        this.getView()!.addDependent(this._oDialog as Control);
    }
    (this._oDialog as Dialog).open();
}

// ✅ MANDATORY: clean up in onExit
public onExit(): void {
    if (this._oDialog) {
        (this._oDialog as Dialog).destroy();
        this._oDialog = undefined;
    }
}
```

## Deprecated Controls — Never Use

```
❌ sap.ui.commons.*   (obsolete library)
❌ sap.ui.ux3.*       (obsolete library)
❌ sap.ca.*           (obsolete library)
❌ sap.m.SimpleForm   (use Form + ColumnLayout)
❌ document.createElement() — never raw DOM
```
