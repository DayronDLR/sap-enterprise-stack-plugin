# SAPUI5 + CAP Integration - Reglas de Integración

> **APLICABILIDAD**: Proyectos que combinan SAPUI5 FreeStyle con SAP CAP (Cloud Application Programming Model)
> **PRIORIDAD**: ⭐ CRÍTICO - Cumplimiento obligatorio al 100%
> **FUENTE**: Documentación oficial SAP UI5 MCP Servers

## 1. Estructura de Proyecto — Ubicación Obligatoria

### ✅ CORRECTO: App UI5 dentro del proyecto CAP

```
my-cap-project/          ← Root del proyecto CAP
├── app/                 ← ✅ AQUÍ van las apps UI5
│   └── my-ui5-app/
│       ├── webapp/
│       │   ├── Component.js
│       │   ├── manifest.json
│       │   └── ...
│       ├── package.json
│       └── ui5.yaml
├── db/                  ← Modelos CDS
│   └── schema.cds
├── srv/                 ← Servicios CDS
│   └── service.cds
├── package.json         ← Root package.json CAP
└── .cdsrc.json
```

### ❌ PROHIBIDO: App UI5 fuera de la carpeta `app/`

```
my-cap-project/
├── my-ui5-app/          ← ❌ NUNCA en el root del proyecto CAP
├── frontend/            ← ❌ NUNCA en carpeta con nombre personalizado
├── ui/                  ← ❌ NUNCA fuera de app/
```

## 2. Plugin Obligatorio: `cds-plugin-ui5`

### Instalación (en el Root CAP, NO en la carpeta UI5)

```bash
# ✅ OBLIGATORIO: instalar en el root del proyecto CAP
cd my-cap-project/        # ← Root CAP
npm install --save-dev cds-plugin-ui5
```

```json
// package.json del ROOT CAP — devDependencies
{
  "devDependencies": {
    "cds-plugin-ui5": "^0.x.x",
    "@sap/cds-dk": "^8.x.x"
  }
}
```

### ❌ NUNCA instalar en la carpeta de la app UI5

```bash
# ❌ INCORRECTO: instalar en la subcarpeta de la app
cd my-cap-project/app/my-ui5-app/
npm install cds-plugin-ui5   # ❌ NUNCA aquí
```

## 3. Comando de Desarrollo — Regla Crítica

### ✅ SIEMPRE: `cds watch` desde el Root CAP

```bash
# ✅ OBLIGATORIO: arrancar desde el root del proyecto CAP
cd my-cap-project/
cds watch
```

**¿Por qué?** `cds watch` con `cds-plugin-ui5` instalado:

- Sirve automáticamente las apps UI5 en `app/`
- Conecta el frontend al servicio CAP local sin configuración extra
- Hot-reload de cambios tanto en CDS como en UI5

### ❌ PROHIBIDO: Correr desde la carpeta UI5

```bash
# ❌ NUNCA: arrancar desde la carpeta de la app UI5
cd my-cap-project/app/my-ui5-app/
ui5 serve          # ❌ PROHIBIDO — no conecta al servicio CAP
npm start          # ❌ PROHIBIDO — no conecta al servicio CAP
```

### ❌ PROHIBIDO: `ui5-middleware-simpleproxy` para CAP local

```yaml
# ❌ NUNCA usar simpleproxy para conectar a CAP local
# ui5.yaml
server:
  customMiddleware:
    - name: ui5-middleware-simpleproxy  # ❌ No necesario con cds-plugin-ui5
      configuration:
        baseUri: http://localhost:4004
```

> `cds-plugin-ui5` gestiona la conexión al servicio CAP automáticamente. Usar `simpleproxy` crea conflictos y duplica configuración innecesariamente.

## 4. Obtener Información de Servicios CAP

```bash
# ✅ CORRECTO: Ver servicios disponibles y sus URLs
cds compile '*' --to serviceinfo

# Ejemplo de output:
# MyService:
#   - kind: odata-v4
#   - urlPath: /odata/v4/MyService
```

## 5. Configuración manifest.json para Servicios CAP

```json
{
  "sap.app": {
    "dataSources": {
      "mainService": {
        "uri": "/odata/v4/MyService/",
        "type": "OData",
        "settings": {
          "odataVersion": "4.0"
        }
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

> La URI `/odata/v4/MyService/` es relativa — funciona tanto en desarrollo local con `cds watch` como en producción en BTP.

## 6. ui5.yaml Mínimo para Proyecto CAP

```yaml
# app/my-ui5-app/ui5.yaml
specVersion: "3.0"
metadata:
  name: my.ui5.app
type: application
framework:
  name: SAPUI5
  version: "1.136"    # LTS recomendado
  libraries:
    - name: sap.m
    - name: sap.ui.core
    - name: sap.f
    - name: sap.ui.layout
    - name: themelib_sap_horizon
```

> **Sin** sección `server.customMiddleware` para proxies CAP — el plugin lo gestiona automáticamente.

## 7. Deploy a SAP BTP Cloud Foundry

```yaml
# mta.yaml — módulo UI5 dentro del proyecto CAP
modules:
  - name: my-cap-project-app-content
    type: com.sap.application.content
    path: app/my-ui5-app
    requires:
      - name: my-cap-project-html5-repo-host
        parameters:
          content-target: true
    build-parameters:
      build-result: dist
      requires:
        - artifacts:
            - my-ui5-app.zip
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

## Checklist de Integración CAP+UI5

- [ ] App UI5 ubicada en `app/<nombre-app>/` del proyecto CAP
- [ ] `cds-plugin-ui5` instalado en el ROOT CAP (`package.json` raíz)
- [ ] Desarrollo iniciado con `cds watch` desde el root — nunca `ui5 serve`
- [ ] No usar `ui5-middleware-simpleproxy` para conectar a CAP local
- [ ] URI del servicio en `manifest.json` es relativa (`/odata/v4/ServiceName/`)
- [ ] Versión OData confirmada con `cds compile '*' --to serviceinfo`
- [ ] `ui5.yaml` sin configuración de proxy innecesaria
