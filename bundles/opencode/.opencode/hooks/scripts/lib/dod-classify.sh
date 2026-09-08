#!/bin/bash
# dod-classify.sh — clasifica el contenido de UN commit.
#
# Existe para que el gate local y CI usen exactamente la misma regla. Duplicar la
# clasificacion en dos lenguajes es como se termina con un CI que aprueba lo que
# el hook rechaza, o al reves — y nadie sabe cual tiene razon.
#
# Uso:  bash hooks/scripts/lib/dod-classify.sh <sha>
#
# Exit codes:
#   0  el commit trae codigo productivo que EXIGE los gates 2 y 3
#   2  no aplica: meta-stack, o sin archivos productivos
#   1  no se pudo clasificar (git fallo) — falla CERRADO
#
# Por stdout, la lista de archivos productivos cuando el exit es 0.

set -u

SHA="${1:-}"
[[ -n "$SHA" ]] || { echo "uso: dod-classify.sh <sha>" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/dod-common.sh" || { echo "no se pudo cargar dod-common.sh" >&2; exit 1; }

# `--root` para que el primer commit de un repo tambien liste sus archivos: sin
# eso, `diff-tree` no imprime nada para un commit sin padre y el commit inicial
# se clasificaba como "sin productivos".
ARCHIVOS=$(git -c core.quotePath=false diff-tree --no-commit-id --name-only -r --root "$SHA" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "git diff-tree fallo sobre ${SHA}: $(printf '%s' "$ARCHIVOS" | head -1)" >&2
    exit 1
fi

PROD=$(printf '%s\n' "$ARCHIVOS" \
    | grep -vE "$DOD_EXCLUDE_RE" \
    | grep -E "$DOD_PRODUCTIVE_RE" || true)

[[ -z "$PROD" ]] && exit 2
dod_is_meta_only "$PROD" && exit 2

printf '%s\n' "$PROD"
exit 0
