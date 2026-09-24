#!/bin/bash
# sellar-gate.sh — sella un gate de la DoD sobre el contenido que se entrega.
#
# Uso:  bash hooks/scripts/sellar-gate.sh review   # Gate 2
#       bash hooks/scripts/sellar-gate.sh qa       # Gate 3
#
# POR QUE EXISTE. La receta de sellado vivia como PROSA en seis archivos
# markdown distintos —`commands/sap-gates.md`, `agents/reviewer.md`,
# `agents/09-qa-testing/*`, `commands/sap-nfr-check.md`, `sap-cleancore-check.md`,
# `sap-techlead.md`— a los dos lados de una comparacion por hash, y **nadie la
# validaba**. El resultado fue el esperable:
#
#   - `/sap-gates` se corrigio para sellar los dos arboles y `agents/reviewer.md`
#     quedo sellando uno solo: el mismo bug, vivo en el otro productor.
#   - Tres de los seis usaban `touch`, que crea un archivo VACIO —y
#     `dod_flag_covers` lo trata como ausente—, asi que el Gate 3 no se podia
#     sellar siguiendo sus propias instrucciones.
#   - `/sap-gates` escribia con `>>` crudo: sin lock, sin techo, sin
#     idempotencia. Medido: 30 sellados dejaban 32 lineas, y con el archivo
#     crecido un append concurrente perdia 2 a 5 sellos de 40.
#
# Una receta, un lugar. El markdown ahora invoca esto.
#
# SE SELLAN LOS DOS ARBOLES, por razones distintas:
#   - el del INDICE (`git write-tree`) alimenta el trailer `SES-Gated-Tree` que
#     estampa `.husky/prepare-commit-msg`, o sea el nivel de git y CI;
#   - el de `commit-a` es el que exige el gate local, porque `git commit -a`
#     entrega tambien lo modificado sin stagear.
# Sellar uno solo deja el otro camino sin cubrir.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# El fallback es el TOPLEVEL del repo, no el CWD. `delivery-gate.sh` usa `.` y
# esto usaba `$(pwd)`: invocado desde un subdirectorio, el sello se escribia en
# `<subdir>/tmp/` y el gate lo buscaba en otro lado. Atarlo al repo hace que los
# dos miren el mismo archivo desde cualquier directorio.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# La lib se resuelve desde la UBICACION DEL SCRIPT, no desde el CWD. Con ruta
# relativa, en el repo del stack andaba y en el proyecto de un consumidor del
# plugin fallaba — dejando medio sello y un deny cuyo consejo ("volve a correr
# /sap-gates") fallaba igual la vez siguiente.
if [[ ! -f "${SCRIPT_DIR}/lib/dod-common.sh" ]]; then
    echo "[sellar-gate] no encuentro ${SCRIPT_DIR}/lib/dod-common.sh — NO se sello nada." >&2
    exit 1
fi
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/dod-common.sh"

case "${1:-}" in
    review) FLAG="${PROJECT_DIR}/tmp/.review-done"; ETIQUETA="Gate 2 (Code Review)" ;;
    qa)     FLAG="${PROJECT_DIR}/tmp/.qa-nfr-done"; ETIQUETA="Gate 3 (QA + NFR)" ;;
    *)      echo "uso: sellar-gate.sh <review|qa>" >&2; exit 1 ;;
esac

RC=0
for tipo in commit commit-a; do
    ARBOL=$(dod_delivery_tree "$tipo" 2>/dev/null)
    if [[ -z "$ARBOL" ]]; then
        echo "[sellar-gate] no se pudo calcular el arbol '${tipo}' — NO se sello." >&2
        RC=1; continue
    fi
    # Via `dod_flag_seal`: toma el lock, acota el archivo y es idempotente.
    if ! dod_flag_seal "$FLAG" "$ARBOL"; then
        echo "[sellar-gate] fallo el sellado de '${tipo}' sobre ${FLAG}." >&2
        RC=1
    fi
done

if [[ $RC -ne 0 ]]; then
    echo "[sellar-gate] ${ETIQUETA}: el sello quedo INCOMPLETO. La entrega va a seguir bloqueada." >&2
    exit 1
fi
echo "[sellar-gate] ${ETIQUETA} sellado sobre el contenido actual."
