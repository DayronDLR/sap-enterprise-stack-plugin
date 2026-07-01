---
name: sapui5-freestyle
model: claude-opus-4-7
description: Creates and extends SAPUI5 FreeStyle applications using ui5-mcp and fiori-mcp tools. Use this skill when creating a new SAPUI5 app from scratch, scaffolding views/controllers/routes, building dashboards, forms, list/detail apps, or any custom Fiori/UI5 development not based on Fiori Elements generators. Trigger for requests like "crea una app SAPUI5", "nueva aplicación UI5 FreeStyle", "necesito un dashboard SAP", "formulario UI5", "app de aprobaciones SAPUI5", or adding new views/features to an existing SAPUI5 FreeStyle project — even if the user doesn't say "FreeStyle" explicitly.
license: MIT
metadata:
  version: 1.0.0
  lastUpdated: 2026-03-11
compatibility:
  tools:
    - mcp__ui5-mcp__get_guidelines
    - mcp__ui5-mcp__create_ui5_app
    - mcp__ui5-mcp__get_api_reference
    - mcp__ui5-mcp__run_ui5_linter
    - mcp__ui5-mcp__run_manifest_validation
    - mcp__ui5-mcp__get_version_info
    - mcp__fiori-mcp__list_functionality
    - mcp__fiori-mcp__get_functionality_details
    - mcp__fiori-mcp__execute_functionality
    - mcp__fiori-mcp__search_docs
---

# SAPUI5 FreeStyle Application Builder

Senior SAP Fiori/SAPUI5 developer workflow. Creates production-ready apps following enterprise SAP standards.

## Step 0 — Mandatory Before Any Code

Call `mcp__ui5-mcp__get_guidelines` first. Always. Apply the output throughout the entire task.

---

## Phase 1: Requirements

Collect what's needed. Infer from context when obvious — don't over-ask.

| Parameter | Required | Default |
|---|---|---|
| App namespace (`com.company.app`) | ✅ | — |
| Base path (absolute) | ✅ | — |
| TypeScript or JavaScript | ✅ | TypeScript |
| OData V4 URL + entity set | if OData | — |
| i18n locales | optional | `en`, `es` |
| Inside CAP project? | optional | no |
| UI pattern | optional | infer from request |

---

## Phase 2: Scaffold with MCP Tools

```
1. mcp__ui5-mcp__get_version_info { frameworkName: "SAPUI5" }
2. mcp__ui5-mcp__create_ui5_app { appNamespace, basePath, typescript: true, framework: "SAPUI5", runNpmInstall: true }
3. mcp__fiori-mcp__list_functionality { appPath }
   → mcp__fiori-mcp__get_functionality_details { appPath, functionalityId }
   → mcp__fiori-mcp__execute_functionality { appPath, functionalityId, parameters }
```

CAP projects: `basePath` = `app/` folder, `createAppDirectory: true`.

---

## Phase 3: Implement

### Mandatory file structure

```
webapp/
├── Component.ts
├── manifest.json
├── index.html
├── controller/
│   ├── BaseController.ts   ← always create, see references/core-standards.md
│   └── Main.controller.ts
├── view/Main.view.xml
├── model/
│   ├── models.ts
│   └── formatter.ts        ← all formatters here, see references/data-binding.md
└── i18n/
    ├── i18n.properties
    └── i18n_es.properties
```

### Reference files — load as needed

| Topic | File | When |
|---|---|---|
| BaseController, ES6, MVC, imports | `references/core-standards.md` | All projects |
| Layouts, forms, controls, VBox rules | `references/design-patterns.md` | Building views |
| OData types, formatters, binding | `references/data-binding.md` | Data-driven apps |
| Routing, navigation, parameters | `references/routing.md` | Multi-view apps |
| i18n keys, ARIA labels, locales | `references/i18n-accessibility.md` | All projects |
| CSP, XSS, lazy load, batch requests | `references/security-performance.md` | Pre-delivery |
| CAP folder, cds watch, manifest URI | `references/cap-integration.md` | CAP projects only |

When unsure about a UI5 API: `mcp__ui5-mcp__get_api_reference` or `mcp__fiori-mcp__search_docs`.

### Master-Detail with SplitApp

```xml
<!-- Master-Detail with SplitApp -->
<SplitApp id="app">
  <masterPages>
    <Page title="Orders">
      <List items="{/Orders}" mode="SingleSelectMaster" selectionChange=".onSelect">
        <StandardListItem title="{OrderID}" description="{Status}"/>
      </List>
    </Page>
  </masterPages>
  <detailPages>
    <Page title="Order Detail">
      <ObjectHeader title="{OrderID}" number="{Amount}"/>
    </Page>
  </detailPages>
</SplitApp>
```

---

## Phase 4: Validate

```
mcp__ui5-mcp__run_ui5_linter { projectDir }          ← fix all findings
mcp__ui5-mcp__run_manifest_validation { projectDir }
```

Quick checklist:

- [ ] Zero hardcoded strings — `{i18n>key}` in XML, `getText()` in TS
- [ ] All locale files have every new key
- [ ] All interactive controls have ARIA labels
- [ ] No `var` — only `const`/`let`
- [ ] No `sap.m.*` globals — only ES6 imports
- [ ] No `SimpleForm` — only `Form + ColumnLayout`
- [ ] No VBox wrapping Table+FilterBar as main container → use `DynamicPage`
- [ ] Routing: `async: true`, router initialized in `Component.ts`
- [ ] Dialogs: lazy via `Fragment.load()`, destroyed in `onExit`

---

## Phase 5: Handoff

1. List of files created with one-line description each
2. Start command: `ui5 serve` (standalone) or `cds watch` from CAP root
3. Next steps to implement
4. Relevant SAP transactions for the business domain

## Cross-Skill References

For detailed coverage of these topics, defer to the canonical skill:

- **CAP backend integration**: `sap-cap-capire` skill (canonical for CDS, OData services)
- **UI5 CLI commands**: `sapui5-cli` skill (canonical for project init, build, serve)
