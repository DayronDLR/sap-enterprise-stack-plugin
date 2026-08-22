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
[[ "${SES_GATES:-}" = "off" ]] && \
    allow_with_note "SES_GATES=off — Definition of Done omitida por configuracion. El codigo entra sin review ni QA."

case "${BASH_SOURCE[0]:-$0}" in
    */plugins/*)
        [[ "${SES_SKIP_DOD_GATES:-}" = "1" ]] && allow
        ;;
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
[[ -z "$CHANGED" ]] && allow

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
if dod_is_meta_only "$CHANGED"; then
    allow
fi

MODE=$(dod_mode)
# lite: spike/prototipo. Gate 1 ya paso (sigue bloqueando CRITICAL); no se exigen
# los dos subagentes. El dev queda avisado de que entrego sin review.
if [[ "$MODE" = "lite" ]]; then
    allow_with_note "SES_MODE=lite — entregado con Gate 1 solamente, sin code review ni QA/NFR. Corre /sap-gates antes de promover a QAS."
fi
# ultra: codigo camino a PRD. Una revision de hace 25 minutos no cubre lo que se
# escribio despues, asi que la ventana de los flags se acorta a la mitad.
if [[ "$MODE" = "ultra" ]]; then
    DOD_MAX_AGE_SECONDS=$(( DOD_MAX_AGE_SECONDS / 2 ))
fi

MISSING=""
dod_flag_fresh "$REVIEW_FLAG" || MISSING="${MISSING}
  - Gate 2 (Code Review): agente 'reviewer' sobre el diff"
dod_flag_fresh "$QA_FLAG" || MISSING="${MISSING}
  - Gate 3 (QA + NFR): agente 'sap-qa' con shared/non-functional-requirements.md"

if [[ -n "$MISSING" ]]; then
    deny "Definition of Done — falta correr los gates antes de entregar:
${MISSING}

Corre /sap-gates para ejecutarlos sobre el diff actual, o pedile al dev que confirme
si quiere entregar sin ellos (SES_GATES=off).

Archivos productivos en esta entrega:
$(echo "$CHANGED" | sed 's/^/  /')"
fi

# Los flags se consumen: la proxima entrega exige gates nuevos sobre el diff nuevo.
rm -f "$REVIEW_FLAG" "$QA_FLAG" 2>/dev/null
type emit_stack_event >/dev/null 2>&1 && emit_stack_event "allow" '{"gates":"passed"}'
exit 0
