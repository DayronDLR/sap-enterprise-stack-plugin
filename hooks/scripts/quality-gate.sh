#!/bin/bash
# quality-gate.sh — Gate 1 de la Definition of Done.
# Stop hook: verifica linters/smells antes de permitir que Claude cierre la sesion.
# Si CUALQUIER chequeo falla con CRITICAL/HIGH, bloquea con decision=block.

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HOTFIX_FLAG="${PROJECT_DIR}/tmp/.hotfix-override"

# Stack observability (gap #8) + SLO timing (gap #2)
HOOK_NAME="quality-gate"
# shellcheck disable=SC1091
[[ -f "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh" ]] && \
    source "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh"
type timed_section_start >/dev/null 2>&1 && timed_section_start
type emit_stack_event >/dev/null 2>&1 && emit_stack_event "start" '{}'

# HOTFIX-OVERRIDE: en Gate 1 sigue bloqueando CRITICAL (security/regresion grave)
# pero los HIGH se degradan a WARNING. El override requiere razon valida +
# segundo aprobador (gap #6 — two-person rule). Ver docs/adr/005-two-person-hotfix-approval.md
HOTFIX_ACTIVE=0
if [[ -f "$HOTFIX_FLAG" ]]; then
    REASON_LINE=$(head -1 "$HOTFIX_FLAG" 2>/dev/null)
    APPROVER_LINE=$(grep -E '^APPROVED_BY: ' "$HOTFIX_FLAG" 2>/dev/null | head -1)
    REQUESTER=$(git config user.email 2>/dev/null || echo "unknown")
    APPROVER=$(echo "$APPROVER_LINE" | sed 's/^APPROVED_BY: *//')
    if echo "$REASON_LINE" | grep -qE '^REASON: .{20,}' && [[ -n "$APPROVER" ]] && [[ "$APPROVER" != "$REQUESTER" ]]; then
        HOTFIX_ACTIVE=1
    elif echo "$REASON_LINE" | grep -qE '^REASON: .{20,}'; then
        # Razon valida pero falta segundo aprobador → rechazar con mensaje claro
        REASON_NO_APP="HOTFIX-OVERRIDE inválido: falta APPROVED_BY (segundo aprobador). Formato requerido en tmp/.hotfix-override:\nREASON: <ticket + descripcion + aprobador CAB, min 20 chars>\nAPPROVED_BY: <email distinto del solicitante ($REQUESTER)>\nVer docs/adr/005-two-person-hotfix-approval.md"
        REASON_ESC=$(printf '%s' "$REASON_NO_APP" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        type emit_stack_event >/dev/null 2>&1 && \
            emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"block\",\"reason\":\"hotfix_missing_approver\"}"
        printf '{"decision":"block","reason":%s}\n' "$REASON_ESC"
        exit 0
    fi
fi

CHANGED_FILES=$(
    {
        git diff --name-only HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
        if [[ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]]; then
            git ls-files 'hooks/scripts/__smoketest__/fixtures/*' 2>/dev/null
        fi
    } | sort -u
)

CDS_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(cds|ddls|bdef|behv)$' || true)
UI5_CHANGED=$(echo "$CHANGED_FILES" | grep -E 'webapp/.*\.(js|xml)$' || true)
JS_CHANGED=$(echo "$CHANGED_FILES"  | grep '\.js$' || true)
ABAP_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(abap|prog|clas|fugr)$' || true)
MANIFEST_CHANGED=$(echo "$CHANGED_FILES" | grep -E 'webapp/manifest\.json$' || true)

ERRORS=""

# 1) CDS lint
if [[ -n "$CDS_CHANGED" ]]; then
    CDS_RESULT=$(pnpm dlx @sap/cds-dk cds lint 2>&1) || ERRORS="${ERRORS}\n[CRITICAL] CDS lint fallo:\n${CDS_RESULT}"
fi

# 2) UI5 linter
if [[ -n "$UI5_CHANGED" ]]; then
    UI5_RESULT=$(pnpm dlx @ui5/linter 2>&1) || ERRORS="${ERRORS}\n[CRITICAL] UI5 linter fallo:\n${UI5_RESULT}"
fi

# 3) ESLint
if [[ -n "$JS_CHANGED" ]]; then
    ESLINT_RESULT=$(pnpm dlx eslint $JS_CHANGED 2>&1) || ERRORS="${ERRORS}\n[CRITICAL] ESLint fallo:\n${ESLINT_RESULT}"
fi

# 4) ABAP smell scan (CRITICAL/HIGH bloquea)
if [[ -n "$ABAP_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ABAP_RESULT=$(bash "${SCRIPT_DIR}/abap-smell-scan.sh" 2>&1)
    ABAP_EXIT=$?
    if [[ "$ABAP_EXIT" -ne 0 ]]; then
        ERRORS="${ERRORS}\n${ABAP_RESULT}"
    fi
fi

# 4.5) Clean Core scan (ABAP/CDS) — bloquea modificaciones a SAP standard y APIs no released
if [[ -n "$ABAP_CHANGED" ]] || [[ -n "$CDS_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/clean-core-scan.sh" ]]; then
        CC_RESULT=$(bash "${SCRIPT_DIR}/clean-core-scan.sh" 2>&1)
        CC_EXIT=$?
        if [[ "$CC_EXIT" -ne 0 ]]; then
            ERRORS="${ERRORS}\n${CC_RESULT}"
        fi
    fi
fi

# 4.6) ATC config drift (validate-atc-config.js) — bloquea si config/atc-*.json invalido
ATC_CHANGED=$(echo "$CHANGED_FILES" | grep -E '^config/atc-(variant|exemptions)\.json$' || true)
if [[ -n "$ATC_CHANGED" ]]; then
    if [[ -f "${PROJECT_DIR}/scripts/validate-atc-config.js" ]]; then
        ATC_RESULT=$(node "${PROJECT_DIR}/scripts/validate-atc-config.js" 2>&1)
        ATC_EXIT=$?
        if [[ "$ATC_EXIT" -ne 0 ]]; then
            ERRORS="${ERRORS}\n[CRITICAL] ATC config invalido:\n${ATC_RESULT}"
        fi
    fi
fi

# 5) Manifest UI5 (auto-validate-manifest.sh ya esta en PostToolUse, pero validamos
#    en cierre para detectar drift acumulado)
if [[ -n "$MANIFEST_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/auto-validate-manifest.sh" ]]; then
        MANIFEST_RESULT=$(bash "${SCRIPT_DIR}/auto-validate-manifest.sh" 2>&1) || \
            ERRORS="${ERRORS}\n[CRITICAL] Manifest UI5 invalido:\n${MANIFEST_RESULT}"
    fi
fi

if [[ -n "$ERRORS" ]]; then
    # En HOTFIX: degradar HIGH a WARNING, mantener bloqueo solo si hay CRITICAL
    if [[ "$HOTFIX_ACTIVE" = "1" ]]; then
        CRIT_ONLY=$(printf '%b' "$ERRORS" | grep -E '\[CRITICAL\]' || true)
        if [[ -z "$CRIT_ONLY" ]]; then
            WARN_MSG="HOTFIX-OVERRIDE activo: Gate 1 detecto HIGH pero NO CRITICAL. Permitiendo cierre con warning. Findings: $(printf '%b' "$ERRORS" | tr '\n' ' ' | head -c 500)"
            REASON_ESC=$(printf '%s' "$WARN_MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
            type emit_stack_event >/dev/null 2>&1 && \
                emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\",\"hotfix\":1}"
            printf '{"decision":"approve","systemMessage":%s}\n' "$REASON_ESC"
            exit 0
        fi
        # Si hay CRITICAL, ni siquiera HOTFIX lo permite
    fi
    REASON=$(printf "Gate 1 (Quality) fallo. Resolver antes de cerrar:%s" "$ERRORS")
    REASON_ESC=$(printf '%s' "$REASON" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"block\"}"
    printf '{"decision":"block","reason":%s}\n' "$REASON_ESC"
    exit 0
fi

type emit_stack_event >/dev/null 2>&1 && \
    emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\"}"
echo '{"decision":"approve"}'
exit 0
