#!/bin/bash
# session-close-note.sh — aviso NO bloqueante al cerrar un turno.
#
# Reemplaza a los tres hooks `Stop` anteriores (echo fijo + quality-gate +
# mandatory-review), que corrian al final de cada turno y bloqueaban el cierre.
#
# Este solo avisa, UNA vez por sesion, que hay trabajo sin revisar y que
# /sap-gates existe. Nunca bloquea: los gates ahora se exigen al entregar
# (delivery-gate.sh) o cuando el dev los pide. Ver ADR-008.

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TMP_DIR="${PROJECT_DIR}/tmp"
NOTE_FLAG="${TMP_DIR}/.close-note-$(printf '%s' "${CLAUDE_SESSION_ID:-nosession}" | tr -c 'a-zA-Z0-9' '_')"

# Ya avisamos en esta sesion: salir antes de hacer cualquier trabajo.
[[ -f "$NOTE_FLAG" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Aviso opcional: si falta la libreria, simplemente no se avisa.
[[ -f "${SCRIPT_DIR}/lib/dod-common.sh" ]] || exit 0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/dod-common.sh"

CHANGED=$(dod_changed_files)
[[ -z "$CHANGED" ]] && exit 0
dod_is_meta_only "$CHANGED" && exit 0

COUNT=$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ')

mkdir -p "$TMP_DIR" 2>/dev/null
touch "$NOTE_FLAG" 2>/dev/null

echo "[DoD] ${COUNT} archivo(s) productivo(s) modificado(s). Los gates de review/QA corren al commitear, o cuando pidas /sap-gates."
exit 0
