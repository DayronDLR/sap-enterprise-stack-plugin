# SAP Enterprise Agent Stack

> Generado por `emitters/copilot.mjs` desde `stack.manifest.json`.
> No editar a mano: los cambios se pierden en la próxima emisión.

Stack de agentes SAP enterprise: 11 agentes de dominio, subagentes Fiori, gates de Definition of Done y servidores MCP SAP.

## Comandos

| Prompt | Rol | Cuándo |
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

## Definition of Done en este host

**GitHub Copilot no soporta hooks bloqueantes.** Nada va a detenerte en el
momento de escribir. Eso no significa que los gates no apliquen: significa
que se enteran más tarde.

| Política | Qué la hace cumplir acá |
| --- | --- |
| Exige los 3 gates de la DoD al commitear, pushear o abrir PR. | los hooks de git y CI, sobre el pull request |

**Antes de entregar, corré:**

```text
/sap-gates
```

Los gates 2 (code review) y 3 (QA + NFR) se corren en la sesión del agente.
CI no puede correrlos por vos — solo verificar que corrieron, leyendo el
trailer `SES-Gated-Tree` de cada commit. Un commit con código productivo sin
ese trailer bloquea el pull request.

### Lo que directamente no está

- Controla las llamadas a servidores MCP.
- Comprime la entrada de comandos verbosos (ADR-009).
- Reinyecta la persona del agente activo cada N turnos.
- Registra la actividad de subagentes para las métricas.
- Aviso de cierre de sesión, una vez por sesión.

Son comodidades, no políticas: ninguna decide si el código puede entregarse.

## Principios

# Principios de Desarrollo — Aplica a TODOS los agentes

> Estas reglas son **globales**. Cada agente puede tener reglas adicionales especificas a su dominio.

## NUNCA

1. **NUNCA hardcodear** credenciales, secrets, URLs de servicio, o textos de usuario
   - BTP: usar service bindings y destinations
   - Fiori: URLs en manifest.json dataSources
   - ABAP: usar SY-MANDT, constantes, o tablas de config
   - i18n: todos los textos visibles al usuario en archivos i18n

2. **NUNCA SELECT *** en views, queries o procedures productivos — solo campos necesarios

3. **NUNCA** codigo sin manejo de errores:
   - ABAP: TRY/CATCH en bloques criticos, FAILED/REPORTED en EML
   - CAP: req.error() o throw cds.error() en handlers
   - Fiori: catch en promises OData V4, errorHandler en V2
   - Integration: Exception Subprocess en iFlows

4. **NUNCA** omitir access control:
   - CDS ABAP: @AccessControl.authorizationCheck: #CHECK
   - BTP: @requires en service definitions, XSUAA scopes
   - Fiori: validar autorizacion en backend, nunca solo en frontend

5. **NUNCA** deployer a PRD sin confirmacion explicita del usuario

6. **NUNCA imponer un package manager** en el proyecto del usuario:
   - Detectar el que ya usa por su lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` o sin lockfile → **npm** (el estandar documentado por SAP para CAP/Fiori/MTA)
   - Ejecutar `install`, `build` y scripts con **ese** gestor — nunca cambiarlo ni introducir un lockfile de otro
   - No agregar `"packageManager"` ni `corepack` al `package.json` del cliente salvo que el usuario lo pida
   - `pnpm` es SOLO el tooling interno de este stack/plugin (los MCP servers) — jamas se propaga al codigo, build o instrucciones del proyecto del cliente

## SIEMPRE

1. **SIEMPRE** incluir tests:
   - ABAP: cl_abap_behv_test_environment para RAP, ABAP Unit para logica
   - CAP: cds.test() con casos positivos y negativos
   - Fiori: OPA5 journeys para flujos criticos, QUnit para formatters

2. **SIEMPRE** documentar codigo no trivial con comentarios concisos

3. **SIEMPRE** aplicar Clean Core para S/4HANA:
   - Preferir BAdIs, CDS, RAP, extensiones BTP sobre modificaciones estandar
   - Usar APIs released (C1 contract) sobre acceso directo a tablas

4. **SIEMPRE** verificar APIs y sintaxis contra documentacion oficial o MCP tools antes de generar codigo

5. **SIEMPRE** considerar performance desde el diseno:
   - Indices para campos de filtro frecuentes
   - Paginacion en listas (growing=true, $top/$skip)
   - Lazy loading de asociaciones

## Escalera de decision — antes de escribir codigo nuevo

Recorrela en orden y frena en el primer "si". El codigo que no se escribe no se
revisa, no se transporta y no se rompe en PRD.

1. **¿Hace falta que exista?** Si el requerimiento no lo pide explicitamente, no
   se construye. Nada de "por las dudas".
2. **¿Ya esta en este proyecto?** Buscar antes de crear: clase Z existente,
   include, helper, CDS view, fragment.
3. **¿Lo resuelve SAP estandar?** BAPI, clase CL_*, CDS view released (C1),
   BAdI, Fiori Elements en vez de freestyle. Una API released mantenida por SAP
   gana a cualquier Z equivalente.
4. **¿Lo resuelve una dependencia ya instalada?** No agregar una libreria para
   algo que el runtime ya hace.
5. **¿Entra en una linea?** Una expresion CDS antes que un metodo; un `CASE`
   antes que una clase de estrategia.
6. **Si no:** la solucion minima que cumple el requerimiento y sus NFR.

**Perezoso con la solucion, nunca con la lectura.** Entender el problema y el
codigo existente a fondo es prerequisito para decidir no escribir algo.

La escalera **no** aplica a: manejo de errores, validaciones, access control,
locking, logging ni los NFR. Eso nunca se recorta — es la frontera de confianza.

## Simplificaciones deliberadas

Cuando un agente elija a proposito una solucion minima (helper stdlib en vez de
clase propia, vista CDS released en vez de query custom, escalar en vez de batch
porque el volumen no lo justifica), marcarla con comentario inline:

`// ponytail: <decision>, <upgrade path si crece>`

Ejemplo: `// ponytail: SELECT SINGLE sin lock, agregar ENQUEUE si concurrencia escala`

La marca comunica intencion al reviewer y evita que el proximo agente "complete"
la simplificacion pensando que fue olvido. NO se usa para saltarse NFR §1-§3,
§6, §8 ni mandates de Clean Core — esos son irrenunciables.

