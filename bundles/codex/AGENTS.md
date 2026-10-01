# SAP Enterprise Agent Stack

> Generado por `emitters/codex.mjs` desde `stack.manifest.json`.
> No editar a mano: los cambios se pierden en la próxima emisión.

Stack de agentes SAP enterprise: 11 agentes de dominio, subagentes Fiori, gates de Definition of Done y servidores MCP SAP.

## Agentes

Se invocan como skills, con `$nombre`:

| Skill | Rol | Cuándo |
| --- | --- | --- |
| `$ses-sap-abap` | ABAP Developer | Codigo ABAP: reports, BAdIs, RFCs, CDS, RAP, AMDP y debugging. |
| `$ses-sap-basis` | Basis & Security Advisor | Roles y autorizaciones, transportes, landscape, segregacion de funciones y GRC. |
| `$ses-sap-cap` | SAP BTP & CAP Developer | CAP Node.js/Java, MTA, XSUAA, Cloud Foundry, Kyma y servicios en SAP BTP. |
| `$ses-sap-devops` | SAP DevOps Engineer | CI/CD para SAP: gCTS, pipelines, ATC y automatizacion de transportes. |
| `$ses-sap-doc` | SAP Documentation Architect | Documentacion tecnica entregable: Word con template de cliente y diagramas. |
| `$ses-sap-fiori` | Fiori / UI5 Developer | Apps Fiori y SAPUI5, RAP frontend, Launchpad y Business Application Studio. |
| `$ses-sap-hana` | SAP HANA Cloud Specialist | Calculation Views, SQLScript, HDI containers, SDA/SDI y BW/4HANA. |
| `$ses-sap-integration` | Integration Architect | iFlows, Integration Suite/CPI, OData, IDocs, APIs y conexiones entre sistemas. |
| `$ses-sap-migration` | Data Migration Lead | Migracion de datos: mapeo de campos, LTMC/Migration Cockpit y scripts de carga. |
| `$ses-sap-qa` | QA & Testing Specialist | Casos de prueba, UAT, defectos, checklist de go-live y requisitos no funcionales. |
| `$ses-sap-req` | Requirements Analyst | Requerimientos, blueprints, functional specs, gap analysis y AS-IS/TO-BE. |

## Definition of Done


Codex soporta hooks bloqueantes, así que los 3 gates aplican en el momento
de la entrega, igual que en el host de referencia.

> ⚠️ **Dos pasos manuales: confiar la carpeta y aprobar los hooks.**
> Codex no carga los hooks de un proyecto hasta que confiás en él — te lo
> pregunta la primera vez que lo abrís. Además, cada hook nuevo o cambiado
> queda en «Hooks need review» hasta que lo aprobás en `/hooks`; `codex exec`
> ni avisa. Mientras tanto, los 3 gates **no te frenan al escribir**: quedan
> en `git` (husky) y en CI. Corré `$ses-sap-gates` antes de entregar.
>
> Medido contra `codex-cli 0.153.4`: con la carpeta confiada y sin aprobar,
> ningún hook corrió. `ses doctor --host codex --dir <proyecto>` te dice si
> confiaste en la carpeta; la aprobación de cada hook se ve en `/hooks`.

> **Si tu organización activó `allow_managed_hooks_only = true`** en
> `requirements.toml`, los hooks de proyecto se ignoran y esta protección no
> corre. En ese caso los gates quedan en manos de `git` y CI: corré
> `$ses-sap-gates` antes de entregar.

# DEFINITION OF DONE — Regla Global Bloqueante

> **APLICABILIDAD**: TODO codigo que se entrega. Sin excepciones por tamaño.
> **CUANDO**: en la **entrega** — `git commit` / `git push` / `gh pr create` — o
> cuando el dev corre `/sap-gates`. **NO en cada turno.**
> **ENFORCEMENT**: `hooks/scripts/delivery-gate.sh` (aviso temprano) y
> `.husky/pre-commit` + CI (la garantía, en git). Cómo deciden —flags, trailers,
> rango del push, merges—: [`docs/DOD-ENTREGA.md`](.agents/docs/DOD-ENTREGA.md).

## Principio

Ningún código se entrega hasta que pase **3 gates en este orden**. Si cualquiera
reporta `CRITICAL` o `HIGH`, la entrega se **bloquea**.

| Gate | Quién | Bloquea si |
|---|---|---|
| 1 · Quality | `quality-gate.sh` | Falla CDS lint, UI5 linter, ESLint o el manifest; ABAP smell CRITICAL; Clean Core sobre estándar; configuración que ejecuta código cambia de forma riesgosa (`config-risk-scan.mjs`). Recuerda lo que ya aprobó por contenido. |
| 2 · Code Review | agente `reviewer` sobre el diff | Bugs, regresión, seguridad, Clean Core (CRITICAL); performance, sin manejo de errores, hardcoding (HIGH). Contra `shared/core-dev-principles.md`, las best practices del agente que produjo el código y los estándares oficiales (Clean ABAP, CAP, Fiori Guidelines) |
| 3 · QA + NFR | agente `09-qa-testing` con `agents/09-qa-testing/nfr-checklist.md` | No puede responder **con evidencia** concurrencia, volumen (≥80 % del pico), idempotencia, restart-ability, observabilidad y locking |

Los hallazgos salen **inline en la sesión**; no se generan reportes en archivos.

## Cuándo corren

| Momento | Qué pasa |
|---|---|
| Durante la tarea | Nada bloqueante. Lint incremental del archivo editado. |
| Al cerrar un turno | Aviso de una línea, una vez por sesión. No bloquea. |
| `git commit` / `push` / `gh pr create` | **Los 3 gates.** Bloquea si falta alguno. |
| `/sap-gates` | Los 3 gates a pedido del dev. |

El sello de los gates 2 y 3 cubre **el árbol revisado**: cualquier edición
posterior lo invalida. El flujo es **correr los gates, no tocar nada, y
entregar**. Motivo: `docs/adr/008-gates-en-la-entrega-no-en-cada-turno.md`.

## Aplicabilidad

| Tipo de cambio | Gates que aplican |
|---|---|
| Ajuste chico de configuración: cada clave cambiada está en una lista de lo seguro (versión, descripción, metadatos, la versión concreta de una dependencia que ya estaba, título de la app, textos de i18n); hasta 30 líneas, sin borrados, sin hallazgos del scan. `xs-app.json`, `xs-security.json` y `.cdsrc.json` nunca | Gate 1; Gate 2 en la sesión, sin subagente; Gate 3 no aplica (`sellar-gate.sh qa --config-trivial`, que recalcula la clase) |
| Fix de 1 línea o feature en código productivo | Los 3 (al entregar) |
| Hotfix en PRD | Los 3, con bloqueo aún más estricto |
| Documentación / markdown | Ninguno (no es código ejecutable) |
| Meta-stack (lista abajo) | Sólo Gate 1 |

Estas rutas son **meta-stack**: exentas de los gates 2 y 3, pasan sólo por el
Gate 1. Alcanza **un** archivo productivo en el cambio para que el commit entero
exija los 3. `tests/unit/meta-stack-documentado.test.js` verifica que esta lista
y `dod_is_meta_only` digan lo mismo.

```text
hooks/          scripts/        .github/      orchestrator/
config/         rules/          shared/       agents/
commands/       evals/          tests/        plugins/sap-enterprise-stack/
settings.json   CLAUDE.md
```

## Escape hatches

| Variable / archivo | Efecto |
|---|---|
| `SES_GATES=off` | Desactiva el gate de entrega. El dev asume el riesgo; queda avisado en la sesión. |
| `SES_SKIP_DOD_GATES=1` | Opt-out para consumidores del plugin. |
| `tmp/.hotfix-override` | HOTFIX-OVERRIDE con two-person rule (abajo). |
| `SES_CONFIG_RISK=allow` | Aprueba, para esa entrega, un CRITICAL del scan de configuración (un `postinstall`, una dependencia fuera del registro). Lo exporta la persona en su shell y queda en `logs/config-risk-overrides.log`. |
| `SES_MODE=lite` | Spike/prototipo: sólo Gate 1. `full` (default) exige los 3; `ultra` acorta a la mitad el vencimiento por tiempo. ADR-009. |

## Excepción: hotfix bajo presión (HOTFIX-OVERRIDE)

Para un incidente en PRD que exige entregar sin los 3 gates: crear
`tmp/.hotfix-override` con `REASON: <ticket + descripción, ≥20 chars>` y
`APPROVED_BY: <email distinto del solicitante>`.

1. **Gate 1 CRITICAL nunca se omite** — ni con override.
2. Un override = una entrega: el flag se consume en la primera.
3. Se loguea en `logs/hotfix-overrides.log`; self-approval rechazado.
4. Los gates omitidos se ejecutan en la próxima sesión, sin override.

Procedimiento y auditoría: `docs/adr/003-hotfix-override-design.md`,
`docs/adr/005-two-person-hotfix-approval.md` y `docs/runbooks/01-hotfix-override.md`.

## Qué NO es parte del DoD

Documentación entregable al cliente (la decide `/sap-doc`), reportes de cierre en
`.md` (basta el resumen de sesión) y la decisión de commitear o pushear (es del
usuario).

