#!/bin/bash
# delivery-gate.sh — Definition of Done en el PUNTO DE ENTREGA.
#
# PreToolUse hook sobre `Bash`. Intercepta `git commit`, `git push` y `gh pr create`
# y exige los 3 gates de la DoD ANTES de que el trabajo salga del working tree.
#
# Por que aca y no en `Stop`:
#   `Stop` dispara al final de CADA TURNO. Poner los gates ahi significaba exigir
#   dos subagentes completos (reviewer + sap-qa) en cada prompt que tocara un
#   archivo — incluido "renombra esta variable". El costo medido era de 2-3x
#   tokens por tarea sin ganancia de calidad: revisar un gap a medio cerrar
#   produce hallazgos sobre codigo que todavia va a cambiar.
#   El commit/push/PR es el unico momento en que el trabajo esta terminado y
#   revisarlo tiene sentido. Ver rules/DEFINITION-OF-DONE.md y ADR-008.
#
# Escape hatches:
#   SES_GATES=off            -> desactiva el gate (decision del dev, se avisa)
#   SES_SKIP_DOD_GATES=1     -> opt-out para consumidores del plugin
#   tmp/.hotfix-override     -> HOTFIX-OVERRIDE auditado (two-person rule, ADR-005)

set -u

INPUT=$(cat)

# ── Fast path ────────────────────────────────────────────────────────────────
# Este hook corre en CADA comando Bash. El 99% no son entregas, asi que el caso
# comun tiene que costar cero: un match de patron sobre el JSON crudo y salir.
# Sin spawns, sin git, sin parsear.
#
# El patron NO puede ser `*"git push"*` literal. `git -C . push`, `git --no-pager
# push`, `git -c k=v push` y hasta `git  push` con dos espacios son la misma
# entrega y no matcheaban: el fast path cortaba antes y todo el aparato de
# decision —destino resuelto por git, frontera por ascendencia, approvals por
# hash de arbol— no llegaba a correr. El rigor habia entrado por la logica y no
# por el disparador que la activa.
#
# Se matchea el VERBO, que es barato y no puede tener opciones adentro. Trae
# falsos positivos (un `echo "push"` entra al slow path), y esta bien: ahi el
# comando real se parsea y se descarta. Fallar hacia "mirar de mas" es el lado
# correcto para un disparador.
# Y si el texto crudo no trae la palabra, se mira con el citado quitado.
#
# El fast path corria sobre el JSON crudo ANTES de la pasada aplanada del
# matcher, asi que una palabra partida por el citado —`git c''ommit`,
# `git "com"mit`, `gh "pr" create`, `gh pr cr''eate`— salia por aca en `exit 0`
# y el matcher nunca la veia. Los tests del matcher la daban por cerrada porque
# llamaban a la funcion aislada, no al hook. Lo midio el Gate 3 de punta a punta.
#
# Solo se aplana cuando el crudo no matcheo. Y casi siempre con `tr`, no con
# sustitucion de bash: en bash 3.2 `${s//[…]/}` reconstruye el string por cada
# coincidencia. Medido: un comando de 4 KB con comillas y llaves tardaba 5 SEGUNDOS
# por llamada con el umbral en 8 KB — en cada comando Bash de la sesion. Un fork
# de `tr` cuesta ~3,5 ms; la sustitucion ya cuesta mas que eso con 128 caracteres
# en el peor caso. Bash queda solo para lo muy chico, donde las pocas comillas del
# JSON no pesan.
_hay_entrega() {
    case "$1" in
        # `$'` al slow path sin mas: el citado ANSI-C puede esconder la palabra
        # entera (`git $'\x63ommit'`), y ni el crudo ni un aplanado por `tr` la
        # ven. Lo resuelve el aplanado del matcher. Lo midieron los dos gates.
        *push*|*commit*|*"pr create"*|*"pr new"*|*"\$'"*) return 0 ;;
        *) return 1 ;;
    esac
}
if ! _hay_entrega "$INPUT"; then
    if (( ${#INPUT} > 256 )); then
        # `LC_ALL=C`: con locale UTF-8, `tr` corta en el primer byte que no es
        # UTF-8 ("Illegal byte sequence"), `_PLANO` quedaba truncado y el comando
        # salia por aca. Lo midio el Gate 3, por el hook y no por la funcion.
        _PLANO=$(printf '%s' "$INPUT" | LC_ALL=C tr -d "\"'\\\\{}" | LC_ALL=C tr ',' ' ')
    else
        _PLANO=${INPUT//[\"\'\\\{\}]/}
        _PLANO=${_PLANO//,/ }
    fi
    _hay_entrega "$_PLANO" || exit 0
fi

# ── Slow path ────────────────────────────────────────────────────────────────
# Mismo fallback que `sellar-gate.sh`: el TOPLEVEL del repo, no el CWD.
#
# Divergian. `sellar-gate.sh` ataba el sello al repo y este lo buscaba en `.`,
# asi que fuera de Claude Code —donde `CLAUDE_PROJECT_DIR` no viene— e invocado
# desde un subdirectorio, uno escribia en `<toplevel>/tmp/` y el otro leia en
# `<subdir>/tmp/`. El comentario de `sellar-gate.sh` afirma que "los dos miran el
# mismo archivo desde cualquier directorio": esta era la mitad que faltaba.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
TMP_DIR="${PROJECT_DIR}/tmp"
REVIEW_FLAG="${TMP_DIR}/.review-done"
QA_FLAG="${TMP_DIR}/.qa-nfr-done"
HOTFIX_LOG="${PROJECT_DIR}/logs/hotfix-overrides.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Si falta la libreria, el gate no puede evaluar nada. Se deja pasar avisando por
# stderr en vez de bloquear: un hook roto no debe dejar al dev sin poder commitear,
# y .husky/pre-commit sigue siendo la red a nivel git.
if [[ ! -f "${SCRIPT_DIR}/lib/dod-common.sh" ]]; then
    echo "[delivery-gate] lib/dod-common.sh no encontrado — gate omitido." >&2
    exit 0
fi
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/dod-common.sh"
HOOK_NAME="delivery-gate"
# shellcheck disable=SC1091
[[ -f "${SCRIPT_DIR}/lib/emit-stack-event.sh" ]] && source "${SCRIPT_DIR}/lib/emit-stack-event.sh"

allow() { exit 0; }

allow_with_note() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":%s}}\n' \
        "$(dod_json_escape "$1")"
    exit 0
}

deny() {
    type emit_stack_event >/dev/null 2>&1 && emit_stack_event "deny" '{}'
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(dod_json_escape "$1")"
    exit 0
}

# La regla de escapado JSON. `deny()` la usa para construir su salida, asi que
# sin ella el hook no puede denegar — y un hook que no imprime nada PERMITE. El
# respaldo de `dod_json_escape` evita el fail-open, pero que el archivo falte
# significa que el bundle esta incompleto y eso hay que decirlo, no taparlo.
# Mismo criterio que con `grep`: improbable no es avisado.
if ! declare -F ses_json_escape >/dev/null 2>&1; then
    echo "[delivery-gate] falta hooks/scripts/lib/json-escape.sh: se usa el respaldo minimo." >&2
fi

# `grep` es la herramienta con la que se decide TODO lo de abajo. Sin ella,
# `dod_es_subcomando_git` devuelve no-cero y el gate permitia en silencio: el
# mismo modo de falla que el de `python3`, por otra utilidad. Es POSIX y estar
# sin ella es patologico, pero "improbable" no es "avisado".
if ! command -v grep >/dev/null 2>&1; then
    deny "No encuentro \`grep\` en el PATH. La Definition of Done no puede decidir
sin ella, y permitir a ciegas seria peor que bloquear.

Revisa el PATH del entorno donde corre el agente."
fi

# Extraer el comando real. Solo llegamos aca en entregas, asi que el costo del
# parseo es irrelevante.
#
# Si NO hay parser, se usa el JSON crudo. Eso ya estaba escrito aca —"degradar a
# revisar de mas es preferible a dejar pasar una entrega sin gates"— y era falso:
# el matcher exige que a `git` lo preceda un espacio o un separador, y en el JSON
# lo precede una comilla. No matcheaba nada, y el gate PERMITIA todo en silencio.
# Con python3 ausente el aparato entero desaparecia sin una linea de aviso.
#
# Ahora `dod_tool_command` cae a node antes de rendirse, y si tampoco esta, el
# matcher sobre el crudo admite la comilla via `DOD_GIT_PRE`. Recien ahi la
# promesa de arriba es cierta.
# Ya no hace falta ensanchar `DOD_GIT_PRE` aca: la clase incluye las comillas
# SIEMPRE, con o sin parser. Que este camino las admitiera y el normal no era la
# asimetria que dejaba pasar `sh -c "git commit"` con python3 presente — o sea
# que el camino degradado estaba mejor protegido que el principal.
CMD=$(dod_tool_command "$INPUT")
if [[ -z "$CMD" ]]; then
    CMD="$INPUT"
    echo "[dod] sin python3 ni node no puedo parsear el comando: se decide sobre el JSON crudo." >&2
fi

# Confirmar sobre el comando real: el fast path tambien matchea si la frase
# aparece solo en `description`, o en un `echo "git push"`.
#
# `git` seguido de cualquier cantidad de opciones globales y despues el
# subcomando: `-C <dir>`, `-c <k=v>`, `--no-pager`, `--git-dir=…`, `--work-tree=…`.
# El fast path ya dejo pasar de mas a proposito; la precision vive aca.
if ! dod_es_subcomando_git "$CMD" 'commit' \
   && ! dod_es_subcomando_git "$CMD" 'push' \
   && ! dod_es_gh_pr_create "$CMD"; then
    allow
fi
# `--dry-run` no entrega nada.
echo "$CMD" | grep -q -- '--dry-run' && allow

# ── Escape hatches ───────────────────────────────────────────────────────────

case "${BASH_SOURCE[0]:-$0}" in
    */plugins/*)
        [[ "${SES_SKIP_DOD_GATES:-}" = "1" ]] && allow
        ;;
    *) ;;   # Fuera de plugins/: el opt-out del plugin no aplica.
esac

# ── Alcance: que se esta entregando ──────────────────────────────────────────
#
# El tipo de entrega se decide PRIMERO, porque de el depende cual es el arbol que
# se entrega, y de ese arbol depende si la salida generada se puede eximir. Antes
# este bloque estaba mas abajo y el flag se calculaba DESPUES de que la exencion
# por `--union` lo consultara: siempre lo leia en 0, asi que la exencion por
# contenido estaba muerta y todo push de sync caia a la ruta per-commit, con su
# ventana de 50. Un push de 60 commits de SOLO documentacion salia denegado — la
# misma regresion que `--union` existe para eliminar.
ES_PUSH=false
if dod_es_subcomando_git "$CMD" 'push' \
   || dod_es_gh_pr_create "$CMD"; then
    ES_PUSH=true
fi

# ¿La salida generada de lo que se entrega es la que producen los emisores?
#
# La resolucion vive en `dod-common.sh` para que los otros controles —el husky y
# CI— usen la misma. Aca solo se decide QUE se entrega.
#
# En commit se usa SIEMPRE `commit-a`, sin mirar si el comando trae `-a`.
#
# Detectarlo por el TEXTO era el anti-patron que este mismo archivo documenta
# rechazado dos veces —la heuristica de `--no-verify` y el destino del push—: un
# `-a` dentro del MENSAJE (`git commit -m "fix -a bug"`) convertia un commit
# normal en `commit-a` y lo volvia inentregable por una palabra del mensaje.
#
# `commit-a` NO es un superconjunto de `commit`. Esa premisa vivio aca un buen
# rato y es falsa: `dod_delivery_tree commit-a` hace `git add -u` sobre una copia
# del indice, o sea que PISA lo staged con el working tree. Si alguien stagea algo
# y despues devuelve el working tree a lo anterior (`git status` dice `MM`), el
# arbol de `commit-a` queda igual a HEAD mientras el del indice trae el cambio —
# y es el del indice el que publica `git commit -m`. El diff daba vacio y el gate
# permitia. Se mide en `tests/unit/delivery-gate-bordes.test.js`.
#
# `_TIPO_ENTREGA` distingue push de commit, y nada mas.
#
# `dod_arboles_de_entrega` solo mira si el tipo es `push`: con `commit` o con
# `commit-a` recorre la misma rama y devuelve los dos arboles candidatos cuando
# difieren. El valor exacto no cambia nada aca — y van dos comentarios que
# afirmaron lo contrario, uno diciendo que la eleccion era por el log y otro que
# era lo que producia los dos arboles. Ninguna de las dos.
if [[ "$ES_PUSH" = "true" ]]; then _TIPO_ENTREGA=push; else _TIPO_ENTREGA=commit-a; fi

# El arbol que se entrega, calculado UNA sola vez y COMPARTIDO con todo lo que
# decide sobre el: la verificacion de la salida generada, el alcance, el approval
# y el log de auditoria. Calcularlo por separado en cada consumidor abria una
# ventana —un watcher, un format-on-save— donde uno verifica el arbol A y otro
# decide sobre el arbol B.
# TODOS los arboles que esta entrega puede publicar, calculados UNA vez y
# compartidos con todo lo que decide sobre ellos: la verificacion de la salida
# generada, el alcance, el approval y el log. En push es uno; en commit son el
# del indice y el de `-a`, que no se contienen entre si.
# El rc SE VERIFICA. `dod_arboles_de_entrega` devuelve 1 cuando pudo calcular uno
# de los dos arboles y no el otro, justamente para avisar que la lista esta
# incompleta — y despues los dos consumidores la tomaban con `$( )`, que tira el
# rc. O sea que la señal se agrego y no la leia nadie.
#
# Con una lista recortada vuelve el bypass que este ciclo cerro, entrando por un
# fallo ambiental en vez de por un flag mal calculado: `dod_resolver_generados_ok`
# verifica el unico arbol que llego, exporta `DOD_GENERADOS_OK=1`, y con eso
# `plugins/` desaparece de todos los `CHANGED`. La entrega publica el arbol que
# nadie miro.
if ! _ARBOLES_ENTREGA=$(dod_arboles_de_entrega "$_TIPO_ENTREGA"); then
    deny "No se pudo determinar que arbol estas entregando.

git no pudo calcular uno de los dos arboles candidatos (el del indice y el de
\`-a\`). El motivo esta en la salida de arriba.

La Definition of Done no puede aprobar lo que no puede leer. Revisa el estado del
repo: \`git status\`, permisos de .git/, espacio en el temporal."
fi
_ARBOL_ENTREGA=$(printf '%s\n' "$_ARBOLES_ENTREGA" | sed '/^$/d' | head -1)

if [[ "$ES_PUSH" = "true" ]]; then
    # El disparador son los commits que se publican, NO el working tree: despues
    # de commitear esta limpio y el flag nunca llegaba a 1.
    _RANGO_GEN=$(dod_rango_a_publicar) || _RANGO_GEN=""
    dod_resolver_generados_ok push "$(dod_archivos_del_rango "$_RANGO_GEN")" \
        "$_ARBOLES_ENTREGA" "$_RANGO_GEN"
else
    dod_resolver_generados_ok "$_TIPO_ENTREGA" \
        "$(git -c core.quotePath=false diff --cached --name-only 2>/dev/null
           git -c core.quotePath=false diff --name-only 2>/dev/null)" \
        "$_ARBOLES_ENTREGA"
fi

# QUE se esta entregando: el diff entre HEAD y el ARBOL ENTREGADO.
#
# Antes esto miraba lo STAGED y decidia con un regex si sumar el working tree
# (`git commit -am`). Las dos mitades fallaban:
#
#   - El regex exigia `git commit` literal, asi que `git -C . commit -am`,
#     `git --no-pager commit -am` y `git -c k=v commit -am` NO sumaban el working
#     tree. Con lo staged meta-only y un archivo productivo llegando por el `-a`,
#     el gate lo daba por meta y dejaba pasar el commit.
#   - `git commit <ruta>` publica el working tree de esa ruta SIN stagearla, asi
#     que `CHANGED` quedaba vacio y el guard de mas abajo dejaba pasar todo.
#
# Los dos son la misma asimetria: se decidia sobre el indice mientras se entregaba
# otra cosa. Derivarlo del arbol entregado la elimina, y de paso saca un regex de
# texto mas — que es el patron que este archivo documenta rechazado tres veces.
if [[ "$ES_PUSH" != "true" ]]; then
    if [[ -n "$_ARBOL_ENTREGA" ]] && git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        # La UNION de los dos arboles que un commit puede publicar. Mirar uno
        # solo hacia invisible al archivo staged-y-revertido: ver el comentario
        # de `_TIPO_ENTREGA` mas arriba.
        # Cada arbol se filtra con SU veredicto, no con el del conjunto. Un
        # arbol cuya salida generada esta confirmada no arrastra su bundle a la
        # lista; uno que no, si. Mezclarlos hacia que un indice perfectamente
        # sincronizado quedara bloqueado por el working tree de al lado.
        CHANGED=$(for _a in $_ARBOLES_ENTREGA; do
                      git -c core.quotePath=false diff-tree -r --name-only \
                          --no-commit-id HEAD "$_a" 2>/dev/null \
                        | DOD_GENERADOS_OK=$(dod_arbol_generados_ok "$_a" && echo 1 || echo 0) \
                          dod_filtrar_productivos "$_a"
                  done | sort -u | sed '/^$/d')
    elif [[ -n "$_ARBOL_ENTREGA" ]]; then
        # Sin HEAD (commit inicial): todo el arbol es lo que se entrega.
        CHANGED=$(git -c core.quotePath=false ls-tree -r --name-only "$_ARBOL_ENTREGA" 2>/dev/null \
                      | dod_filtrar_productivos)
    else
        # Sin arbol no se puede saber que se entrega. Se cae al criterio amplio,
        # pero NO en silencio: los dos `$( )` se tragaban el rc, y si git tambien
        # fallaba ahi `CHANGED` quedaba vacio y el guard de abajo permitia la
        # entrega sin que nadie se enterara de que git estaba roto.
        _ST=$(dod_staged_files); _ST_RC=$?
        _CH=$(dod_changed_files); _CH_RC=$?
        if [[ $_ST_RC -ne 0 || $_CH_RC -ne 0 ]]; then
            deny "No se pudo determinar que archivos estas entregando: git fallo al
listar el indice y el working tree, y no se pudo construir el arbol de entrega.

Revisa el estado del repo (\`git status\`, \`.git/index.lock\` de un proceso muerto,
permisos). La Definition of Done no puede aprobar lo que no puede leer."
        fi
        CHANGED=$(printf '%s\n%s\n' "$_ST" "$_CH" | sort -u | sed '/^$/d')
    fi
else
    CHANGED=$(dod_changed_files)
fi

# Nada productivo (docs, markdown, config del propio Claude) -> no aplica la DoD.
#
# OJO con push: aca `CHANGED` mira el working tree, que despues de un commit esta
# limpio. Ese atajo dejaba TODO push sin control — la maquinaria de anclaje solo
# se activaba con el arbol sucio. Un push publica commits, asi que su alcance son
# los commits, no los archivos sin commitear.
if [[ "$ES_PUSH" != "true" ]]; then
    [[ -z "$CHANGED" ]] && allow
fi

# ── SES_GATES=off ────────────────────────────────────────────────────────────
#
# AUDITORIA A12: se registra ANTES de permitir. Omitir los gates es una decision
# legitima del dev; que no quede constancia, no. Va aca y no antes porque necesita
# el alcance ya calculado — cual arbol se entrega y que archivos entran sin gates.
# El arbol es `$_ARBOL_ENTREGA`, el MISMO que se entrega. Antes se recalculaba
# como `commit`, o sea el indice: con `-a` el registro de auditoria nombraba un
# arbol que nunca salio, y el unico rastro de una entrega sin gates apuntaba a
# contenido equivocado.
if [[ "${SES_GATES:-}" = "off" ]]; then
    # El rc SE LEE. `dod_log_gates_off` propaga 1 cuando el log no queda escrito
    # —su propio comentario dice que existe para eso— y este llamador lo
    # descartaba, anunciando "Registrado en logs/gates-off.log" sobre un archivo
    # que nunca se escribio. Es la misma clase que ya se corrigio en
    # `dod_arboles_de_entrega`: una señal que nadie consume no es una señal.
    if dod_log_gates_off "${PROJECT_DIR}/logs/gates-off.log" "$_ARBOL_ENTREGA" "$CHANGED"; then
        allow_with_note "SES_GATES=off — Definition of Done omitida por configuracion. El codigo entra sin review ni QA. Registrado en logs/gates-off.log."
    else
        allow_with_note "SES_GATES=off — Definition of Done omitida por configuracion. El codigo entra sin review ni QA. ATENCION: el registro en logs/gates-off.log NO se pudo escribir (ver stderr): esta entrega queda sin rastro."
    fi
fi

# ── HOTFIX-OVERRIDE (ADR-005) ────────────────────────────────────────────────
#
# El caso `ok` NO permite aca. Permitia, y salia del script ANTES de Gate 1 —
# mientras su propio mensaje decia "Gate 1 CRITICAL sigue aplicando" y
# `rules/DEFINITION-OF-DONE.md` lo promete como regla dura ("nunca se omite, ni
# con override"). El codigo hacia lo contrario: un hotfix con un manifest roto
# salia a PRD sin que el linter lo mirara. Ahora se marca y se decide despues de
# Gate 1, que es donde la promesa se puede cumplir.
HOTFIX=$(dod_hotfix_state)
HOTFIX_OK=0
case "$HOTFIX" in
    ok\|*)
        APPROVER="${HOTFIX#ok|}"; APPROVER="${APPROVER%%|*}"
        REASON="${HOTFIX##*|}"
        REQUESTER=$(git config user.email 2>/dev/null || echo unknown)
        HOTFIX_OK=1
        ;;
    invalid)
        deny "HOTFIX-OVERRIDE invalido. tmp/.hotfix-override necesita DOS lineas:
REASON: <ticket + descripcion, minimo 20 chars>
APPROVED_BY: <email distinto del solicitante ($(git config user.email 2>/dev/null || echo unknown))>
Self-approval rechazado. Ver docs/adr/005-two-person-hotfix-approval.md"
        ;;
esac

# ── Gate 1 — Quality (linters + smells + Clean Core) ─────────────────────────
# Irrenunciable: corre siempre, incluso en cambios meta-stack.
GATE1=$(bash "${SCRIPT_DIR}/quality-gate.sh" --mode=cli 2>&1); GATE1_RC=$?
if [[ "$GATE1_RC" -ne 0 ]]; then
    deny "Gate 1 (Quality) fallo — entrega bloqueada.

${GATE1}

Corregi los hallazgos y volve a intentar el commit."
fi

# Gate 1 paso: recien ahora el override puede consumirse cumpliendo lo que promete.
#
# El consumo se hace con `mv`, que es ATOMICO dentro del mismo filesystem, y se
# verifica. Mover el consumo detras de Gate 1 metio segundos entre leer el flag y
# borrarlo, y en esa ventana dos entregas concurrentes leian el mismo override y
# las dos salian permitidas — dos entregas con un override, contra la regla dura
# "un override = una entrega" (ADR-005). Con `mv`, solo el que logra mover
# consume; el otro se encuentra sin flag y se DENIEGA — no "sigue el camino
# normal", como decia antes esta linea. Denegar es lo correcto: el dev pidio
# entregar bajo override y el override ya no esta, asi que lo que corresponde es
# avisarselo, no reevaluarlo en silencio con otro criterio.
if [[ "$HOTFIX_OK" = "1" ]]; then
    _HOTFIX_CONSUMIDO="${TMP_DIR}/.hotfix-override.consumido.$$"
    if ! mv "${TMP_DIR}/.hotfix-override" "$_HOTFIX_CONSUMIDO" 2>/dev/null; then
        deny "El HOTFIX-OVERRIDE ya fue consumido por otra entrega en curso.
Un override habilita UNA entrega (ADR-005). Si hace falta otra, se crea otro
override, con sus dos firmas."
    fi
    rm -f "$_HOTFIX_CONSUMIDO" 2>/dev/null
    if dod_log_hotfix "$HOTFIX_LOG" "$REQUESTER" "$APPROVER" "$REASON"; then
        allow_with_note "HOTFIX-OVERRIDE consumido. Solicitante: $REQUESTER, aprobador: $APPROVER. Gates 2+3 omitidos; Gate 1 corrio y paso. Re-trabajo obligatorio en la proxima sesion."
    else
        # ADR-005: todo override queda auditado. Si no se puede, no se usa.
        deny "El HOTFIX-OVERRIDE no se pudo registrar en ${HOTFIX_LOG} (ver stderr).

Un override sin auditoria no es un override: la regla de dos personas se sostiene
en que quede constancia de quien lo pidio y quien lo aprobo (ADR-005).

Arregla el acceso al log y volve a intentar."
    fi
fi

# ── Gates 2 y 3 — Code Review + QA/NFR ───────────────────────────────────────
# Cambios solo al meta-stack (hooks, scripts, prompts, documentacion): Gate 1
# alcanza. Esa exencion la fija la tabla de `rules/DEFINITION-OF-DONE.md`.
# La exencion por meta NO aplica si hay salida generada sin confirmar.
#
# `plugins/*` esta en la allowlist de `dod_is_meta_only` —y ahi vive el motor de
# gates que se distribuye a los usuarios—, asi que un backdoor escrito a mano y
# STAGEADO salia como "meta-stack" y el commit pasaba en silencio. El mismo corte
# ya existia en `dod-classify.sh` para la ruta de push; faltaba en la de commit,
# que es la primera de las dos.
if [[ "$ES_PUSH" != "true" ]] && dod_alcanza_gate1 "$CHANGED"; then
    allow
fi

# En PUSH la clasificacion NO puede mirar el working tree: despues de un commit
# esta limpio, `dod_is_meta_only ""` daba true y dejaba pasar todo push. Al
# corregirlo se desactivo la exencion entera para push, y eso sobre-corrigio: un
# push de commits que son SOLO documentacion quedaba impushable, aunque el
# `pre-commit` acabara de aprobarlos diciendo "alcanza con Gate 1".
#
# El alcance de un push son sus COMMITS, y la pregunta que decide la exencion es
# una sola: ¿alguno toca codigo productivo no-meta? `--union` la contesta sobre el
# RANGO ENTERO con una pasada de `git log`, con la misma regla que usa el gate
# local commit a commit y `ses gates --ci`.
#
# Antes esto se resolvia clasificando de a un commit, lo que costaba 2 procesos
# `git` por commit y obligaba a una ventana de 50. Al excederse, la exencion se
# desactivaba y un push de 120 commits de SOLO documentacion salia DENEGADO,
# listando 50 commits inocentes. Era la misma clase de bug que este mecanismo
# existe para evitar. Sin ventana, ese caso desaparece.
if [[ "$ES_PUSH" = "true" ]]; then
    RANGO_PUSH=$(dod_rango_a_publicar) || RANGO_PUSH=""
    if [[ -n "$RANGO_PUSH" ]]; then
        # El stderr del clasificador NO se descarta: si falla, su motivo es lo
        # unico que explica por que un push de documentacion no quedo exento.
        # "Sin observabilidad no hay sign-off" tambien aplica al propio gate.
        _ERR_CLASIF=$(mktemp 2>/dev/null) || _ERR_CLASIF=/dev/null
        # shellcheck disable=SC2086
        bash "${SCRIPT_DIR}/lib/dod-classify.sh" --union $RANGO_PUSH >/dev/null 2>"$_ERR_CLASIF"
        _RC_UNION=$?
        if [[ $_RC_UNION -eq 1 && "$_ERR_CLASIF" != /dev/null ]]; then
            echo "[dod] no se pudo clasificar el rango del push: $(head -1 "$_ERR_CLASIF" 2>/dev/null)" >&2
            echo "[dod] se sigue con el control normal de gates." >&2
        fi
        [[ "$_ERR_CLASIF" != /dev/null ]] && rm -f "$_ERR_CLASIF"
        # 2 = el rango entero es meta-stack o documentacion. Cualquier otro codigo
        # —incluido el 1 de "no se pudo clasificar"— sigue con el control normal:
        # un clasificador que falla no puede eximir nada.
        # Solo se AFIRMA la exencion si hay algo que eximir. `HEAD --not --remotes`
        # excluye lo alcanzable desde CUALQUIER remoto, y el push va a UNO: con
        # varios remotos el rango puede salir vacio aunque el push si publique
        # algo. Ahi la nota "todo lo que publica es documentacion" seria falsa.
        if [[ $_RC_UNION -eq 2 ]]; then
            if [[ -n "$(git rev-list $RANGO_PUSH 2>/dev/null | head -1)" ]]; then
                allow_with_note "Push exento de los gates 2 y 3: todo lo que publica es meta-stack o documentacion."
            else
                allow
            fi
        fi
    fi
fi

MODE=$(dod_mode)
# lite: spike/prototipo. Gate 1 ya paso (sigue bloqueando CRITICAL); no se exigen
# los dos subagentes. El dev queda avisado de que entrego sin review.
if [[ "$MODE" = "lite" ]]; then
    allow_with_note "SES_MODE=lite — entregado con Gate 1 solamente, sin code review ni QA/NFR. Corre /sap-gates antes de promover a QAS."
fi
# ultra: codigo camino a PRD. El anclaje por arbol ya garantiza que el approval
# cubra exactamente lo que se entrega, asi que la ventana solo es la red de
# seguridad; en ultra se acorta a la mitad para que un flag olvidado caduque
# antes ante un cambio de base o de dependencias que el arbol no captura.
if [[ "$MODE" = "ultra" ]]; then
    DOD_MAX_AGE_SECONDS=$(( DOD_MAX_AGE_SECONDS / 2 ))
fi

# El approval se valida contra el arbol que se va a entregar, no contra el reloj.
# En commit eso es el indice; en push/PR, el arbol de HEAD.
# El mismo arbol que se verifico arriba: si el approval se anclara al indice
# mientras `-a` entrega el working tree, cubriria otro contenido.
DELIVERY_TREE="$_ARBOL_ENTREGA"

# En push, un commit que ya paso los gates no tiene por que volver a pasarlos: el
# contenido es el mismo y ya se reviso. Lo que si hay que verificar es que TODOS
# los commits que se publican hayan pasado por ahi — los hechos con los hooks
# desactivados, fuera de Claude, o traidos por cherry-pick, no figuran.
if [[ "$ES_PUSH" = "true" ]]; then
    # Nada que publicar: no hay entrega.
    # Via `dod_commits_a_publicar`. OJO: sin remotos NO devuelve vacio —devuelve
    # la historia entera, que es fallar cerrado y es lo correcto—. Este comentario
    # decia lo contrario y describia el bug viejo, no el codigo de al lado. Sin
    # remoto configurado `--not --remotes` no excluye nada y devolvia la historia
    # entera, asi que este guard no disparaba y el push salia denegado culpando a
    # commits que nadie iba a publicar.
    [[ -z "$(dod_commits_a_publicar | head -1)" ]] && allow

    # El registro es un ATAJO, no un reemplazo: si todos los commits que se
    # publican ya pasaron los gates al commitear, no hace falta revisar de nuevo
    # el mismo contenido. Si falta alguno —o si el registro todavia no existe—
    # se cae al control normal: un sello que cubra el arbol de HEAD.
    A_PUBLICAR=$(dod_commits_a_publicar)
    SIN_GATE=""
    SIN_GATE_PROD=""
    CON_GATE=0
    # El trailer NO depende del registro local: es evidencia que viaja dentro del
    # commit. Exigir que el registro exista para mirarlo dejaba sin reconocer a
    # cualquier clon nuevo, y al propio caso del squash merge — que es de donde
    # salio este arreglo.
    if [[ -n "$A_PUBLICAR" ]]; then
        while IFS= read -r sha; do
            [[ -z "$sha" ]] && continue
            # Tres pruebas del mismo hecho. El TRAILER es la portatil: viaja dentro del
            # commit y sobrevive a un squash merge, que borra la rama y deja los commits
            # originales fuera de todo remoto. El registro local es un atajo de esta
            # maquina; por sha o por arbol, porque un `--amend` de solo mensaje produce
            # un sha nuevo sobre contenido ya revisado.
            _ARBOL_SHA=$(git rev-parse --verify --quiet "${sha}^{tree}" 2>/dev/null)
            # Tambien cuenta un flag que cubra el ARBOL DE ESE COMMIT. Es el caso
            # de quien commitea primero y corre `/sap-gates` despues: el commit no
            # llego a llevar trailer, pero su contenido SI se reviso.
            #
            # Esto no reabre el add-then-revert: ahi el arbol sellado es el del
            # revert —igual al del remoto— y el commit del backdoor tiene OTRO
            # arbol, asi que sigue sin quedar cubierto.
            if dod_delivery_logged "$sha" \
               || dod_delivery_tree_logged "$_ARBOL_SHA" \
               || { [[ -n "$_ARBOL_SHA" ]] \
                    && dod_flag_covers "$REVIEW_FLAG" "$_ARBOL_SHA" \
                    && dod_flag_covers "$QA_FLAG" "$_ARBOL_SHA"; }; then
                # Por sha o por arbol: un `--amend` que solo cambia el mensaje
                # produce un sha nuevo sobre contenido ya revisado.
                CON_GATE=$((CON_GATE + 1))
            elif dod_trailer_cubre_su_arbol "$sha"; then
                # Cubierto SOLO por el trailer: no hay respaldo local de que los
                # gates hayan corrido. Se acepta —es lo que hace que un squash
                # merge no vuelva a pedirlos— pero queda anotado, porque el
                # trailer se puede escribir a mano (ADR-013).
                dod_log_trailer_no_corroborado "$sha"
                CON_GATE=$((CON_GATE + 1))
            elif dod_anterior_al_mecanismo "$sha"; then
                # Anterior al mecanismo: no pudo llevar trailer ni figurar en el
                # registro. Se cuenta como exento, no como sin gatear.
                CON_GATE=$((CON_GATE + 1))
            else
                _LINEA="
  $(git log -1 --format='%h %s' "$sha" 2>/dev/null)"
                # Los TRES codigos del clasificador significan cosas distintas y
                # hay que tratarlos distinto. Colapsarlos en dos ya produjo los dos
                # errores opuestos:
                #
                #   - filtrar la lista que DECIDE dejaba el gate fail-OPEN cuando el
                #     clasificador fallaba: no entraba nada y el push salia permitido.
                #   - meter todo en la lista que decide dejaba fail-CLOSED sobre un
                #     commit meta-only, que por la tabla de la DoD solo necesita
                #     Gate 1 — y encima lo acusaba de "hooks desactivados".
                #
                # `SIN_GATE` decide; `SIN_GATE_PROD` solo se MUESTRA.
                # stderr a archivo, no a /dev/null: cuando el clasificador falla, su
                # mensaje es lo unico que dice POR QUE. Sin el, el deny culpaba al
                # commit de "hooks desactivados", que es lo que no paso.
                _ERR_SHA=$(mktemp 2>/dev/null) || _ERR_SHA=/dev/null
                bash "${SCRIPT_DIR}/lib/dod-classify.sh" "$sha" >/dev/null 2>"$_ERR_SHA"
                _RC_SHA=$?
                if [[ $_RC_SHA -ne 0 && $_RC_SHA -ne 2 && "$_ERR_SHA" != /dev/null ]]; then
                    echo "[dod] no se pudo clasificar ${sha:0:12}: $(head -1 "$_ERR_SHA" 2>/dev/null)" >&2
                fi
                [[ "$_ERR_SHA" != /dev/null ]] && rm -f "$_ERR_SHA"
                case "$_RC_SHA" in
                    2)  # Meta-stack o documentacion: `pre-commit` ya lo aprobo
                        # diciendo "alcanza con Gate 1". No puede bloquear el push.
                        CON_GATE=$((CON_GATE + 1)) ;;
                    0)  # Codigo productivo sin sellar: bloquea y se muestra.
                        SIN_GATE="${SIN_GATE}${_LINEA}"
                        SIN_GATE_PROD="${SIN_GATE_PROD:-}${_LINEA}" ;;
                    *)  # No se pudo clasificar: bloquea, sin poder decir cual.
                        # Falla CERRADO; un clasificador roto no habilita nada.
                        SIN_GATE="${SIN_GATE}${_LINEA}" ;;
                esac
            fi
        done <<< "$A_PUBLICAR"

        # El atajo NO vale si la ventana truncó la lista. `dod_commits_a_publicar`
        # corta a los `DOD_PUSH_SCAN_MAX` mas NUEVOS y `rev-list` va de nuevo a
        # viejo: lo que queda afuera es el arranque de la rama. Con 50 commits
        # sellados encima de uno sin gatear, el bucle solo veia los sellados,
        # `SIN_GATE` quedaba vacio y el push salia PERMITIDO — el commit sin
        # revisar publicado por ser viejo, no por ser inocente.
        # Se cachea: cada llamada spawnea un `git rev-list --count`, y el mensaje
        # de mas abajo la vuelve a necesitar.
        if dod_push_excede_ventana; then VENTANA_EXCEDIDA=true; else VENTANA_EXCEDIDA=false; fi
        if [[ -z "$SIN_GATE" && "$VENTANA_EXCEDIDA" = "false" ]]; then
            # La nota NO afirma POR CUAL de las tres vias quedo cubierto cada
            # commit: antes decia siempre "el resto es anterior al registro",
            # incluso cuando el motivo habia sido el trailer y no existia registro
            # alguno. Un mensaje que inventa el motivo es peor que uno que no lo da.
            allow_with_note "Push permitido: ${CON_GATE} commit(s) ya cuentan con los gates 2 y 3 (por trailer, por registro local, o por ser anteriores al mecanismo)."
        fi
    fi
fi

MISSING=""
STALE_TREE=0
# Los arboles que ESTA entrega puede publicar. En push es uno solo; en commit son
# el del indice (lo que publica `git commit -m`) y el de `-a`, que NO se contienen
# entre si.

# ¿El sello cubre esta entrega?
#
# La regla es: tiene que cubrir CADA arbol que la entrega puede publicar. Validar
# uno solo era el bypass: con un archivo staged y despues revertido en el working
# tree, el arbol de `-a` queda igual a HEAD y el del indice trae el cambio, asi
# que mirar solo el primero dejaba pasar el segundo sin que nadie lo revisara.
#
# La UNICA excepcion es la que ya existia: si dos arboles difieren solo en
# contenido NO productivo —editaste un README despues de sellar—, alcanza con que
# el sello cubra uno. Eso no reabre nada, porque la diferencia no es codigo.
check_flag() {
    local flag="$1" etiqueta="$2" arbol rc peor=0
    # Lista vacia = no se pudo calcular ningun arbol. El `for` daba CERO vueltas,
    # `peor` quedaba en 0 y el `case` lo leia como "sellado" sin haber mirado
    # nada. Es el unico lugar del aparato donde un vacio de git terminaba en OK —
    # y justo en el punto donde se decide si el approval cubre lo que se entrega.
    # (Hoy no es explotable: en ese estado `git commit` tampoco puede escribir el
    # arbol. Pero "no explotable hoy" no es el criterio de este archivo.)
    if [[ -z "$_ARBOLES_ENTREGA" ]]; then
        MISSING="${MISSING}
  - ${etiqueta} — no se pudo determinar el arbol que estas entregando"
        return 1
    fi
    for arbol in $_ARBOLES_ENTREGA; do
        dod_flag_covers "$flag" "$arbol"; rc=$?
        [[ $rc -eq 0 ]] && continue
        dod_equivalente_a_alguno "$flag" "$arbol" "$_ARBOLES_ENTREGA" && continue
        # El 2 ("cubre otro contenido") manda sobre el 1 ("falta"): es el mensaje
        # mas informativo de los dos.
        [[ $rc -eq 2 ]] && peor=2
        [[ $peor -eq 0 ]] && peor=$rc
    done
    case "$peor" in
        0) return 0 ;;
        2) STALE_TREE=1; MISSING="${MISSING}
  - ${etiqueta} — cubre OTRO contenido, no el que estas entregando" ;;
        *) MISSING="${MISSING}
  - ${etiqueta}" ;;
    esac
}

check_flag "$REVIEW_FLAG" "Gate 2 (Code Review): agente 'reviewer' sobre el diff"
check_flag "$QA_FLAG"     "Gate 3 (QA + NFR): agente 'sap-qa' con shared/non-functional-requirements.md"

# El sello de HEAD NO equivale a un sello por commit.
#
# El bucle de arriba ya determino que hay commits sin gatear en el rango que se
# publica, pero `SIN_GATE` solo alimentaba el TEXTO del deny: si los flags cubrian
# el arbol de HEAD, `MISSING` quedaba vacio, no habia deny, y el push salia
# permitido en silencio con esos commits adentro.
#
# El caso concreto: agregar codigo y revertirlo. El arbol de HEAD vuelve a ser el
# del remoto, `/sap-gates` lo sella sobre un `git diff HEAD` VACIO —el reviewer no
# ve nada— y el commit intermedio viaja al remoto sin haber pasado por nadie. Un
# `git checkout` de ese sha lo revive intacto.
#
# Es la misma clase de agujero que la heuristica de arbol que se elimino de
# `dod-common.sh`, por otra puerta. Lo que se publica son COMMITS, y cada uno
# tiene que tener su propia evidencia.
if [[ "$ES_PUSH" = "true" && -n "${SIN_GATE:-}" ]]; then
    MISSING="${MISSING}
  - Hay commits sin gatear en el rango que publica este push (ver abajo)"
fi
# La ventana excedida bloquea POR SI SOLA, aunque no haya nada que listar.
#
# El comentario de mas abajo prometia esto y el codigo no lo hacia: `MISSING`
# solo crecia con `SIN_GATE` no vacio. Si los commits mas nuevos estaban todos
# sellados y los flags cubrian HEAD, `MISSING` quedaba vacio y el commit del
# ARRANQUE —sin trailer, sin registro, sin revision— se publicaba en silencio.
if [[ "$ES_PUSH" = "true" && "${VENTANA_EXCEDIDA:-false}" = "true" ]]; then
    MISSING="${MISSING}
  - El push trae mas commits de los que inspecciona la ventana (${DOD_PUSH_SCAN_MAX})"
fi

if [[ -n "$MISSING" ]]; then
    if [[ "$STALE_TREE" = "1" ]]; then
        EXPLICACION="Ningun approval cubre el arbol que estas entregando. Se anclan al hash del
contenido revisado, asi que cualquier edicion posterior — aunque sea una linea —
deja de estar cubierta. Es deliberado: 'revise esto' tiene que significar esto y
no otra cosa.

Puede ser que hayas editado despues de correr los gates, o que otra sesion haya
sellado su propio arbol. Volve a correr /sap-gates y entrega sin tocar nada mas.

  arbol a entregar: ${DELIVERY_TREE}"
    else
        EXPLICACION="Corre /sap-gates para ejecutarlos sobre el diff actual, o pedile al dev que
confirme si quiere entregar sin ellos (SES_GATES=off)."
    fi
    if [[ "$ES_PUSH" = "true" && -n "${SIN_GATE:-}" ]]; then
        # Se muestran solo los que exigen gates, PERO unicamente si esa lista
        # acotada quedo no vacia: si quedo vacia, la clasificacion no sirvio y es
        # mejor mostrar todo que mostrar nada.
        # Los dos motivos se explican distinto, porque el diagnostico es distinto.
        # Antes todo heredaba el texto de "hooks desactivados", incluso los commits
        # que el clasificador no pudo procesar — que es exactamente lo que NO paso.
        if [[ -n "${SIN_GATE_PROD:-}" ]]; then
            EXPLICACION="${EXPLICACION}

Estos commits publican codigo productivo y no figuran en el registro de entregas
gateadas (${DOD_DELIVERY_LOG}). O se hicieron con los hooks desactivados, fuera
de Claude, o vinieron de otra rama — o quedaron fuera de la ventana de
inspeccion y no se pudo confirmar su salida generada, que es otra cosa:
${SIN_GATE_PROD}"
        fi
        if [[ "${SIN_GATE}" != "${SIN_GATE_PROD:-}" ]]; then
            EXPLICACION="${EXPLICACION}

De estos NO se pudo determinar el contenido (el clasificador fallo), asi que se
bloquean por precaucion. El motivo va por stderr:
${SIN_GATE}"
        fi
    fi
    # El aviso de recorte va FUERA del bloque de arriba, porque el caso que mas
    # lo necesita es justo cuando no hay nada que listar: si los commits de la
    # ventana estan todos cubiertos, `SIN_GATE` queda vacio y el push se deniega
    # igual —hay commits mas viejos que nadie miro— pero sin este parrafo el dev
    # recibe un deny sin una sola pista de por que.
    if [[ "$ES_PUSH" = "true" && "${VENTANA_EXCEDIDA:-false}" = "true" ]]; then
        EXPLICACION="${EXPLICACION}

Solo se inspeccionaron los ${DOD_PUSH_SCAN_MAX} commits mas nuevos y el push trae mas. Como
\`git log\` va del mas nuevo al mas viejo, lo que queda afuera es el ARRANQUE de la
rama — justo donde suele estar el commit que fuerza el bloqueo. Corre
\`git log --oneline HEAD --not --remotes\` para verlos todos.

Subir DOD_PUSH_SCAN_MAX inspecciona mas, y cuesta caro: ~82 ms por commit en el
recorrido de trailers —hasta unos 200 ms si el repo es grande o los commits no
estan sellados—, pero ~1,5 s por cada commit que toca salida generada
(plugins/, fixtures/), porque hay que materializar su arbol y correr los cuatro
emisores. Para varios cientos son minutos, no segundos. Sellar el arbol de HEAD
con /sap-gates suele salir mas barato."
    fi
    # La lista de archivos solo se imprime si hay alguno. En push, `CHANGED` sale
    # del working tree, que despues de commitear esta limpio: el deny terminaba
    # con un "Archivos productivos en esta entrega:" y nada debajo, sugiriendo que
    # el gate no encontro nada y bloqueo igual. Lo que bloquea en push son los
    # COMMITS, que ya estan listados arriba.
    # Si lo que entra a la lista es salida generada desincronizada, el remedio NO
    # es /sap-gates: es regenerar. Correr los gates igual "destraba" —el sello se
    # ancla al arbol— y commitea el bundle desincronizado, o sea que el consejo
    # equivocado ademas empeora el estado.
    # OJO CON LOS BACKTICKS DE ESTE BLOQUE.
    #
    # El texto va dentro de un string entre comillas DOBLES, asi que un backtick
    # sin escapar es sustitucion de comandos. Aca hubo uno, en la unica linea del
    # archivo donde falto el escape, y el hook terminaba EJECUTANDO
    # `node bin/ses.mjs build` en modo escritura contra el repo del dev cada vez
    # que este bloque disparaba. Medido: una edicion sin stagear en el bundle
    # desaparecia y no se recuperaba. Un PreToolUse que dice denegar estaba
    # destruyendo trabajo.
    #
    # De paso, el propio mensaje quedaba ilegible: la salida del emisor se
    # imprimia dentro del parentesis, encima del texto que explicaba el remedio.
    _COMO_DESTRABAR=""
    _RAICES_MAL=$(for _a in $_ARBOLES_ENTREGA; do dod_raices_malas_de "$_a"; done | tr -s ' ' '\n' | sort -u | tr '\n' ' ')
    if [[ -n "${_RAICES_MAL// /}" ]] \
       && printf '%s\n' "$CHANGED" | grep -qE "^($(printf '%s' "$_RAICES_MAL" | tr -s ' ' '|' | sed 's/^|//;s/|$//'))/"; then
        _COMO_DESTRABAR="

La salida generada no coincide con sus fuentes. Antes que nada:
    node bin/ses.mjs build --host claude
    node bin/ses.mjs build --host codex    --fixture
    node bin/ses.mjs build --host opencode --fixture
    node bin/ses.mjs build --host copilot  --fixture

y volve a intentar. Si el bundle queda sincronizado, esto no pide gates.

(\`pnpm run build:hosts\` hace lo mismo en un comando.)"
    fi

    _LISTA_ARCHIVOS=""
    if [[ -n "$CHANGED" ]]; then
        _LISTA_ARCHIVOS="

Archivos productivos en esta entrega:
$(echo "$CHANGED" | sed 's/^/  /')"
    fi
    deny "Definition of Done — falta correr los gates antes de entregar:
${MISSING}

${EXPLICACION}${_COMO_DESTRABAR}${_LISTA_ARCHIVOS}"
fi

# Los flags NO se consumen aca.
#
# Antes este hook intentaba adivinar si husky iba a correr, mirando si el comando
# traia `--no-verify`. Esa heuristica era fragil por diseno: el texto del comando
# no es la intencion, es evidencia parcial de la intencion. Un mensaje de commit
# largo pasado por heredoc mete su cuerpo entero en `$CMD`, y cualquier palabra
# con guion terminada en `n` disparaba la deteccion: el gate consumia los flags,
# husky corria igual, no encontraba nada, y rechazaba el commit que este hook
# acababa de aprobar. Parsear mejor solo movia el borde del fallo.
#
# Ahora el consumo se detecta por su EFECTO: lo hace .husky/post-commit, que
# corre solo si el commit ocurrio de verdad. Y si alguien desactiva los hooks,
# los flags sobreviven pero NO habilitan nada nuevo, porque estan anclados al
# hash del arbol: solo cubren ese contenido exacto. El anclaje volvio innecesaria
# toda esta rama.

type emit_stack_event >/dev/null 2>&1 && emit_stack_event "allow" '{"gates":"passed"}'
exit 0
