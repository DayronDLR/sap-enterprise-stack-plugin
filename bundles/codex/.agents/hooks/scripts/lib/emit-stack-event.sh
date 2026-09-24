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

# La regla de escapado vive en `json-escape.sh`, compartida con `dod-common.sh`.
# Copiarla aca habria sido una REDEFINICION, no una copia: `quality-gate.sh` y
# `delivery-gate.sh` sourcean los dos archivos.
#
# Si no esta, se usa el respaldo de abajo: perder una linea de observabilidad es
# peor que emitirla con un escapado mas pobre, y este helper nunca debe romper al
# hook que lo llama.
# shellcheck disable=SC1091
[[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/json-escape.sh" ]] \
    && source "$(dirname "${BASH_SOURCE[0]:-$0}")/json-escape.sh"

# RESPALDO si el lib no esta. El comentario de arriba prometia "se emite igual
# pero sin escapar", y no era cierto: sin `ses_json_escape` cada `$(…)` del
# `printf` daba vacio y la linea salia `{"ts":,"session":,"hook":,…}`. Lo
# encontraron los dos gates. Y `jq`, que es como se consume este archivo, aborta
# en la primera linea invalida: una sola mata la medicion del SLO entera.
#
# No es teorico: `json-escape.sh` entro en este ciclo, y cualquier plugin
# instalado de antes no lo trae.
#
# Se define SOLO si falta. Si despues se sourcea el lib de verdad —`quality-gate.sh`
# carga este archivo antes que `dod-common.sh`—, la definicion completa lo pisa.
if ! declare -F ses_json_escape >/dev/null 2>&1; then
    ses_json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\t'/\\t}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\r'/\\r}"
        # El resto de `\x01-\x1F` se QUITA: este respaldo no sabe escaparlo, y un
        # `\x1b` crudo en `CLAUDE_SESSION_ID` volvia la linea invalida para `jq`
        # (lo midio el Gate 3). Perder un caracter de control es mejor que perder
        # la linea.
        s="${s//[$'\x01'-$'\x08'$'\x0b'$'\x0c'$'\x0e'-$'\x1f']/}"
        printf '"%s"' "$s"
    }
fi
# Sin el validador, solo `{}` —el payload por defecto— se da por objeto; el resto
# va envuelto como texto, que siempre es JSON valido. El costo, dicho: en este
# modo degradado `jq '.payload.decision'` da `null`, porque el payload queda como
# `{"raw":"…"}`. La linea se conserva; los campos consultables, no.
if ! declare -F ses_json_es_objeto >/dev/null 2>&1; then
    ses_json_es_objeto() { [[ "$1" = '{}' ]]; }
fi

emit_stack_event() {
    local event="$1"
    # NO `${2:-{}}`: bash cierra la expansion en la PRIMERA `}`, asi que el
    # default queda en `{` y la `}` final se concatena como texto literal. Con
    # payload da `{"a":1}}` y sin payload da `{}` por casualidad — o sea que
    # cada linea con contenido salia como JSON invalido.
    local payload="${2:-}"
    [[ -n "$payload" ]] || payload='{}'
    local log_dir="${CLAUDE_PROJECT_DIR:-.}/logs"
    local log_file="${log_dir}/stack-events.jsonl"
    local ts session host
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    session="${CLAUDE_SESSION_ID:-unknown}"
    host=$(hostname -s 2>/dev/null || echo unknown)

    mkdir -p "$log_dir" 2>/dev/null || return 0

    # EL PAYLOAD SE VALIDA, no se mira la primera letra.
    #
    # Antes: `[[ ! "$payload" =~ ^\{ ]]` — o sea que cualquier cosa que empezara
    # con llave salia CRUDA. `{no es json` y hasta un `{` suelto rompian la linea
    # entera. Ahora lo que no parsea se envuelve como texto y la linea sale
    # valida igual.
    if ! ses_json_es_objeto "$payload" 2>/dev/null; then
        payload="{\"raw\":$(ses_json_escape "$payload" 2>/dev/null || printf '""')}"
    fi

    # TODOS los campos escapados, no solo el payload.
    #
    # `session`, `hook` y `event` venian del entorno o del llamador y se
    # interpolaban crudos con `%s`. Una comilla en `CLAUDE_SESSION_ID`, en
    # `HOOK_NAME` o en el nombre del evento rompia la linea. Medido: 6 de 6
    # entradas adversarias daban JSONL invalido, y `jq` —que es el consumo que
    # documenta docs/SLO-HOOKS.md— ABORTA en la primera, no la saltea.
    printf '{"ts":%s,"session":%s,"hook":%s,"event":%s,"host":%s,"payload":%s}\n' \
        "$(ses_json_escape "$ts")" \
        "$(ses_json_escape "$session")" \
        "$(ses_json_escape "${HOOK_NAME:-unknown}")" \
        "$(ses_json_escape "$event")" \
        "$(ses_json_escape "$host")" \
        "$payload" \
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
