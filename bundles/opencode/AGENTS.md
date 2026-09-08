# SAP Enterprise Agent Stack

> Generado por `emitters/opencode.mjs` desde `stack.manifest.json`.
> No editar a mano: los cambios se pierden en la próxima emisión.

Stack de agentes SAP enterprise: 11 agentes de dominio, subagentes Fiori, gates de Definition of Done y servidores MCP SAP.

## Comandos

| Comando | Rol | Cuándo |
| --- | --- | --- |
| `/sap-abap` | ABAP Developer | Codigo ABAP: reports, BAdIs, RFCs, CDS, RAP, AMDP y debugging. |
| `/sap-basis` | Basis & Security Advisor | Roles y autorizaciones, transportes, landscape, segregacion de funciones y GRC. |
| `/sap-cap` | SAP BTP & CAP Developer | CAP Node.js/Java, MTA, XSUAA, Cloud Foundry, Kyma y servicios en SAP BTP. |
| `/sap-devops` | SAP DevOps Engineer | CI/CD para SAP: gCTS, pipelines, ATC y automatizacion de transportes. |
| `/sap-doc` | SAP Documentation Architect | Documentacion tecnica entregable: Word con template de cliente y diagramas. |
| `/sap-fiori` | Fiori / UI5 Developer | Apps Fiori y SAPUI5, RAP frontend, Launchpad y Business Application Studio. |
| `/sap-hana` | SAP HANA Cloud Specialist | Calculation Views, SQLScript, HDI containers, SDA/SDI y BW/4HANA. |
| `/sap-integration` | Integration Architect | iFlows, Integration Suite/CPI, OData, IDocs, APIs y conexiones entre sistemas. |
| `/sap-migration` | Data Migration Lead | Migracion de datos: mapeo de campos, LTMC/Migration Cockpit y scripts de carga. |
| `/sap-qa` | QA & Testing Specialist | Casos de prueba, UAT, defectos, checklist de go-live y requisitos no funcionales. |
| `/sap-req` | Requirements Analyst | Requerimientos, blueprints, functional specs, gap analysis y AS-IS/TO-BE. |

## Definition of Done


OpenCode soporta hooks bloqueantes vía plugins: `.opencode/plugins/ses-gates.js`
traduce el contrato del stack al modelo de excepciones de OpenCode, así que
los 3 gates aplican en el momento de la entrega.

# DEFINITION OF DONE — Regla Global Bloqueante

> **APLICABILIDAD**: TODO codigo que se entrega. Sin excepciones por tamaño.
> **CUANDO**: en la **entrega** — `git commit` / `git push` / `gh pr create` — o
> cuando el dev corre `/sap-gates`. **NO en cada turno.**
> **ENFORCEMENT**: `hooks/scripts/delivery-gate.sh` (PreToolUse sobre `Bash`),
> con `.husky/pre-commit` como red para commits hechos fuera del agente.

## Principio

Ningun codigo se entrega hasta que pase **3 gates en este orden**:

1. **Quality Gate tecnico** — linters / scans / smells (`quality-gate.sh`)
2. **Code Review** — agente `reviewer` sobre el diff
3. **QA + NFR Check** — agente `09-qa-testing` validando funcional **y** no funcional

Si CUALQUIERA reporta `CRITICAL` o `HIGH`, la entrega se **bloquea**.

## Cuando corren

Los gates corren en el **punto de entrega**, no al cerrar cada turno. El motivo
y las alternativas descartadas estan en `docs/adr/008-gates-en-la-entrega-no-en-cada-turno.md`.

| Momento | Que pasa |
|---|---|
| Durante la tarea | Nada bloqueante. Lint incremental del archivo editado. |
| Al cerrar un turno | Aviso de una linea, una vez por sesion. No bloquea. |
| `git commit` / `push` / `gh pr create` | **Los 3 gates.** Bloquea si falta alguno. |
| `/sap-gates` | Los 3 gates a pedido del dev. |

Los flags `tmp/.review-done` y `tmp/.qa-nfr-done` guardan los **hashes de árbol**
revisados, uno por línea, y solo cubren esos: cualquier edición posterior los
deja de cubrir. Se consumen cuando la entrega efectivamente ocurre (hook
`post-commit`). El flujo es **correr los gates, no tocar nada, y entregar**.

`git push` verifica que los commits que publica figuren en el registro de
entregas gateadas (`logs/gate-deliveries.log`); si alguno falta, pide los gates
sobre el árbol de `HEAD`. Detalle y alternativas descartadas en
[ADR-011](../docs/adr/011-approvals-de-gate-anclados-al-contenido.md).

## Aplicabilidad

| Tipo de cambio | Gates que aplican |
|---|---|
| Fix de 1 linea en codigo productivo | Los 3 (al entregar) |
| Feature completa | Los 3 (al entregar) |
| Hotfix en PRD | Los 3, con bloqueo aun mas estricto |
| Documentacion / markdown | Ninguno (no es codigo ejecutable) |
| Meta-stack (`hooks/`, `agents/`, `commands/`, `scripts/`) | Solo Gate 1 |

## Escape hatches

| Variable / archivo | Efecto |
|---|---|
| `SES_GATES=off` | Desactiva el gate de entrega. El dev asume el riesgo; queda avisado en la sesion. |
| `SES_SKIP_DOD_GATES=1` | Opt-out para consumidores del plugin. |
| `tmp/.hotfix-override` | HOTFIX-OVERRIDE auditado con two-person rule (ADR-005). Gate 1 CRITICAL sigue bloqueando. |
| `SES_MODE=lite` | Spike/prototipo: solo Gate 1 al entregar. `full` (default) exige los 3; `ultra` acorta a la mitad la red de vencimiento por tiempo. Ver ADR-009. |

## Gate 1 — Quality Gate Tecnico

Ejecutado por `hooks/scripts/quality-gate.sh`. Bloquea si:

- CDS lint falla (`.cds` modificados)
- UI5 linter falla (`webapp/**/*.{js,xml}` modificados)
- ESLint falla (`.js` modificados)
- ABAP smell scan reporta CRITICAL (`hooks/scripts/abap-smell-scan.sh`)
- Clean Core scan detecta modificacion a SAP standard (`hooks/scripts/clean-core-scan.sh`)
- Manifest UI5 invalido

## Gate 2 — Code Review (agente `reviewer`)

Invocado por `/sap-gates` o exigido por `delivery-gate.sh` al entregar. Corre el
agente `reviewer` sobre el diff. Bloquea si reporta:

- CRITICAL: bugs, regresion, security issue, violacion Clean Core
- HIGH: smells de performance, ausencia de manejo de errores, hardcoding

Verifica adherencia a:

- `shared/core-dev-principles.md`
- Best practices SAP del agente que produjo el codigo
- Estandares oficiales (Clean ABAP, CAP best practices, Fiori Guidelines)

## Gate 3 — QA + NFR Check (agente `09-qa-testing`)

Invocado por `/sap-gates` o exigido por `delivery-gate.sh` al entregar. Corre el
agente QA con el sub-checklist `agents/09-qa-testing/nfr-checklist.md`. Bloquea
si NO puede responder con evidencia:

- Concurrencia: ¿que pasa con N usuarios paralelos?
- Volumen: ¿se probo con ≥80% del pico productivo?
- Idempotencia: ¿reintento produce mismo resultado?
- Restart-ability: ¿reanudable tras cancelacion?
- Observabilidad: ¿logs utiles a las 3 AM?
- Locking: ¿enqueue / lock master / FOR UPDATE donde corresponde?

Casos limite y datos sucios cubiertos.

## Output

Los 3 gates devuelven hallazgos **inline en la sesion** (stdout). No se generan
archivos de reporte. El usuario los ve directo en la conversacion.

## Que NO es parte del DoD

- Documentacion entregable al cliente (eso lo decide el `/sap-doc` agent cuando aplica)
- Reportes de cierre en `.md` (eliminados intencionalmente — basta el resumen de sesion)
- Commits / push (eso es decision del usuario, no del DoD)

## Excepcion: hotfix bajo presion (HOTFIX-OVERRIDE)

Para un incidente en PRD que exige entregar sin los 3 gates, existe un override
auditado con **two-person rule**. Crear `tmp/.hotfix-override` con dos lineas:

```text
REASON: <ticket + descripcion, minimo 20 chars>
APPROVED_BY: <email distinto del solicitante>
```

Reglas duras:

1. **Gate 1 CRITICAL nunca se omite** — ni con override.
2. El flag **se consume** en la primera entrega. Un override = una entrega.
3. Todo override se loguea en `logs/hotfix-overrides.log` con solicitante,
   aprobador, sesion y razon.
4. **Self-approval rechazado.** Ambos firmantes asumen el riesgo.
5. Los gates omitidos se ejecutan en la proxima sesion, sin override.

Procedimiento completo, anti-patrones y auditoria mensual:
`docs/adr/003-hotfix-override-design.md` y `docs/adr/005-two-person-hotfix-approval.md`.

## Quien lo enforce

- **`delivery-gate.sh`** — hook `PreToolUse` sobre `Bash` en `settings.json`.
  Intercepta `git commit` / `git push` / `gh pr create` y corre los 3 gates en
  orden. Si falta alguno, deniega la entrega con instrucciones.
- **`.husky/pre-commit`** — red de seguridad a nivel git: cubre los commits
  hechos desde la terminal, sin agente de por medio.
- **`/sap-gates`** — invocacion explicita del dev, en cualquier momento.
- El usuario ve los hallazgos inline y decide: corregir, o entregar igual con
  `SES_GATES=off` asumiendo el riesgo.
