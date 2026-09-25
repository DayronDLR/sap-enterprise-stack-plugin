# Autorizaciones y testing de apps Fiori

> Material de referencia del agente Fiori/UI5. Se lee bajo demanda.

## Autorizaciones

### On-Premise (PFCG)

```text
Objeto de autorización Fiori: S_START (transacción Fiori ID)
Objeto OData: S_SERVICE (nombre del servicio)
Objeto de negocio: según módulo (V_VBAK_AAT, F_BKPF_BUK, etc.)

Role structure:
Z_BR_[MÓDULO]_[ROL]        ← Business Role (composite)
  └─ Z_BC_[MÓDULO]_[NOMBRE] ← Business Catalog (con tiles)
       └─ Z_BG_[NOMBRE]     ← Business Group (organización visual)
```

### BTP (xs-security.json)

```json
{
  "xsappname": "my-app",
  "tenant-mode": "dedicated",
  "scopes": [
    { "name": "$XSAPPNAME.Viewer",  "description": "View orders" },
    { "name": "$XSAPPNAME.Approver","description": "Approve orders" }
  ],
  "role-templates": [
    {
      "name": "Viewer",
      "description": "Order viewer",
      "scope-references": ["$XSAPPNAME.Viewer"]
    },
    {
      "name": "Approver",
      "description": "Order approver",
      "scope-references": ["$XSAPPNAME.Viewer","$XSAPPNAME.Approver"]
    }
  ]
}
```

> **Autenticación con IAS (2025+):** XSUAA gestiona la **autorización** (scopes /
> role-collections); la **autenticación** debe centralizarse en **SAP Cloud Identity
> Services (IAS)** como IdP corporativo (SSO/MFA), con trust IAS ↔ Subaccount. En apps
> nuevas, configurar IAS como IdP del Approuter; XSUAA puro queda para escenarios legacy.
> Detalle del patrón y migración en el agente **07-basis-security** (Cloud Identity).

## Testing

### OPA5 (Integration Tests)

```javascript
// test/integration/pages/OrderListPage.js
sap.ui.define(["sap/ui/test/Opa5","sap/ui/test/actions/Press","sap/ui/test/matchers/Properties"],
function(Opa5, Press, Properties) {
  Opa5.createPageObjects({
    onTheOrderListPage: {
      actions: {
        iClickTheFirstOrder: function() {
          return this.waitFor({
            controlType: "sap.m.ObjectListItem",
            matchers   : new Properties({ title: "1000000001" }),
            actions    : new Press(),
            errorMessage: "Order not found"
          });
        }
      },
      assertions: {
        iSeeTheOrderList: function() {
          return this.waitFor({
            id: "orderList",
            success: oList => Opa5.assert.ok(oList, "List rendered"),
            errorMessage: "List not visible"
          });
        }
      }
    }
  });
});
```

### wdi5 (E2E con WebdriverIO, recomendado BTP)

```javascript
// test/e2e/orderList.test.js
const { wdi5 } = require("wdi5");
describe("Order List", () => {
  it("should show orders and navigate to detail", async () => {
    const list = await browser.asControl({ selector: { id: "orderList" } });
    expect(await list.getItems()).toHaveLength(10);
    await list.getItems()[0].press();
    expect(await browser.getUrl()).toContain("orderDetail");
  });
});
```
