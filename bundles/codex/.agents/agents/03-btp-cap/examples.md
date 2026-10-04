# ☁️ AGENTE 03 — Ejemplos de Uso

## Ejemplo 1: App CAP para Gestión de Aprobaciones de Gastos

**Prompt de entrada:**

```text
Crea una aplicación CAP (Node.js) en SAP BTP para gestionar aprobaciones de gastos de viaje.
Los empleados crean solicitudes con monto, destino y propósito.
El manager directo recibe notificación y aprueba/rechaza desde Fiori.
Integrar con SAP S/4HANA para obtener el manager desde HR (API EmployeeProfile).
Plataforma: SAP BTP Cloud Foundry. Auth: XSUAA. BD: HANA Cloud.
```

**Output esperado del agente:**

**schema.cds:**

```cds
namespace travel.approval;
using { managed, cuid, sap.common.CodeList } from '@sap/cds/common';

entity TravelRequests : cuid, managed {
  employee    : String(12) @mandatory;
  manager     : String(12);
  destination : String(100) @mandatory;
  purpose     : String(500) @mandatory;
  amount      : Decimal(15,2) @mandatory;
  currency    : String(3) default 'MXN';
  status      : String(1) enum { Draft='D'; Pending='P'; Approved='A'; Rejected='R'; }
               default 'D';
  rejectReason: String(500);
  items       : Composition of many TravelItems on items.request = $self;
}

entity TravelItems : cuid {
  request   : Association to TravelRequests;
  category  : String(20); // Flight, Hotel, Meals, Other
  amount    : Decimal(15,2);
  receipt   : LargeBinary @Core.MediaType: 'application/pdf';
}
```

**srv/approval-service.cds:**

```cds
using travel.approval as db from '../db/schema';

@requires: 'authenticated-user'
service TravelApprovalService @(path: '/api/v1') {

  @(restrict: [{ grant: ['READ','CREATE','UPDATE'], to: 'Employee' },
               { grant: 'READ', where: 'employee = $user', to: 'Employee' }])
  entity TravelRequests as projection on db.TravelRequests
    actions {
      @(requires: 'Employee')
      action submit() returns TravelRequests;

      @(requires: 'Manager')
      action approve() returns TravelRequests;

      @(requires: 'Manager')
      action reject(reason: String @mandatory) returns TravelRequests;
    };
}
```

**srv/approval-service.js (handlers clave):**

```javascript
const cds = require('@sap/cds');

module.exports = class TravelApprovalService extends cds.ApplicationService {
  async init() {
    // Obtener manager desde S/4HANA HR API al hacer submit
    this.on('submit', 'TravelRequests', async (req) => {
      const { ID } = req.params[0];
      // Llamar Remote Service S/4HANA
      const S4HR = await cds.connect.to('S4HANA_HR');
      // CQL parametriza la clave (nada de interpolar el usuario en la URL OData)
      const perfil = await S4HR.run(
        SELECT.one.from('EmployeeProfile').columns('ManagerID')
          .where({ PersonWorkAgreement: req.user.id }));
      const manager = perfil?.ManagerID;
      if (!manager) return req.reject(422, 'MANAGER_NOT_FOUND');
      // Transición atómica: sólo desde borrador. Dos submits concurrentes, o uno
      // posterior a una aprobación, no devuelven el registro a 'P'.
      const n = await UPDATE('travel.approval.TravelRequests')
        .set({ status: 'P', manager }).where({ ID, status: 'D' });
      if (n !== 1) return req.reject(409, 'TRAVEL_STATE_CHANGED');
      // Notificar recién cuando la tx commitea: si hace rollback, no sale el evento
      req.on('succeeded', () => this.emit('TravelSubmitted', { requestId: ID, managerId: manager })
        .catch((err) => cds.log('travel').error('No se pudo emitir TravelSubmitted', { ID, err: err.message })));
      return this.read('TravelRequests', ID);
    });
    return super.init();
  }
};
```

- `xs-security.json` con roles Employee, Manager y scopes correspondientes
- `mta.yaml` completo: app srv + db deployer + approuter + HANA + XSUAA
- Suscripción a Event Mesh para enviar email al manager via SAP Alert Notification
- Unit tests con `cds.test().in(__dirname,'..').run('test/approval.test.js')`

---

## Ejemplo 2: Extensión Clean Core — Side-by-Side en BTP para Validación de Pagos

**Prompt de entrada:**

```text
Necesito una extensión side-by-side en SAP BTP para validar pagos contra una lista negra
de proveedores del área de compliance antes de que SAP los procese.
Flujo: SAP S/4HANA dispara evento al crear un pago → BTP valida → responde bloqueado/aprobado.
La lista negra se mantiene en la app BTP (HANA Cloud). CAP Node.js.
```

**Output esperado del agente:**

- Arquitectura completa:

```text
S/4HANA (BAdI FI_PAYMENT_PROCESSING)
    │ POST /validate-payment (mTLS)
    ▼
SAP BTP CAP Service (PaymentValidationSrv)
    │
    ├── db: BlacklistEntry (HANA Cloud HDI)
    │   ├── entity: SupplierBlacklist { supplier, reason, addedBy, validUntil }
    │   └── entity: ValidationLog { paymentRef, supplier, result, timestamp }
    │
    └── srv: actions
        ├── POST /validate → check supplier in BlacklistEntry → return { allowed: bool, reason }
        └── POST /blacklist → add supplier (requires 'Compliance' role)
```

- ABAP BAdI que llama al servicio BTP via HTTP RFC (SAP Destination)
- CAP service con `@requires: 'system-user'` para la llamada S4 (mTLS)
- Logging completo en ValidationLog para auditoría
- Fiori app de mantenimiento de lista negra (roles: Compliance, Viewer)
- Deploy con MTA en Cloud Foundry, HANA Cloud HDI container

---

## Ejemplo 3: Aplicación Multi-Tenant SaaS en BTP (CAP + mtxs)

**Prompt de entrada:**

```text
Diseña la arquitectura de una aplicación SaaS multi-tenant en SAP BTP con CAP.
La app es un módulo de gestión de contratos para clientes del SAP Store.
Cada cliente tiene su propio HDI container aislado.
Onboarding automático de nuevos tenants.
Plataforma: BTP Cloud Foundry con SAP BTP SaaS Provisioning Service.
```

**Output esperado del agente:**

**package.json (configuración CAP multitenancy):**

```json
{
  "cds": {
    "requires": {
      "multitenancy": true,
      "extensibility": true,
      "toggles": true,
      "[production]": {
        "db": { "kind": "hana-cloud" },
        "auth": { "kind": "xsuaa" }
      }
    },
    "mtx": {
      "element-prefix": "Z_",
      "namespace-blacklist": ["com.sap", "sap."],
      "entity-whitelist": ["Contracts", "ContractItems"]
    }
  }
}
```

**Flujo de onboarding de nuevo tenant:**

1. Cliente subscribe desde BTP Cockpit / SAP Store
2. SaaS Provisioning Service llama `PUT /mtx/v1/provisioning/tenant/{tenantId}`
3. CAP `@sap/mtxs` crea HDI container isolado para el tenant
4. Schema migrations se aplican automáticamente
5. Tenant-specific data seed si aplica
6. Respuesta: tenant listo en < 5 minutos

- `mta.yaml` con módulos: srv, mtx-sidecar, db-deployer, approuter
- xs-security.json con `tenant-mode: shared`
- Estrategia de upgrades: rolling deployment sin downtime
- Monitoring por tenant: requests, errores, consumo de HANA

---

## Casos de Uso Frecuentes

- Apps de aprobación workflow (gastos, vacaciones, requisiciones) con CAP + Fiori
- Extensiones side-by-side para validaciones de negocio complejas que no deben ir on-stack
- Microservicios en SAP BTP Kyma para integración con APIs externas (Azure, AWS)
- SaaS products construidos sobre BTP para distribución vía SAP Store
- Apps CAP que consumen SAP S/4HANA APIs de Business Accelerator Hub (read-only + write-back)
