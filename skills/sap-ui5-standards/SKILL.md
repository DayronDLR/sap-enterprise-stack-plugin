---
name: sap-ui5-standards
description: Estándares obligatorios de SAPUI5/Fiori del stack — ES6+/MVC, data binding, accesibilidad e i18n, integración con CAP, layouts y controles, formatters, routing, y seguridad/performance. Úsalo antes de escribir o revisar código SAPUI5 (controllers, vistas XML, manifest.json, fragments, formatters, rutas) para cargar solo la regla que aplica al caso.
---

# Estándares SAPUI5 — enrutador

Este skill guarda los estándares de UI5 del stack en `reference/`. **No los leas
todos**: leé solo el que aplica a lo que estás por escribir. Cargarlos completos
cuesta ~11k tokens y el 90% no aplica a una tarea dada.

## Qué leer según la tarea

| Vas a tocar… | Leé |
| --- | --- |
| Controllers, MVC, ES6+, APIs deprecadas | `sap-ui5-standards/reference/core-standards.md` |
| Textos visibles, ARIA, i18n | `sap-ui5-standards/reference/accessibility-i18n.md` |
| Proyecto UI5 dentro de CAP, `cds watch`, `cds-plugin-ui5` | `sap-ui5-standards/reference/cap-integration.md` |
| Vistas XML, layouts, `Form` vs `SimpleForm`, CSS | `sap-ui5-standards/reference/design-controls.md` |
| Binding de tipos, formatters, OData types | `sap-ui5-standards/reference/formatters-databinding.md` |
| `manifest.json` routing, targets, `BaseController`, parámetros | `sap-ui5-standards/reference/routing-navigation.md` |
| XSS, CSP, `$batch`, lazy loading, performance | `sap-ui5-standards/reference/security-performance.md` |

## Material técnico de referencia

Catálogos de API, patrones completos y ejemplos de código. Misma regla: uno por vez.

| Necesitás… | Leé |
| --- | --- |
| APIs del framework, patrones freestyle, Building Blocks | `sap-ui5-standards/reference/expertise-ui5-framework.md` |
| Floorplans, annotations CDS, adaptation projects | `sap-ui5-standards/reference/expertise-fiori-elements.md` |
| RAP: behavior definitions, projections, EML | `sap-ui5-standards/reference/expertise-rap.md` |
| CAP + Fiori, despliegue on-premise vs BTP, MTA | `sap-ui5-standards/reference/expertise-cap-btp.md` |
| Autorizaciones (PFCG) y testing (OPA5, wdi5) | `sap-ui5-standards/reference/expertise-ops.md` |
| Smart Controls (SmartTable, SmartFilterBar) con OData V2 | `sap-ui5-standards/reference/smartcontrols-v2.md` |
| Patrones de formatters listos (statusState, numberFormat) | `sap-ui5-standards/reference/formatter-patterns.md` |
| MTA para FreeStyle standalone en BTP | `sap-ui5-standards/reference/mta-freestyle-standalone.md` |

Leelos con la tool Read, por path relativo a este skill.

## Reglas que aplican siempre (no hace falta abrir ningún archivo)

Estas son las que más se violan, y son baratas de tener presentes:

- **i18n obligatorio** — cero textos hardcodeados en vistas o controllers.
- **`viewPath` está PROHIBIDO** en `manifest.json` v2; usá `routing.config.viewPath`
  solo en v1 legacy.
- **Versión LTS explícita** en `manifest.json` — nunca `latest`.
- **Sin APIs deprecadas** — validá con `mcp__plugin_ses_sap-ui5__get_api_reference` ante la duda.
- **`growing` + `growingThreshold`** en toda lista que pueda superar unos cientos
  de registros.
- **Nada de `sap.ui.getCore()`** en código nuevo.

## Verificación

Después de escribir código UI5, corré siempre:

```bash
ui5lint                      # o mcp__plugin_ses_sap-ui5__run_ui5_linter
```

Y `mcp__plugin_ses_sap-ui5__run_manifest_validation` si tocaste `manifest.json`.
