```text
.agents/
├── CLAUDE.md                    ← Orquestador principal
├── README.md                    ← Instrucciones de instalación
├── CONTRIBUTING.md              ← Guía para extender el stack
├── commands/                    ← Comandos del stack (13); cada emisor los traduce al formato de su host
├── agents/                      ← System prompts de cada agente especializado
│   ├── 01-requirements/
│   ├── 02-integration/
│   ├── 03-btp-cap/
│   ├── 04-fiori-ui5/            ← prompt núcleo; estándares y referencia en skills/sap-ui5-standards/
│   ├── 05-hana-cloud/
│   ├── 06-abap-developer/
│   │   └── reference/           ← Material lazy-load (ALV clásico, reports legacy)
│   ├── 07-basis-security/
│   ├── 08-data-migration/
│   ├── 09-qa-testing/
│   ├── 10-devops/
│   └── 11-documentation/
├── skills/                      ← Skills; los del stack cargan material bajo demanda
│   ├── sap-ui5-standards/       ← ⭐ Estándares y expertise SAPUI5/Fiori (lazy-load)
│   ├── sap-abap-standards/      ← ⭐ RAP, CDS, AMDP, BAdIs (lazy-load)
│   ├── sap-nfr/                 ← ⭐ Catálogo NFR detallado (lazy-load)
│   ├── sap-btp-standards/       ← ⭐ Arquitectura CAP y modelado HANA (lazy-load)
│   ├── sap-doc-standards/       ← ⭐ Estructura, diagramas y templates de doc (lazy-load)
│   └── sap-diagrams/            ← ⭐ Motor de diagramas SAP validados (.sapdiag.json → .drawio + .svg)
│       ├── schemas/             ← IR tipado: architecture, sequence
│       ├── lib/                 ← layout, ruteo, gate de composición, emisores
│       ├── bin/sapdiag.mjs      ← CLI: validate | render | deliver | doctor
│       └── examples/            ← specs de referencia (pasan showcase en CI)
├── shared/                      ← Contenido compartido entre agentes (evita duplicación)
│   ├── response-format.md       ← Formato de respuesta estándar (6 secciones)
│   ├── core-dev-principles.md   ← Reglas SIEMPRE/NUNCA comunes a todos los agentes
│   └── non-functional-requirements.md ← NFR: reglas duras (el detalle, en skills/sap-nfr/)
├── orchestrator/
│   └── routing_rules.json       ← Reglas de enrutamiento con dependencias entre agentes
├── config/
│   └── stack.config.json
├── rules/
│   ├── GIT-WORKFLOW.md          ← Regla global (aplica a todos los agentes)
│   ├── TASK-COMPLETION-REPORT.md ← Regla OPT-IN: reporte de cierre (desactivada por defecto — activar por proyecto)
│   └── repo-structure.md        ← Este archivo
├── docs/
│   ├── sap-agent-stack.html     ← Documentación visual del stack
│   └── SECURITY-SCANNING.md     ← Documentación de CI/CD y seguridad en PRs
├── client-docs/                 ← ⛔ GITIGNORED — Templates y docs específicos de cliente
├── scripts/
│   ├── validate-stack.js        ← Validación de integridad del stack
│   ├── validate-json.js
│   ├── validate-yaml.js
│   ├── validate-cds.js
│   └── validate-diagrams.js     ← Gate showcase sobre todos los .sapdiag.json
└── flows/
    └── e2e_pipeline.md
```

> **Reglas condicionales:** Los estándares SAPUI5 (`skills/sap-ui5-standards/`) solo aplican cuando el agente Fiori/UI5 está activo. La única regla global es `rules/GIT-WORKFLOW.md`. `TASK-COMPLETION-REPORT.md` es opt-in por proyecto (ver instrucciones dentro del archivo).
>
> **Archivos shared:** El directorio `shared/` contiene contenido reutilizado por múltiples agentes. Los agentes referencian estos archivos en vez de duplicar el contenido en cada system_prompt.
>
> **Archivos reference:** Cada agente puede tener un subdirectorio `reference/` con material de consulta que se lee solo cuando se necesita (lazy-load), NO se carga automáticamente con el system_prompt.
