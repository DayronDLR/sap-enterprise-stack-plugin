# CAP Integration — SAPUI5 FreeStyle

## Mandatory Project Structure

```
my-cap-project/            ← CAP root
├── app/                   ← UI5 apps go HERE
│   └── my-ui5-app/
│       ├── webapp/
│       │   ├── Component.ts
│       │   ├── manifest.json
│       │   └── ...
│       ├── package.json
│       └── ui5.yaml
├── db/
│   └── schema.cds
├── srv/
│   └── service.cds
├── package.json           ← cds-plugin-ui5 installed HERE (root)
└── .cdsrc.json
```

❌ Never place UI5 app outside `app/`:

```
my-cap-project/
├── my-ui5-app/   ← NEVER in CAP root
├── frontend/     ← NEVER
├── ui/           ← NEVER
```

## cds-plugin-ui5 — Install in CAP Root

```bash
# ✅ ALWAYS in CAP root
cd my-cap-project/
npm install --save-dev cds-plugin-ui5
```

```json
// package.json at CAP ROOT — devDependencies
{
  "devDependencies": {
    "cds-plugin-ui5": "^0.x.x",
    "@sap/cds-dk": "^8.x.x"
  }
}
```

❌ Never install in the UI5 app folder:

```bash
# ❌ WRONG
cd my-cap-project/app/my-ui5-app/
npm install cds-plugin-ui5
```

## Development — cds watch Only

```bash
# ✅ ALWAYS start from CAP root
cd my-cap-project/
cds watch
```

`cds watch` with `cds-plugin-ui5` automatically:

- Serves UI5 apps from `app/`
- Connects frontend to local CAP service
- Hot-reload for CDS and UI5 changes

❌ Never run standalone:

```bash
# ❌ NEVER from the UI5 app folder
cd app/my-ui5-app/
ui5 serve          # ← won't connect to CAP
npm start          # ← won't connect to CAP
```

## Find Available CAP Services

```bash
cds compile '*' --to serviceinfo
# Output:
# HRService:
#   kind: odata-v4
#   urlPath: /odata/v4/HRService
```

## manifest.json — Relative OData URI

```json
{
  "sap.app": {
    "dataSources": {
      "mainService": {
        "uri": "/odata/v4/HRService/",
        "type": "OData",
        "settings": { "odataVersion": "4.0" }
      }
    }
  },
  "sap.ui5": {
    "models": {
      "": {
        "dataSource": "mainService",
        "settings": {
          "synchronizationMode": "None",
          "operationMode": "Server",
          "autoExpandSelect": true
        }
      }
    }
  }
}
```

The URI `/odata/v4/HRService/` is relative — works both locally with `cds watch` and in BTP production.

## ui5.yaml for CAP App

```yaml
# app/my-ui5-app/ui5.yaml
specVersion: "3.0"
metadata:
  name: com.myapp.hrapp
type: application
framework:
  name: SAPUI5
  version: "1.136"
  libraries:
    - name: sap.m
    - name: sap.ui.core
    - name: sap.f
    - name: sap.ui.layout
    - name: themelib_sap_horizon
```

No `server.customMiddleware` for proxy — `cds-plugin-ui5` handles it automatically.

## mta.yaml — Deploy to BTP CF

```yaml
modules:
  - name: my-cap-app-content
    type: com.sap.application.content
    path: app/my-ui5-app
    requires:
      - name: my-cap-html5-repo-host
        parameters:
          content-target: true
    build-parameters:
      build-result: dist
      requires:
        - artifacts: [my-ui5-app.zip]
          name: my-ui5-app
          target-path: resources/

  - name: my-ui5-app
    type: html5
    path: app/my-ui5-app
    build-parameters:
      build-result: dist
      builder: custom
      commands:
        - npm install
        - npm run build:cf
      supported-platforms: []
```

## CAP Checklist

- [ ] App in `app/<name>/` inside CAP root
- [ ] `cds-plugin-ui5` in ROOT `package.json` devDependencies
- [ ] Development: `cds watch` from root only
- [ ] OData URI in manifest is relative (`/odata/v4/ServiceName/`)
- [ ] No `ui5-middleware-simpleproxy` for CAP local service
- [ ] OData version confirmed with `cds compile '*' --to serviceinfo`
