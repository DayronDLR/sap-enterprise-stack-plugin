#!/bin/bash
# dod-common.sh
# Helper sourceable con la logica compartida de la Definition of Done.
#
# Antes esta logica estaba duplicada en quality-gate.sh y mandatory-review.sh, y
# ambos corrian en el hook `Stop` — que dispara al final de CADA TURNO, no al final
# de la tarea. Resultado: los 3 gates se exigian en cada prompt que tocara un
# archivo productivo, incluido un fix de una linea. Costo real medido: 2-3x tokens
# por tarea (dos subagentes completos por turno) + linters en cada cierre de turno.
#
# Modelo actual (ADR-008): los gates corren en el PUNTO DE ENTREGA —
# `git commit` / `git push` / `gh pr create` — o cuando el dev los pide con
# /sap-gates. Ver rules/DEFINITION-OF-DONE.md.
#
# Uso:
#   source "${CLAUDE_PROJECT_DIR:-.}/hooks/scripts/lib/dod-common.sh"
#   dod_changed_files            -> imprime archivos productivos (vacio si no hay)
#   dod_is_meta_only "$FILES"    -> 0 si TODO es meta-stack (.claude/, hooks/, docs/)
#   dod_flag_fresh "$FLAG_FILE"  -> 0 si el flag existe y tiene < DOD_MAX_AGE_SECONDS
#   dod_hotfix_state             -> imprime "ok|<approver>|<reason>", "invalid" o "none"
#   dod_json_escape "$texto"     -> imprime el texto como string JSON valido

DOD_MAX_AGE_SECONDS="${DOD_MAX_AGE_SECONDS:-1800}"   # 30 min

# Modo de operacion del stack (SES_MODE). Gradua cuanto exige y cuanto inyecta:
#
#   lite   spike, prototipo, exploracion. Solo Gate 1 al entregar (linters y
#          smells, que son baratos e irrenunciables). Sin refuerzo de agente.
#   full   default. Los 3 gates al entregar. Refuerzo cada N turnos.
#   ultra  codigo que va a PRD. Los 3 gates + los flags valen la mitad de tiempo,
#          para que una revision vieja no cubra codigo nuevo. Refuerzo el doble
#          de seguido.
#
# `lite` NO es una via para saltarse la calidad: Gate 1 sigue bloqueando
# CRITICAL. Es para que un spike de 20 minutos no pida dos subagentes.
dod_mode() {
    local m="${SES_MODE:-full}"
    case "$m" in
        lite|full|ultra) printf '%s' "$m" ;;
        *) printf 'full' ;;
    esac
}

# Patrones de archivo que cuentan como "codigo o configuracion ejecutable".
DOD_PRODUCTIVE_RE='\.(abap|prog|clas|cds|hdbcds|hdbcalculationview|hdbprocedure|hdbtable|js|ts|xml|json|yaml|yml|sh|sql|hdbtablefunction|hdbview|properties)$'
DOD_EXCLUDE_RE='^(\.claude/|tmp/|node_modules/|\.git/|docs/|client-docs/|coverage/|dist/|logs/|README|CHANGELOG|memory/)|\.md$'

# Archivos productivos modificados o nuevos respecto de HEAD.
dod_changed_files() {
    {
        git diff --name-only HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
    } | sort -u \
      | grep -vE "$DOD_EXCLUDE_RE" \
      | grep -E "$DOD_PRODUCTIVE_RE" \
      || true
}

# Archivos productivos que van en el commit (staged). Usado por el gate de entrega:
# lo que importa al commitear es lo que se commitea, no todo el working tree.
dod_staged_files() {
    git diff --cached --name-only 2>/dev/null \
      | grep -vE "$DOD_EXCLUDE_RE" \
      | grep -E "$DOD_PRODUCTIVE_RE" \
      || true
}

# 0 (true) si TODOS los archivos son del meta-stack: cambios al propio stack SAP,
# no a un entregable de cliente. Para estos, la DoD exige solo Gate 1.
dod_is_meta_only() {
    local files="$1"
    [[ -z "$files" ]] && return 0
    # Iterar por linea, no por palabra: un path con espacios se partiria en dos
    # y un archivo productivo podria clasificarse como meta-stack, saltandose
    # los gates 2 y 3.
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$f" in
            hooks/*|scripts/*|.github/*|orchestrator/*|config/*|rules/*|shared/*|agents/*|commands/*|plugins/*|evals/*|tests/*|settings.json|CLAUDE.md) ;;
            *) return 1 ;;
        esac
    done <<< "$files"
    return 0
}

# 0 (true) si el flag existe y es mas reciente que DOD_MAX_AGE_SECONDS.
dod_flag_fresh() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    [[ -z "$mtime" ]] && return 1
    local age=$(( $(date +%s) - mtime ))
    [[ "$age" -le "$DOD_MAX_AGE_SECONDS" ]]
}

# Estado del HOTFIX-OVERRIDE (two-person rule, ADR-005).
# Imprime: "ok|<approver>|<reason>" | "invalid" | "none"
dod_hotfix_state() {
    local flag="${1:-${CLAUDE_PROJECT_DIR:-.}/tmp/.hotfix-override}"
    [[ -f "$flag" ]] || { echo "none"; return 0; }

    local reason_line approver requester
    reason_line=$(grep -E '^REASON: ' "$flag" 2>/dev/null | head -1)
    approver=$(grep -E '^APPROVED_BY: ' "$flag" 2>/dev/null | head -1 | sed 's/^APPROVED_BY: *//')
    requester=$(git config user.email 2>/dev/null || echo "unknown")

    if ! echo "$reason_line" | grep -qE '^REASON: .{20,}'; then echo "invalid"; return 0; fi
    if [[ -z "$approver" || "$approver" == "$requester" ]]; then echo "invalid"; return 0; fi
    echo "ok|${approver}|${reason_line#REASON: }"
}

# Registra un uso de HOTFIX-OVERRIDE en logs/hotfix-overrides.log, rotando el
# archivo si supera 1MB (se mantienen 3 generaciones).
# Uso: dod_log_hotfix <log_file> <requester> <approver> <reason>
dod_log_hotfix() {
    local log="$1" requester="$2" approver="$3" reason="$4"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0

    # `wc -c` y no `stat -f %z`: en GNU coreutils `-f` es `--file-system` y
    # devuelve el block size, con lo que la rotacion nunca se disparaba.
    if [[ -f "$log" ]]; then
        local size; size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
        if [[ "${size:-0}" -gt 1048576 ]]; then
            [[ -f "${log}.2" ]] && mv "${log}.2" "${log}.3"
            [[ -f "${log}.1" ]] && mv "${log}.1" "${log}.2"
            mv "$log" "${log}.1"
        fi
    fi

    printf '[%s] user=%s approver=%s session=%s — REASON: %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$requester" "$approver" \
        "${CLAUDE_SESSION_ID:-no-session}" "$reason" >> "$log"
}

# Escapa un texto arbitrario como string JSON. Sin dependencia de python3:
# los hooks corren en cada tool call y un spawn de interprete por hook es
# latencia pura. Cubre los escapes que exige RFC 8259 para texto de mensajes.
dod_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//	/\\t}"
    s="${s//$'\r'/}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
}
