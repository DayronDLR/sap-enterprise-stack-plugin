#!/bin/bash
# mandatory-review.sh
# Stop hook (Gate 2 + Gate 3 de la Definition of Done).
#
# Gate 2 — Code Review: detecta diff de la sesion y exige al modelo correr al
#                       agente `reviewer` sobre ese diff antes de cerrar.
# Gate 3 — QA + NFR  : exige al agente `09-qa-testing` validar el checklist NFR.
#
# Este script NO invoca subagentes por si mismo (no puede). Lo que hace es:
#   1) Detectar si hubo cambios productivos en la sesion (codigo o config ejecutable).
#   2) Verificar si en el contexto reciente del Stop ya se ejecutaron review + QA.
#   3) Si NO se ejecutaron, devolver decision=block con instrucciones explicitas
#      para que Claude corra los dos agentes antes de cerrar.
#
# La señal de "ya se ejecutaron" se basa en marcadores temporales escritos por
# el modelo en tmp/.review-done y tmp/.qa-nfr-done (creados via Bash tras
# completar cada gate). Edad maxima: 30 minutos (mas viejo = invalido).

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TMP_DIR="${PROJECT_DIR}/tmp"
REVIEW_FLAG="${TMP_DIR}/.review-done"
QA_FLAG="${TMP_DIR}/.qa-nfr-done"
HOTFIX_FLAG="${TMP_DIR}/.hotfix-override"
HOTFIX_LOG="${PROJECT_DIR}/logs/hotfix-overrides.log"
MAX_AGE_SECONDS=1800   # 30 min

# Stack observability + SLO timing
HOOK_NAME="mandatory-review"
# shellcheck disable=SC1091
[[ -f "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh" ]] && \
    source "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh"
type timed_section_start >/dev/null 2>&1 && timed_section_start
type emit_stack_event >/dev/null 2>&1 && emit_stack_event "start" '{}'

mkdir -p "$TMP_DIR" "${PROJECT_DIR}/logs" 2>/dev/null

# 0) HOTFIX-OVERRIDE: si existe tmp/.hotfix-override con razon valida +
#    segundo aprobador, permitir cierre con WARNING (no con CRITICAL).
#    Two-person rule: gap #6 — ver docs/adr/005-two-person-hotfix-approval.md
#    Formato del archivo:
#      REASON: <ticket + descripcion, min 20 chars>
#      APPROVED_BY: <email distinto del solicitante git config user.email>
if [[ -f "$HOTFIX_FLAG" ]]; then
    REASON_LINE=$(head -1 "$HOTFIX_FLAG" 2>/dev/null)
    APPROVER_LINE=$(grep -E '^APPROVED_BY: ' "$HOTFIX_FLAG" 2>/dev/null | head -1)
    REQUESTER=$(git config user.email 2>/dev/null || echo "unknown")
    APPROVER=$(echo "$APPROVER_LINE" | sed 's/^APPROVED_BY: *//')
    HOTFIX_OK=0
    if echo "$REASON_LINE" | grep -qE '^REASON: .{20,}' && [[ -n "$APPROVER" ]] && [[ "$APPROVER" != "$REQUESTER" ]]; then
        HOTFIX_OK=1
    fi
    if [[ "$HOTFIX_OK" = "1" ]]; then
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        USER_ID="${USER:-unknown}"
        SESSION_ID="${CLAUDE_SESSION_ID:-no-session}"
        # Rotacion: si log >1MB, mover a .1 (mantener 3 generaciones).
        # NOTA: `stat -f %z` en Linux GNU NO falla — interpreta `-f` como
        # `--file-system` y devuelve el block size (4096), causando que la
        # rotacion nunca se dispare. Usamos `wc -c` que es portable.
        if [[ -f "$HOTFIX_LOG" ]]; then
            LOG_SIZE=$(wc -c < "$HOTFIX_LOG" 2>/dev/null | tr -d ' ')
            LOG_SIZE=${LOG_SIZE:-0}
            if [[ "$LOG_SIZE" -gt 1048576 ]]; then
                [[ -f "${HOTFIX_LOG}.2" ]] && mv "${HOTFIX_LOG}.2" "${HOTFIX_LOG}.3"
                [[ -f "${HOTFIX_LOG}.1" ]] && mv "${HOTFIX_LOG}.1" "${HOTFIX_LOG}.2"
                mv "$HOTFIX_LOG" "${HOTFIX_LOG}.1"
            fi
        fi
        echo "[$TS] user=$USER_ID approver=$APPROVER session=$SESSION_ID — $REASON_LINE" >> "$HOTFIX_LOG"
        # consumir el flag (no reusable entre sesiones)
        rm -f "$HOTFIX_FLAG" 2>/dev/null
        WARN_MSG="HOTFIX-OVERRIDE activo. Solicitante: $REQUESTER, aprobador: $APPROVER. Gates 2+3 omitidos. Razon: ${REASON_LINE#REASON: }. Logged en logs/hotfix-overrides.log. Ambos asumen el riesgo."
        type emit_stack_event >/dev/null 2>&1 && \
            emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\",\"hotfix\":1}"
        printf '{"decision":"approve","systemMessage":"%s"}\n' "$WARN_MSG"
        exit 0
    fi
fi


# 1) Detectar archivos productivos modificados o nuevos
CHANGED=$(
    { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } \
        | sort -u \
        | grep -vE '^(\.claude/|tmp/|node_modules/|\.git/|docs/|client-docs/|README|CHANGELOG|\.md$|memory/)' \
        | grep -E '\.(abap|prog|clas|cds|hdbcds|hdbcalculationview|hdbprocedure|hdbtable|js|ts|xml|json|yaml|yml|sh|sql|hdbtablefunction|hdbview|properties)$' \
        || true
)

# Si no hay archivos productivos modificados, no aplica el DoD de codigo
if [[ -z "$CHANGED" ]]; then
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\",\"reason\":\"no_productive_files\"}"
    echo '{"decision":"approve"}'
    exit 0
fi

# Solo cambios en hooks/, scripts/, .claude config -> meta-stack, gates 2+3 no aplican
META_ONLY=true
for f in $CHANGED; do
    case "$f" in
        hooks/*|scripts/*|.github/*|orchestrator/*|config/*|rules/*|shared/*|agents/*|commands/*|plugins/*|settings.json|CLAUDE.md)
            : # meta-stack
            ;;
        *)
            META_ONLY=false
            break
            ;;
    esac
done

if [[ "$META_ONLY" = "true" ]]; then
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\",\"reason\":\"meta_only\"}"
    echo '{"decision":"approve"}'
    exit 0
fi

# 2) Chequear flags de review/QA con edad maxima
now=$(date +%s)
is_fresh() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    [[ -z "$mtime" ]] && return 1
    local age=$((now - mtime))
    [[ "$age" -le "$MAX_AGE_SECONDS" ]]
}

REVIEW_OK=false
QA_OK=false
is_fresh "$REVIEW_FLAG" && REVIEW_OK=true
is_fresh "$QA_FLAG"     && QA_OK=true

if [[ "$REVIEW_OK" = "true" ]] && [[ "$QA_OK" = "true" ]]; then
    # Limpiar flags para forzar nueva validacion en la proxima sesion
    rm -f "$REVIEW_FLAG" "$QA_FLAG" 2>/dev/null
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\"}"
    echo '{"decision":"approve"}'
    exit 0
fi

# 3) Construir mensaje de bloqueo
MISSING=""
[[ "$REVIEW_OK" = "false" ]] && MISSING="${MISSING}\\n- Gate 2 (Code Review): invocar agente 'reviewer' sobre el diff de la sesion. Tras completar, ejecutar: touch tmp/.review-done"
[[ "$QA_OK" = "false" ]]     && MISSING="${MISSING}\\n- Gate 3 (QA + NFR): invocar agente '09-qa-testing' con el checklist 'agents/09-qa-testing/nfr-checklist.md'. Tras completar, ejecutar: touch tmp/.qa-nfr-done"

REASON="Definition of Done — gates pendientes antes de cerrar:${MISSING}\\n\\nArchivos productivos detectados: $(echo "$CHANGED" | tr '\n' ' ')\\n\\nReferencia: rules/DEFINITION-OF-DONE.md y shared/non-functional-requirements.md"

type emit_stack_event >/dev/null 2>&1 && \
    emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"block\"}"
# JSON escape (basico) — reemplazar saltos reales por \\n ya hechos arriba
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
