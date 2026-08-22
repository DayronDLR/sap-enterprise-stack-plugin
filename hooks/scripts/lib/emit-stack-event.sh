#!/bin/bash
# emit-stack-event.sh
# Helper sourceable para que cualquier hook emita un evento estructurado a
# logs/stack-events.jsonl. Permite observabilidad del propio stack (gap #8) +
# medicion de SLO/SLI de hooks (gap #2).
#
# Uso (dentro de un hook):
#   source "${CLAUDE_PROJECT_DIR:-.}/hooks/scripts/lib/emit-stack-event.sh"
#   emit_stack_event "quality-gate.start" '{"changed_files":3}'
#   ...trabajo...
#   emit_stack_event "quality-gate.end" "{\"duration_ms\":${DURATION_MS},\"decision\":\"$DECISION\"}"
#
# Formato JSONL (una linea por evento):
# {"ts":"2026-06-24T22:01:33Z","session":"abc","hook":"quality-gate","event":"end",
#  "duration_ms":1234,"decision":"allow","host":"hostname","payload":{...}}

emit_stack_event() {
    local event="$1"
    local payload="${2:-{}}"
    local log_dir="${CLAUDE_PROJECT_DIR:-.}/logs"
    local log_file="${log_dir}/stack-events.jsonl"
    local ts session host
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    session="${CLAUDE_SESSION_ID:-unknown}"
    host=$(hostname -s 2>/dev/null || echo unknown)

    mkdir -p "$log_dir" 2>/dev/null || return 0

    # Escapar comillas en payload si no es JSON valido (defensa basica).
    # Si payload no empieza con '{', envolverlo como string.
    if [[ ! "$payload" =~ ^\{ ]]; then
        payload="{\"raw\":\"${payload//\"/\\\"}\"}"
    fi

    printf '{"ts":"%s","session":"%s","hook":"%s","event":"%s","host":"%s","payload":%s}\n' \
        "$ts" "$session" "${HOOK_NAME:-unknown}" "$event" "$host" "$payload" \
        >> "$log_file" 2>/dev/null || true
}

# Helper para timing: emite start/end con duration_ms.
# Uso: timed_section "quality-gate" "core" "<command>"
timed_section_start() {
    SECTION_START_MS=$(($(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")/1000000))
}

timed_section_end_ms() {
    local now=$(($(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")/1000000))
    echo $((now - SECTION_START_MS))
}
