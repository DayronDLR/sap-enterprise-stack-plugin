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
case "$INPUT" in
    *"git commit"*|*"git push"*|*"gh pr create"*) ;;
    *) exit 0 ;;
esac

# ── Slow path ────────────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
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

# Extraer el comando real. Solo llegamos aca en entregas, asi que el costo del
# parseo es irrelevante. Si no hay parser disponible, se usa el JSON crudo:
# degradar a "revisar de mas" es preferible a dejar pasar una entrega sin gates.
CMD=""
if command -v python3 >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | python3 -c \
        "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
fi
[[ -z "$CMD" ]] && CMD="$INPUT"

# Confirmar sobre el comando real: el fast path tambien matchea si la frase
# aparece solo en `description`, o en un `echo "git push"`.
if ! echo "$CMD" | grep -qE '(^|[;&|[:space:]])(git[[:space:]]+(commit|push)|gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
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
# En commit importa lo staged; en push/PR, todo lo que difiere de HEAD.
if echo "$CMD" | grep -qE 'git[[:space:]]+commit'; then
    CHANGED=$(dod_staged_files)
    # `commit -a` / `-am` levanta tambien el working tree.
    echo "$CMD" | grep -qE 'git[[:space:]]+commit[[:space:]].*-[a-zA-Z]*a' && \
        CHANGED=$(printf '%s\n%s\n' "$CHANGED" "$(dod_changed_files)" | sort -u | sed '/^$/d')
else
    CHANGED=$(dod_changed_files)
fi

# Nada productivo (docs, markdown, config del propio Claude) -> no aplica la DoD.
#
# OJO con push: aca `CHANGED` mira el working tree, que despues de un commit esta
# limpio. Ese atajo dejaba TODO push sin control — la maquinaria de anclaje solo
# se activaba con el arbol sucio. Un push publica commits, asi que su alcance son
# los commits, no los archivos sin commitear.
ES_PUSH=false
echo "$CMD" | grep -qE '(git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)' && ES_PUSH=true
if [[ "$ES_PUSH" != "true" ]]; then
    [[ -z "$CHANGED" ]] && allow
fi

# ── SES_GATES=off ────────────────────────────────────────────────────────────
#
# AUDITORIA A12: se registra ANTES de permitir. Omitir los gates es una decision
# legitima del dev; que no quede constancia, no. Va aca y no antes porque necesita
# el alcance ya calculado — cual arbol se entrega y que archivos entran sin gates.
if [[ "${SES_GATES:-}" = "off" ]]; then
    dod_log_gates_off "${PROJECT_DIR}/logs/gates-off.log" \
        "$(dod_delivery_tree "$([[ "$ES_PUSH" = "true" ]] && echo push || echo commit)")" \
        "$CHANGED"
    allow_with_note "SES_GATES=off — Definition of Done omitida por configuracion. El codigo entra sin review ni QA. Registrado en logs/gates-off.log."
fi

# ── HOTFIX-OVERRIDE (ADR-005) ────────────────────────────────────────────────
HOTFIX=$(dod_hotfix_state)
case "$HOTFIX" in
    ok\|*)
        APPROVER="${HOTFIX#ok|}"; APPROVER="${APPROVER%%|*}"
        REASON="${HOTFIX##*|}"
        REQUESTER=$(git config user.email 2>/dev/null || echo unknown)
        dod_log_hotfix "$HOTFIX_LOG" "$REQUESTER" "$APPROVER" "$REASON"
        rm -f "${TMP_DIR}/.hotfix-override" 2>/dev/null
        allow_with_note "HOTFIX-OVERRIDE consumido. Solicitante: $REQUESTER, aprobador: $APPROVER. Gates 2+3 omitidos, Gate 1 CRITICAL sigue aplicando. Re-trabajo obligatorio en la proxima sesion."
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

# ── Gates 2 y 3 — Code Review + QA/NFR ───────────────────────────────────────
# Cambios solo al meta-stack (hooks, scripts, prompts): Gate 1 alcanza.
# En push, `CHANGED` mira el working tree y despues de un commit esta limpio, asi
# que `dod_is_meta_only ""` daba true y dejaba pasar TODO push. El alcance de un
# push son los commits: la clasificacion por archivos no aplica.
if [[ "$ES_PUSH" != "true" ]] && dod_is_meta_only "$CHANGED"; then
    allow
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
if echo "$CMD" | grep -qE 'git[[:space:]]+commit'; then
    DELIVERY_TREE=$(dod_delivery_tree commit)
else
    DELIVERY_TREE=$(dod_delivery_tree push)
fi

# En push, un commit que ya paso los gates no tiene por que volver a pasarlos: el
# contenido es el mismo y ya se reviso. Lo que si hay que verificar es que TODOS
# los commits que se publican hayan pasado por ahi — los hechos con los hooks
# desactivados, fuera de Claude, o traidos por cherry-pick, no figuran.
if [[ "$ES_PUSH" = "true" ]]; then
    # Nada que publicar: no hay entrega.
    [[ -z "$(git rev-list HEAD --not --remotes 2>/dev/null | head -1)" ]] && allow

    # El registro es un ATAJO, no un reemplazo: si todos los commits que se
    # publican ya pasaron los gates al commitear, no hace falta revisar de nuevo
    # el mismo contenido. Si falta alguno —o si el registro todavia no existe—
    # se cae al control normal: un sello que cubra el arbol de HEAD.
    A_PUBLICAR=$(dod_commits_a_publicar)
    SIN_GATE=""
    CON_GATE=0
    if [[ -n "$A_PUBLICAR" ]] && dod_registro_base >/dev/null; then
        while IFS= read -r sha; do
            [[ -z "$sha" ]] && continue
            if dod_delivery_logged "$sha" \
               || dod_delivery_tree_logged "$(git rev-parse --verify --quiet "${sha}^{tree}" 2>/dev/null)"; then
                # Por sha o por arbol: un `--amend` que solo cambia el mensaje
                # produce un sha nuevo sobre contenido ya revisado.
                CON_GATE=$((CON_GATE + 1))
            elif ! dod_anterior_al_registro "$sha"; then
                SIN_GATE="${SIN_GATE}
  $(git log -1 --format='%h %s' "$sha" 2>/dev/null)"
            fi
        done <<< "$A_PUBLICAR"

        if [[ -z "$SIN_GATE" ]]; then
            allow_with_note "Push permitido: ${CON_GATE} commit(s) figuran como entregados con los gates; el resto es anterior al registro."
        fi
    fi
fi

MISSING=""
STALE_TREE=0
check_flag() {
    local flag="$1" etiqueta="$2"
    dod_flag_covers "$flag" "$DELIVERY_TREE"
    case "$?" in
        0) return 0 ;;
        2) STALE_TREE=1; MISSING="${MISSING}
  - ${etiqueta} — cubre OTRO contenido, no el que estas entregando" ;;
        *) MISSING="${MISSING}
  - ${etiqueta}" ;;
    esac
}
check_flag "$REVIEW_FLAG" "Gate 2 (Code Review): agente 'reviewer' sobre el diff"
check_flag "$QA_FLAG"     "Gate 3 (QA + NFR): agente 'sap-qa' con shared/non-functional-requirements.md"

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
        EXPLICACION="${EXPLICACION}

Estos commits no figuran en el registro de entregas gateadas
(${DOD_DELIVERY_LOG}). Se hicieron con los hooks desactivados, fuera de Claude, o
vinieron de otra rama:
${SIN_GATE}"
    fi
    deny "Definition of Done — falta correr los gates antes de entregar:
${MISSING}

${EXPLICACION}

Archivos productivos en esta entrega:
$(echo "$CHANGED" | sed 's/^/  /')"
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
