# Integración CAP + Fiori y despliegue on-premise vs BTP

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## CAP + Fiori Integration (BTP)

### CDS Annotations en CAP para Fiori Elements

```cds
// srv/service.cds — anotaciones Fiori dentro de CAP
annotate OrderService.Orders with @(
  UI: {
    HeaderInfo: {
      TypeName      : 'Order',
      TypeNamePlural: 'Orders',
      Title         : { Value: orderNo },
      Description   : { Value: status }
    },
    LineItem: [
      { Value: orderNo,     Label: 'Order No.',   Position: 10 },
      { Value: status,      Label: 'Status',      Position: 20 },
      { Value: totalAmount, Label: 'Total',        Position: 30 },
      { $Type: 'UI.DataFieldForAction', Action: 'OrderService.approve',
        Label: 'Approve', Position: 40 }
    ],
    SelectionFields: [ orderNo, status, createdAt ],
    Facets: [{
      $Type : 'UI.ReferenceFacet',
      Target: '@UI.FieldGroup#General',
      Label : 'General'
    },{
      $Type : 'UI.ReferenceFacet',
      Target: 'items/@UI.LineItem',
      Label : 'Items'
    }],
    FieldGroup #General: {
      Data: [
        { Value: orderNo },
        { Value: status },
        { Value: totalAmount },
        { Value: createdAt }
      ]
    }
  }
);
```

### xs-app.json (Approuter) para Fiori en BTP

```json
{
  "welcomeFile": "/index.html",
  "authenticationMethod": "route",
  "routes": [
    {
      "source"      : "^/api/(.*)$",
      "target"      : "/api/$1",
      "destination" : "srv-api",
      "authenticationType": "xsuaa"
    },
    {
      "source"      : "^(.*)$",
      "target"      : "$1",
      "service"     : "html5-apps-repo-rt",
      "authenticationType": "xsuaa"
    }
  ]
}
```

### Fiori App en MTA (BTP)

```yaml
# mta.yaml — módulo UI5 en BTP
- name: my-app-ui
  type: html5
  path: app/orders
  build-parameters:
    build-result: dist
    builder: custom
    commands:
      - npm install
      - npm run build:cf
    supported-platforms: []

- name: my-app-ui-deployer
  type: com.sap.application.content
  path: .
  requires:
    - name: my-app-html5-repo-host
      parameters:
        content-target: true
  build-parameters:
    build-result: resources
    requires:
      - name: my-app-ui
        target-path: resources/
        artifacts:
          - dist/my-app-orders.zip
```

## Despliegue — On-Premise vs BTP

### On-Premise S/4HANA

```text
1. Generar app con Fiori Tools (VS Code / BAS)
2. Build: npm run build
3. Desplegar en ABAP:
   - Transacción: /UI5/UI5_REPOSITORY_LOAD (para BSP app)
   - O: abapGit / gCTS (preferido en S/4HANA 2020+)
4. Activar servicio ICF:
   - Transacción SICF → /sap/bc/ui5_ui5/[namespace]/[app]
5. Configurar Launchpad (Fiori Launchpad Designer):
   - Transacción: /UI2/FLPD_CONF (On-Premise Launchpad Designer)
   - Crear Business Catalog → Tile → Target Mapping
6. Asignar a Business Role (PFCG):
   - Role: Z_BR_[NOMBRE]
   - Catalog: Z_BC_[NOMBRE]
```

### BTP con SAP Build Work Zone

```text
1. Desplegar app en HTML5 Application Repository (via MTA):
   cf deploy my-app.mtar
2. Configurar en SAP Build Work Zone (Advanced Edition):
   - Content Manager → Add app desde HTML5 Repository
   - Asignar a Role y Site
3. Acceso via Work Zone site URL
4. XSUAA: roles definidos en xs-security.json → asignados en BTP Cockpit
```

### ABAP Backend con Fiori (On-Premise): Publicar OData

```text
"-- Activar servicio OData V4 (RAP):
"-- 1. En Service Binding → Publish
"-- 2. Activar en /IWFND/V4_ADMIN (o SICF para REST)
"-- 3. URL On-Premise: /sap/opu/odata4/[namespace]/[binding]/[version]/

"-- Para OData V2 (legacy):
"-- Activar en /IWFND/MAINT_SERVICE
"-- URL: /sap/opu/odata/sap/[SERVICE_NAME]/
```
