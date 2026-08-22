#!/bin/bash
# mandatory-review.sh — estado de los Gates 2 (Code Review) y 3 (QA + NFR).
#
# HISTORIA: hasta ADR-008 este script era un hook `Stop` que devolvia
# decision=block hasta que el modelo corriera los agentes `reviewer` y `sap-qa`.
# Como `Stop` dispara al final de CADA TURNO, eso exigia dos subagentes completos
# por prompt — 2-3x tokens por tarea, revisando codigo a medio escribir.
#
# AHORA: no es un hook. Es un utilitario CLI que reporta que gates faltan.
# Lo consumen:
#   - hooks/scripts/delivery-gate.sh  (PreToolUse en git commit/push/gh pr create)
#   - commands/sap-gates.md           (/sap-gates, invocacion explicita del dev)
#   - .husky/pre-commit               (red de seguridad para commits fuera de Claude)
#
# Salida: texto plano. Exit code 0 = gates cubiertos, 1 = faltan gates.
# Con --quiet solo devuelve el exit code.

set -u

QUIET=0
for arg in "$@"; do
    [[ "$arg" = "--quiet" ]] && QUIET=1
done

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TMP_DIR="${PROJECT_DIR}/tmp"
REVIEW_FLAG="${TMP_DIR}/.review-done"
QA_FLAG="${TMP_DIR}/.qa-nfr-done"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/lib/dod-common.sh" ]]; then
    echo "[DoD] lib/dod-common.sh no encontrado — no se puede evaluar el estado de los gates." >&2
    exit 0
fi
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/dod-common.sh"

say() { [[ "$QUIET" = "1" ]] || printf '%s\n' "$1"; }

# Opt-out para consumidores del plugin.
case "${BASH_SOURCE[0]:-$0}" in
  */plugins/*)
    if [ "${SES_SKIP_DOD_GATES:-}" = "1" ]; then
      say "[DoD] SES_SKIP_DOD_GATES=1 -> gates 2+3 omitidos (opt-out del plugin)."
      exit 0
    fi
    ;;
esac
[[ "${SES_GATES:-}" = "off" ]] && { say "[DoD] SES_GATES=off -> gates 2+3 omitidos."; exit 0; }

CHANGED=$(dod_changed_files)
if [[ -z "$CHANGED" ]]; then
    say "[DoD] Sin archivos productivos modificados — gates 2+3 no aplican."
    exit 0
fi

if dod_is_meta_only "$CHANGED"; then
    say "[DoD] Solo cambios al meta-stack — alcanza con Gate 1."
    exit 0
fi

MISSING=0
dod_flag_fresh "$REVIEW_FLAG" || { MISSING=1; say "  PENDIENTE  Gate 2 (Code Review) — agente 'reviewer' sobre el diff"; }
dod_flag_fresh "$QA_FLAG"     || { MISSING=1; say "  PENDIENTE  Gate 3 (QA + NFR)  — agente 'sap-qa' + shared/non-functional-requirements.md"; }

if [[ "$MISSING" = "0" ]]; then
    say "[DoD] Gates 2 y 3 cubiertos (validos por $((DOD_MAX_AGE_SECONDS / 60)) min)."
    exit 0
fi

say ""
say "Archivos productivos sin revisar:"
say "$(echo "$CHANGED" | sed 's/^/  /')"
say ""
say "Corre /sap-gates para ejecutarlos."
exit 1
