# CAP: expertise técnico y arquitectura estándar del proyecto

> Referencia del agente BTP/CAP. Se lee bajo demanda.

## EXPERTISE TÉCNICO

### SAP CAP (Cloud Application Programming Model)

- CDS (Core Data Services): entidades, asociaciones, proyecciones, vistas, anotaciones
- Servicios CAP: definición con .cds, implementación con Node.js (cds.service) y Java (CqnService)
- **TypeScript en handlers**: `@cap-js/cds-typer` para tipos generados desde CDS, type-safe service handlers (recomendado para proyectos nuevos Node.js)
- **CAP plugins** (`cds-plugin`): ecosistema `@cap-js/*` (audit-logging, change-tracking, attachments, telemetry, postgres/sqlite) — preferir plugin oficial sobre código custom
- Handlers: on(), before(), after() — CRUD y acciones personalizadas
- Eventos: emitir y suscribirse con cds.emit() / srv.on()
- Validaciones de datos y managed associations
- Draft handling para apps Fiori con estado borrador
- Multi-tenancy en SaaS (cds.env.requires.multitenancy)
- Remote Services: consumo de S/4HANA APIs y SAP Ariba via service bindings
- CAP with SAP Event Mesh / Advanced Event Mesh: publicar/consumir eventos cloud
- Testing: @sap/cds/test, jest/vitest, supertest; **hybrid testing** (`cds bind` para correr local contra servicios BTP reales)

### SAP BTP Plataforma

- Cloud Foundry (CF): manifest.yml, cf CLI, Buildpacks (Node.js, Java)
- Kyma Runtime: Kubernetes nativo, Helm charts, Function deployment
- BTP Cockpit: subaccounts, spaces, service instances, bindings
- Multi-Target Application (MTA): mta.yaml, mbt build, cf deploy
- SAP Approuter: autenticación, routing, xs-app.json
- SAP XSUAA: OAuth 2.0, roles, scopes, JWT tokens, xs-security.json
- SAP Cloud Identity Services (IAS/IPS): IdP central; patrón recomendado IAS como autenticación + XSUAA/IAS para tokens de app (ver agente 07-basis)
- SAP Connectivity Service: Cloud Connector, on-premise access, Principal Propagation
- SAP Destination Service: destinos HTTP, RFC, Mail
- SAP HTML5 Application Repository: hosting de apps Fiori/UI5
- SAP Business Application Studio (BAS) / SAP Build Code: dev spaces, templates
- SAP Build Work Zone (Standard / Advanced): launchpad, business sites, CDM

### Servicios BTP Clave

- SAP HANA Cloud: HDI containers, deploy via @sap/hdi-deploy
- SAP Event Mesh: topics, queues, webhooks, amqp/mqtt
- SAP Alert Notification Service: alertas proactivas
- SAP Object Store Service: S3-compatible para blobs
- SAP Audit Log Service: trazabilidad regulatoria
- SAP Feature Flags Service: toggles para releases
- SAP Authorization & Trust Management (XSUAA)
- SAP AI Core / AI Launchpad: ML models, inferencing

### Integración con SAP S/4HANA (Clean Core)

- SAP S/4HANA Cloud APIs (Business Hub): consumir desde CAP
- SAP Graph: unified API layer para SAP ecosystem
- SAP OData V4: consumir services de S4 desde CAP Remote Service
- RFC/BAPI via SAP Cloud Connector (solo fallback legacy)
- Change Data Capture (CDC) con SAP Event Mesh

### Herramientas y CLI

- @sap/cds-dk: cds init, cds add, cds watch, cds deploy
- CF CLI: cf push, cf bind-service, cf env
- BTP CLI: btp login, btp create instance
- SAP MTA Build Tool (mbt): mbt build
- VS Code / BAS con SAP CDS Language Support
- npm / Maven para gestión de dependencias

## ARQUITECTURA CAP ESTÁNDAR

### Estructura de Proyecto

```text
my-cap-app/
├── app/                    # UI5/Fiori frontend
│   └── fiori-app/
├── db/                     # Data model layer
│   ├── schema.cds          # Entidades & Domain model
│   ├── data/               # CSV seed data (local dev)
│   └── src/                # HANA HDI artifacts (nativas)
├── srv/                    # Service layer
│   ├── service.cds         # Service definitions
│   ├── service.js          # Node.js handlers
│   └── external/           # Remote service CSN imports
├── mta.yaml                # MTA descriptor
├── xs-security.json        # XSUAA roles & scopes
├── package.json            # Dependencies & scripts
└── .cdsrc.json             # CAP config profile
```

### Patron de Servicio CAP

```cds
// db/schema.cds
namespace my.app;
using { managed, cuid } from '@sap/cds/common';

entity Orders : cuid, managed {
  orderNo     : String(20) @mandatory;
  status      : String(1) enum { New='N'; Approved='A'; Rejected='R'; };
  items       : Composition of many OrderItems on items.order = $self;
  totalAmount : Decimal(15,2);
}

entity OrderItems : cuid {
  order    : Association to Orders;
  material : String(18);
  quantity : Decimal(13,3);
  price    : Decimal(15,2);
}
```

```cds
// srv/service.cds
using my.app as db from '../db/schema';

service OrderService @(path:'/api/v1/orders') {
  entity Orders as projection on db.Orders
    actions {
      action approve() returns Orders;
      action reject(reason: String);
    };
  entity OrderItems as projection on db.OrderItems;
}
```

```javascript
// srv/service.js
const cds = require('@sap/cds');

module.exports = class OrderService extends cds.ApplicationService {
  init() {
    this.on('approve', 'Orders', async (req) => {
      const { ID } = req.params[0];
      await UPDATE('my.app.Orders', ID).with({ status: 'A' });
      return this.read('Orders', ID);
    });

    this.before('CREATE', 'Orders', (req) => {
      if (!req.data.orderNo) req.error(400, 'OrderNo es obligatorio');
    });

    return super.init();
  }
};
```

### MTA Descriptor (mta.yaml)

```yaml
ID: my-cap-app
version: 1.0.0
modules:
  - name: my-cap-app-srv
    type: nodejs
    path: gen/srv
    requires:
      - name: my-cap-app-db
      - name: my-cap-app-xsuaa
      - name: my-cap-app-destination
    provides:
      - name: srv-api
        properties:
          srv-url: ${default-url}

  - name: my-cap-app-db-deployer
    type: hdb
    path: gen/db
    requires:
      - name: my-cap-app-db

  - name: my-cap-app-approuter
    type: approuter.nodejs
    path: app/
    requires:
      - name: my-cap-app-xsuaa
      - name: srv-api
        group: destinations
        properties:
          name: srv-api
          url: ~{srv-url}
          forwardAuthToken: true

resources:
  - name: my-cap-app-xsuaa
    type: org.cloudfoundry.managed-service
    parameters:
      service: xsuaa
      service-plan: application
      path: ./xs-security.json

  - name: my-cap-app-db
    type: com.sap.xs.hdi-container
    parameters:
      service: hana
      service-plan: hdi-shared
```
