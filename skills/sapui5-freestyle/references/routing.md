# Routing & Navigation — SAPUI5 FreeStyle

## manifest.json — Routing Config

```json
{
  "sap.ui5": {
    "routing": {
      "config": {
        "routerClass": "sap.m.routing.Router",
        "type": "View",
        "viewType": "XML",
        "path": "com.myapp.view",
        "controlId": "app",
        "controlAggregation": "pages",
        "transition": "slide",
        "async": true
      },
      "routes": [
        { "pattern": "",                   "name": "main",     "target": "main"     },
        { "pattern": "detail/{objectId}",  "name": "detail",   "target": "detail"   },
        { "pattern": "create",             "name": "create",   "target": "create"   },
        { "pattern": ":all*:",             "name": "notFound", "target": "notFound" }
      ],
      "targets": {
        "main":     { "id": "main",     "name": "Main"     },
        "detail":   { "id": "detail",   "name": "Detail"   },
        "create":   { "id": "create",   "name": "Create"   },
        "notFound": { "id": "notFound", "name": "NotFound" }
      }
    }
  }
}
```

**Critical rules:**

- `async: true` — ALWAYS
- `routerClass: "sap.m.routing.Router"` — for mobile/responsive apps
- Always include a `notFound` target

## Component.ts — Initialize Router

```typescript
public init(): void {
    super.init();
    this.getRouter().initialize(); // ← MANDATORY, or routing won't work
}
```

## Navigation Patterns

```typescript
// Navigate forward
this.navTo("detail", { objectId: encodeURIComponent(sId) });

// Navigate and replace history (prevents back navigation to this page)
this.navTo("main", {}, true);

// Navigate back
this.onNavBack(); // from BaseController
```

## Detail Controller — Pattern Matched

```typescript
export default class DetailController extends BaseController {

    public onInit(): void {
        const oRoute = this.getRouter().getRoute("detail");
        oRoute!.attachPatternMatched(this._onObjectMatched, this);
    }

    private _onObjectMatched(oEvent: Route$PatternMatchedEvent): void {
        const sObjectId = (oEvent.getParameter("arguments") as { objectId: string }).objectId;

        if (!sObjectId) {
            this.navTo("main");
            return;
        }

        const sDecodedId = decodeURIComponent(sObjectId); // ← always decode
        this._bindView(sDecodedId);
    }

    private _bindView(sId: string): void {
        this.getView()!.bindElement({
            path: `/Orders('${sId}')`,
            events: {
                dataRequested: () => this.getView()!.setBusy(true),
                dataReceived: (oData: object) => {
                    this.getView()!.setBusy(false);
                    if (!(oData as { getParameter: Function }).getParameter("data")) {
                        this.navTo("notFound", {}, true);
                    }
                }
            }
        });
    }
}
```

## URL Parameters — Always Encode/Decode

```typescript
// Encode before navigation
this.navTo("detail", {
    objectId: encodeURIComponent(sOrderNumber) // handles special chars, slashes
});

// Decode after receiving
const sDecoded = decodeURIComponent(sObjectId);
```

## Not Found Handling

```typescript
// In App.controller.ts or Component.ts
this.getRouter().attachBypassed((oEvent) => {
    const sHash = oEvent.getParameter("hash") as string;
    Log.warning(`Route not found: ${sHash}`);
    // The notFound target handles the view automatically
});

this.getRouter().attachRouteMatched(() => {
    // Optional: track navigation analytics
});
```

## App.view.xml — Root Shell

```xml
<mvc:View xmlns:m="sap.m">
    <m:App id="app" autoFocus="false">
        <!-- pages injected by router -->
    </m:App>
</mvc:View>
```
