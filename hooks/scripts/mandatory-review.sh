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
  *) ;;   # Fuera de plugins/: el opt-out del plugin no aplica.
esac
# AUDITORIA A12: queda constancia de la omision, con arbol y archivos.
if [[ "${SES_GATES:-}" = "off" ]]; then
    dod_log_gates_off "${PROJECT_DIR}/logs/gates-off.log" \
        "$(dod_delivery_tree commit)" "$(dod_staged_files)"
    say "[DoD] SES_GATES=off -> gates 2+3 omitidos. Registrado en logs/gates-off.log."
    exit 0
fi

# Consumo puro, sin evaluar el working tree. Lo usa .husky/post-commit, que
# corre DESPUES de que HEAD se movio: ahi `git diff HEAD` da vacio y la
# evaluacion normal saldria por "sin archivos productivos" sin llegar nunca a
# consumir. La decision de si hacian falta gates ya la tomo pre-commit.
if [[ "${DOD_CONSUME_ONLY:-}" = "1" ]]; then
    # Un commit meta-only no exigio gates 2+3, asi que tampoco puede gastarlos:
    # antes se los llevaba puestos y el dev perdia una revision que seguia siendo
    # valida para su contenido.
    if dod_is_meta_only "$(dod_commit_files)"; then
        say "[DoD] Commit meta-only: no consume approvals (no los necesitaba)."
        exit 0
    fi
    # Se libera SOLO el arbol entregado. Los approvals de otros arboles —de otra
    # sesion trabajando en paralelo— quedan intactos.
    ENTREGADO=$(git rev-parse --verify --quiet "HEAD^{tree}" 2>/dev/null)
    # Se chequea el rc: `dod_con_lock` puede devolver 75 (no consiguio exclusion
    # y NO ejecuto la operacion). Anunciar "consumido" sin haberlo consumido
    # deja el approval vivo para la proxima entrega del mismo arbol — el flag
    # seguiria cubriendo contenido ya entregado.
    RC_REL=0
    dod_flag_release "$REVIEW_FLAG" "$ENTREGADO" || RC_REL=$?
    dod_flag_release "$QA_FLAG" "$ENTREGADO" || RC_REL=$?
    if [[ "$RC_REL" -ne 0 ]]; then
        say "[DoD] AVISO: no se pudo consumir el approval del arbol ${ENTREGADO:0:12} (rc=${RC_REL}). Sigue vigente: la proxima entrega del mismo contenido pasaria sin revision nueva."
    else
        say "[DoD] Approval del arbol ${ENTREGADO:0:12} consumido."
    fi
    exit 0
fi

CHANGED=$(dod_changed_files)
if [[ -z "$CHANGED" ]]; then
    say "[DoD] Sin archivos productivos modificados — gates 2+3 no aplican."
    exit 0
fi

if dod_is_meta_only "$CHANGED"; then
    say "[DoD] Solo cambios al meta-stack — alcanza con Gate 1."
    exit 0
fi

# Este script solo corre desde .husky/pre-commit, o sea que la entrega es un
# commit: el arbol relevante es el del indice.
DELIVERY_TREE=$(dod_delivery_tree commit)

MISSING=0
check_flag() {
    local flag="$1" etiqueta="$2"
    dod_flag_covers "$flag" "$DELIVERY_TREE"
    case "$?" in
        0) return 0 ;;
        2) MISSING=1; say "  OTRO ARBOL  ${etiqueta} — cubre otro contenido: editaste despues, u otra sesion sello lo suyo" ;;
        *) MISSING=1; say "  PENDIENTE   ${etiqueta}" ;;
    esac
}
check_flag "$REVIEW_FLAG" "Gate 2 (Code Review) — agente 'reviewer' sobre el diff"
check_flag "$QA_FLAG"     "Gate 3 (QA + NFR)  — agente 'sap-qa' + shared/non-functional-requirements.md"

if [[ "$MISSING" = "0" ]]; then
    say "[DoD] Gates 2 y 3 cubren el arbol ${DELIVERY_TREE:0:12}."
    # Este camino NO consume: es el que corre .husky/pre-commit, y consumir aca
    # seria prematuro (`git commit` sin -m abre el editor DESPUES del hook, asi
    # que el commit todavia puede abortarse). El consumo vive en post-commit,
    # via DOD_CONSUME_ONLY.
    exit 0
fi

say ""
say "Archivos productivos sin revisar:"
say "$(echo "$CHANGED" | sed 's/^/  /')"
say ""
say "Corre /sap-gates para ejecutarlos, y entrega sin tocar nada mas: los approvals"
say "se anclan al hash del contenido revisado (arbol ${DELIVERY_TREE:0:12})."
exit 1
