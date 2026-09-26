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

> ⚠️ **Un paso manual, una sola vez: confiar la carpeta.**
> Codex no carga los hooks de un proyecto hasta que confiás en él — te lo
> pregunta la primera vez que lo abrís. Hasta que digas que sí, los 3 gates
> **no te frenan al escribir**: quedan en `git` (husky) y en CI. Corré
> `$ses-sap-gates` antes de entregar.
>
> No es "habilitar cada hook": `enabled` es `true` por defecto en Codex. Es la
> confianza en la carpeta lo que decide. Verificado contra `codex-cli 0.153.3`;
> `ses doctor --host codex --dir <proyecto>` te dice en qué estado estás.

> **Si tu organización activó `allow_managed_hooks_only = true`** en
> `requirements.toml`, los hooks de proyecto se ignoran y esta protección no
> corre. En ese caso los gates quedan en manos de `git` y CI: corré
> `$ses-sap-gates` antes de entregar.

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

`git push` mira **los commits que publica**, no el working tree. Primero
clasifica el rango entero: si todo lo que publica es meta-stack o documentación,
no hay nada que los gates 2 y 3 puedan revisar y el push sale exento, con nota.

Si hay código productivo, cada commit tiene que estar cubierto por alguna de
estas tres, que son la misma evidencia por vías distintas:

| Vía | Qué es | Sobrevive a |
|---|---|---|
| Trailer `SES-Gated-Tree` | Va dentro del commit, anclado a su árbol | squash, clon nuevo, CI |
| `logs/gate-deliveries.log` | Registro local, por sha o por árbol | `--amend` de solo mensaje |
| Anterior al mecanismo | El commit precede al que **introdujo** `.husky/prepare-commit-msg` | clonar, rotar el log, borrar el hook |

### Cuando el commit trae varios trailers

Un merge o un squash **concatena los mensajes**, y con ellos los trailers. Eso es
normal: 8 de los últimos 100 commits de este repo tienen dos o más, y uno tiene
26. **Gana el último**, que es el del commit final de la rama y cuyo árbol es
exactamente el árbol del merge. Por eso el trailer sobrevive a un squash.

Ambos lectores —`dod_trailer_cubre_su_arbol` en bash y `lib/trailer.mjs` en el
CLI— aplican esa misma regla, y `tests/unit/sellado-trailer.test.js` los corre a
los dos sobre los commits reales del repo exigiendo el mismo veredicto. Cuando
divergían, el gate local aceptaba un push que CI denegaba para siempre.

Dos detalles que conviene saber:

- **No alcanza con que *alguno* de los trailers cubra.** Si el último no cubre, se
  deniega aunque haya uno válido más arriba: es el caso del `--amend` posterior al
  sellado, donde corresponde denegar.
- **`git merge --squash` local pierde los trailers sólo si aceptás el mensaje
  automático.** Git arma `SQUASH_MSG` indentando los mensajes cuatro espacios
  dentro de «Squashed commit of the following», y el patrón exige columna 0.
  Medido:

  | Cómo commiteás el squash | Resultado |
  |---|---|
  | `git commit -m "…"` | **sella normal** — la fuente es `message`, el hook corre |
  | `git commit --no-edit` | queda sin trailer: la fuente es `squash` y el hook sale temprano |

  Si caíste en el segundo caso no estás trabado: sellá y `git commit --amend
  --no-edit` estampa el trailer. El squash de GitHub no tiene este problema —
  deja los trailers en columna 0.

La tercera vía se ancla a **git**, no al registro local: la frontera es el commit
que introdujo el hook de sellado, que es un hecho de la historia y no se mueve al
clonar. Un commit posterior que *borre* el hook no queda exento, y si el hook no
existe en ningún commit, nada queda exento por antigüedad.

El rango de un push **no se deduce del texto del comando** — se le pregunta a
git. Con un solo remoto no hay ambigüedad; con varios se usa el upstream de la
rama; y si no se puede determinar el destino, se mira `HEAD` entero. Esa última
opción bloquea de más, que es el lado correcto para equivocarse: `--not --remotes`
excluye lo alcanzable desde *cualquier* remoto, o sea que da un rango más
**chico**, y caer ahí ante la duda sería fallar abierto.

La salida generada (`plugins/`, `fixtures/`) se excluye **solo cuando el emisor
confirma que es la suya**: el gate materializa el árbol que se entrega y corre
`ses build --check` contra él. Si coincide, se excluye para no repetir el mismo
hallazgo una vez por host; si no coincide —o no se puede comprobar— cuenta como
código productivo y exige los gates.

No alcanza con que la fuente venga en el mismo cambio. Esa regla se probó y se
descartó: bastaba tocar `settings.json` —un byte— para colar a mano un backdoor
en el artefacto que se distribuye. `dist/` no se excluye por ninguna vía, porque
ningún `--check` lo valida.

En un push la verificación es **por commit**, no sólo sobre el árbol final. La
primera versión corría el `--check` una vez sobre HEAD y aplicaba el veredicto a
todo el rango; eso se descartó al medir lo que permitía: basta plantar un
backdoor en `plugins/` en un commit y revertirlo en el siguiente para que HEAD
salga limpio, el rango entero se declare meta-stack y el push salga exento, con
el backdoor publicado y accesible por `git checkout` o `git bisect`. Es la clase
*add-and-revert*, que ya se bloqueaba para el código productivo y quedaba abierta
justo para el artefacto que se distribuye.

Sólo se paga por los commits que **tocan** salida generada, que en un push normal
son cero o uno; el resto se saltea sin materializar nada. Un rango que excede la
ventana ya bloquea por otro lado.

El recorrido por commit se corta en `DOD_PUSH_SCAN_MAX` (50). **Si el push trae
más, no se toma ningún atajo**: se exigen los gates sobre el árbol de `HEAD`,
porque hay commits que nadie inspeccionó.

Y cuando el rango toca salida generada, el techo efectivo **no es la ventana sino
`DOD_GEN_PRESUPUESTO_SEG`** (45 s): a ~1,5 s por commit —medido; una versión
anterior decía ~1,1— se agota alrededor de los **30** y el push queda denegado, no
lento. Subir `DOD_PUSH_SCAN_MAX` en ese caso no
hace que tarde más: hace que deniegue igual, más tarde. La salida es sellar `HEAD`
con `/sap-gates`.

Subir la variable inspecciona más, y el costo depende de **qué** trae el push, no
sólo de cuántos commits:

| Camino | Por commit | 50 commits |
| --- | --- | --- |
| Rango sin salida generada | plano: una sola pasada | ~0,4 s |
| Rango productivo, recorrido de trailers | ~82 ms | ~4,5 s |
| Commits que **tocan** salida generada | ~1,5 s (materializa el árbol y corre los 4 emisores) | hasta ~36 s |

El último camino tiene techo agregado propio, `DOD_GEN_PRESUPUESTO_SEG` (45 s):
pasado ese punto no se exime nada, se dice por qué, y la entrega cae al camino
normal de pedir los gates sobre `HEAD`.

**Cuántos commits tocan salida generada, de verdad.** Una versión anterior decía
«cero o uno en un push normal». Medido sobre la historia de este repo: **80 % de
los últimos 20 commits**, 48 % de los últimos 50, 26 % de los últimos 100. O sea
que un push de 50 commits puede pagar ~36 s y rozar el presupuesto. Si lo agota,
la salida no es un error: es sellar `HEAD` con `/sap-gates`, que sale más barato
que inspeccionar el rango entero.

Una versión anterior de este párrafo publicaba «~85 ms por commit» para todo y
estimaba 45 s con `DOD_PUSH_SCAN_MAX=500`. Era el número del recorrido de
trailers aplicado al camino equivocado: en el de salida generada la cuenta
verdadera daba minutos, y el dev que siguiera ese consejo se quedaba mirando un
prompt clavado.

Son medidas de una máquina de desarrollo, no una garantía: lo que vale es el
orden de magnitud. Sellar el árbol de `HEAD` con `/sap-gates` suele salir más
barato que subir la ventana.

Detalle y alternativas descartadas en
[ADR-011](../docs/adr/011-approvals-de-gate-anclados-al-contenido.md); sobre lo
que el trailer **no** garantiza, [ADR-013](../docs/adr/013-la-dod-vive-en-git-no-en-el-host.md).

## Aplicabilidad

| Tipo de cambio | Gates que aplican |
|---|---|
| Fix de 1 linea en codigo productivo | Los 3 (al entregar) |
| Feature completa | Los 3 (al entregar) |
| Hotfix en PRD | Los 3, con bloqueo aun mas estricto |
| Documentacion / markdown | Ninguno (no es codigo ejecutable) |
| Meta-stack (ver lista completa abajo) | Solo Gate 1 |

### Qué cuenta como meta-stack, exactamente

Estas rutas quedan **exentas de los gates 2 y 3** y pasan sólo por el Gate 1:

```text
hooks/          scripts/        .github/      orchestrator/
config/         rules/          shared/       agents/
commands/       evals/          tests/        plugins/sap-enterprise-stack/
settings.json   CLAUDE.md
```

Una versión anterior de esta tabla nombraba cuatro —`hooks/`, `agents/`,
`commands/`, `scripts/`— cuando la implementación eximía catorce. Entre los diez
que faltaban estaba **`settings.json`, que es el archivo que configura los
hooks**: un cambio que apague el gate entra por una puerta que la doc no decía
que existía.

Eso sigue siendo cierto por diseño —tocar el andamiaje no debería exigir un
review funcional— pero no depende de la buena fe: `tests/unit/meta-stack-documentado.test.js`
verifica que esta lista y `dod_is_meta_only` digan lo mismo, y que `settings.json`
siga cableando `delivery-gate.sh` sobre `Bash`. Borrar ese cableado **rompe un
test**, que es lo que antes no pasaba.

Alcanza **un** archivo productivo en el cambio para que el commit entero exija
los 3 gates.

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

## Que cuenta como "entrega" — y donde esta la garantia

**La garantia no esta en el texto del comando. Esta en git.** `.husky/pre-commit`
lo ejecuta git en TODO commit, lo haya escrito quien lo haya escrito, y si
alguien lo saltea con `--no-verify` el commit sale sin trailer y **CI lo
deniega**. `tests/unit/nivel2-bloquea.test.js` lo fija con las formas que ningun
analisis de texto revela —una funcion envoltorio, la indireccion por variable—:
git las bloquea todas.

El hook `delivery-gate.sh` (PreToolUse) es el **aviso temprano** (ADR-013,
nivel 1): mira el texto del comando y deniega antes de que el agente llegue a
git, con un mensaje que dice que hacer. Es **best-effort por construccion**: bash
no se puede analizar estaticamente de forma completa. Tres rondas de revision
seguidas encontraron formas nuevas de escribir `git commit` que el texto no
revela; la proxima siempre existe.

Lo que el nivel 1 si reconoce, medido de punta a punta contra el hook:

```bash
git commit; echo listo      sh -c "git commit -m x"      eval "git commit"
(git commit -m x)           $(git commit -m x)           !git commit
\git commit                 <(git push)                  {git,commit} -m x
$'\x67\x69\x74' commit       git c''ommit                 "git" commit
gh pr create                gh pr new                    gh "pr" cr''eate
```

La regla: `git` tiene que **empezar una palabra**, y se matchea sobre el comando
crudo y sobre una forma aplanada con lo que bash resuelve antes de ejecutar —el
citado ANSI-C, las llaves sin espacios, comillas y barras—. Lo que **no**
reconoce, a sabiendas: funciones y alias, la indireccion por variable, `xargs`,
`find -exec`, un `python -c`, y un script de python o node que otro segmento del
mismo comando escribe y despues ejecuta. Esas las frena el nivel 2. Un PR
creado sin `gh pr create` —con `gh alias set` o con `gh api` contra el endpoint
de pulls— tampoco lo ve el nivel 1, y ahi el respaldo es el trailer que CI exige
a cada commit del rango.

Un costo a sabiendas: `rg` y `ag` no estan en la lista de comandos de solo
lectura (`--pre` y `--pager` ejecutan un programa), asi que buscar la frase de
una entrega con ellos deniega. Con `grep` pasa.

**Severidad para los gates**: una forma que evade el nivel 1 y que el nivel 2
frena es **MEDIUM**. Una que entrega codigo productivo sin gates —que pasa el
nivel 2— es **CRITICAL**. Se clasifica midiendo el nivel 2, no suponiendolo (ver
`agents/reviewer.md`).

**Lo que solo *menciona* una entrega ya no deniega** (roadmap F8-a). Antes
`echo "git commit"`, un heredoc hacia `cat` con un procedimiento de git o un
`# git push` en un comentario denegaban como la entrega, y ese costo empujaba a
`SES_GATES=off`. `hooks/scripts/lib/comando.mjs` borra del comando lo que con
seguridad es dato antes del matcher:

- comentarios;
- el cuerpo de un heredoc cuyo comando no es un shell;
- los argumentos citados de un comando que solo lee o imprime (`echo`, `printf`,
  `cat`, `grep`…) o de `python -c` / `node -e`, que ya eran punto ciego.

Lo que se ejecuta nunca se borra:

- `$( )`, backticks y `<( )`, aunque vayan entre comillas;
- lo que lee un shell (`sh -c`, `eval`, `bash <<EOF`, `| sh`, `| xargs`);
- la palabra del comando;
- los argumentos de todo comando que no esté en esa lista.

La decision es **por segmento**, que es la objecion que habia al allowlist:
`echo hola; git commit` sigue denegando, porque `git commit` es otro comando.
Y la lista es **cerrada**: sólo se borra algo si todos los comandos, a
cualquier profundidad, son de solo lectura o impresión, `cd` o un intérprete que
no es shell, sin asignaciones delante. Con cualquier otro no se borra nada,
porque puede ejecutar lo que otro segmento citó o escribió
(`echo … > f; bash f`, `> >(bash)`, `env -u X sh -c …`):

- un shell, `make`, `npm`, un envoltorio como `env`, un ejecutable por ruta o
  del `PATH`;
- tambien `git` y `gh`, que ejecutan texto de su configuracion (un alias `!…`,
  `core.editor`);
- y los que corren un programa por opcion (`rg --pre`,
  `sort --compress-program`).

Una lista de lo peligroso no converge; una de lo seguro, sí. Sin node, o
ante un comando que el analizador no entiende, se decide sobre el texto entero,
como antes.

**Una entrega en otro repositorio no es de este proyecto** (F8-b). Si cada
entrega del comando se resuelve —por el `cwd` del evento, un `cd <dir>`
encadenado con `;` o `&&`, o `git -C`— a un directorio de otro repo, el gate
permite con un aviso. La exencion es estrecha a proposito: una entrega en un
subshell, en `sh -c`, con variables, con `--git-dir` o `GIT_DIR`, un `cd`
detras de `||` o en un pipe, `cd -`, o cualquier comando de primer nivel que no
sea `cd <dir>`, `git`, `gh` o de solo lectura (`pushd`, `eval`, `source`,
`if`/`for`, `export`, y tambien `ln`, `mv` o `rm`, que cambian a que apunta una
ruta antes de que el `cd` corra), cuenta como de este proyecto. Tampoco se
sigue un `cd` a un nombre sin barra (`cd sub`), que bash busca antes en
`CDPATH`: solo rutas absolutas, `./`, `../` o `~`. Y un comando con cualquier
sustitucion (`$( )`, backticks) no se exime: la sustitucion corre antes y puede
mover el destino. Otro worktree de este mismo repo
tambien pasa, con un aviso que dice que alla la DoD la hace cumplir
`.husky/pre-commit`.

## Quien lo enforce

- **`delivery-gate.sh`** — hook `PreToolUse` sobre `Bash` en `settings.json`.
  Intercepta `git commit` / `git push` / `gh pr create` y corre los 3 gates en
  orden. Si falta alguno, deniega la entrega con instrucciones.
- **`.husky/pre-commit`** — red de seguridad a nivel git: cubre los commits
  hechos desde la terminal, sin agente de por medio.
- **`/sap-gates`** — invocacion explicita del dev, en cualquier momento.
- El usuario ve los hallazgos inline y decide: corregir, o entregar igual con
  `SES_GATES=off` asumiendo el riesgo.

