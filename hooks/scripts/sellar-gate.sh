#!/bin/bash
# sellar-gate.sh — sella un gate de la DoD sobre el contenido que se entrega.
#
# Uso:  bash hooks/scripts/sellar-gate.sh review                 # Gate 2
#       bash hooks/scripts/sellar-gate.sh qa                     # Gate 3
#       bash hooks/scripts/sellar-gate.sh qa --config-trivial    # Gate 3 no aplica
#       bash hooks/scripts/sellar-gate.sh <review|qa> --nivel=<liviana|estandar|completa>
#
# `--nivel`: la profundidad con que se revisó (`lib/nivel-revision.mjs`). El script
# VUELVE A CALCULAR el nivel que exige lo que se entrega y se niega a sellar una
# revisión más liviana. `qa --nivel=liviana` es «Gate 3 no aplica»: sólo vale para
# contenido que no se ejecuta. Sin `--nivel`, se asume la revisión completa.
#
# `--config-trivial`: un ajuste chico de configuración (`lib/clase-cambio.mjs`)
# no tiene concurrencia, volumen ni locking que revisar, y el Gate 3 no aplica.
# El script VUELVE A CALCULAR la clase sobre lo que se entrega y se niega a sellar
# si no se cumple: la clase no se declara, se comprueba.
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
# Estado propio: nada de esto se toma del entorno. Un EXIGIDO exportado falsearía
# el registro de auditoría.
unset PEDIDO EXIGIDO MOTIVOS

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

# Un tercer argumento no se ignora: `--nivel=completa --nivel=liviana` tiene que
# fallar, no sellar con el primero.
if [[ $# -gt 2 ]]; then
    echo "uso: sellar-gate.sh <review|qa> [--config-trivial | --nivel=<nivel>] — sobran argumentos." >&2
    exit 1
fi

case "${1:-}" in
    review) FLAG="${PROJECT_DIR}/tmp/.review-done"; ETIQUETA="Gate 2 (Code Review)" ;;
    qa)     FLAG="${PROJECT_DIR}/tmp/.qa-nfr-done"; ETIQUETA="Gate 3 (QA + NFR)" ;;
    *)      echo "uso: sellar-gate.sh <review|qa> [--config-trivial | --nivel=<liviana|estandar|completa>]" >&2; exit 1 ;;
esac

# Profundidad de un nivel: un sello sólo vale si la revisión fue al menos tan
# profunda como la que el cambio exige.
rango_nivel() {
    case "$1" in
        config-trivial) echo 0 ;; liviana) echo 1 ;; estandar) echo 2 ;; completa) echo 3 ;;
        *) echo -1 ;;
    esac
}

# Deja en EXIGIDO el nivel que exige lo que se entrega (vacío si no se puede
# calcular) y en MOTIVOS los primeros motivos. No decide nada: lo usan el
# rechazo de `--nivel` y el registro de auditoría.
calcular_nivel() {
    EXIGIDO=""; MOTIVOS=""
    command -v node >/dev/null 2>&1 || return 0
    [[ -f "${SCRIPT_DIR}/lib/nivel-revision.mjs" ]] || return 0
    local json
    json=$(cd "$PROJECT_DIR" && node "${SCRIPT_DIR}/lib/nivel-revision.mjs" 2>/dev/null) || return 0
    EXIGIDO=$(printf '%s' "$json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).nivel||""))}catch{}})' 2>/dev/null)
    MOTIVOS=$(printf '%s' "$json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write((JSON.parse(s).motivos||[]).slice(0,5).join("\n  "))}catch{}})' 2>/dev/null)
}

if [[ "${2:-}" = "--config-trivial" ]]; then
    if [[ "${1:-}" != "qa" ]]; then
        echo "[sellar-gate] --config-trivial sólo aplica al Gate 3: el review (Gate 2) se hace igual." >&2
        exit 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "[sellar-gate] sin node no se puede comprobar la clase del cambio — NO se selló. Corré el Gate 3 completo." >&2
        exit 1
    fi
    CLASE=$(cd "$PROJECT_DIR" && node "${SCRIPT_DIR}/lib/clase-cambio.mjs" 2>/dev/null)
    # El motivo se lee con un parser de JSON: con `sed` se cortaba en la primera
    # comilla escapada y el dev se quedaba sin saber por qué.
    MOTIVO=$(printf '%s' "$CLASE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).motivo||""))}catch{process.stdout.write("no se pudo leer la clase")}})' 2>/dev/null)
    if printf '%s' "$CLASE" | grep -qF '"clase":"config-trivial"'; then
        ETIQUETA="Gate 3 (no aplica: ajuste chico de configuración)"
        PEDIDO="config-trivial"
        # Queda registro de cada entrega por el camino corto: el Gate 2 de ese
        # camino lo hace la sesión, sin subagente, y un auditor tiene que poder
        # encontrarlas y muestrearlas.
        mkdir -p "${PROJECT_DIR}/logs" 2>/dev/null && printf '%s\t%s\t%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git -C "$PROJECT_DIR" write-tree 2>/dev/null || echo sin-arbol)" "$MOTIVO" \
            >> "${PROJECT_DIR}/logs/gate-config-trivial.log"
    else
        echo "[sellar-gate] el cambio NO es un ajuste chico de configuración — NO se selló." >&2
        printf '  %s\n  Corré el Gate 3 completo.\n' "$MOTIVO" >&2
        exit 1
    fi
elif [[ "${2:-}" == --nivel=* ]]; then
    PEDIDO="${2#--nivel=}"
    case "$PEDIDO" in
        config-trivial|liviana|estandar|completa) ;;
        *) echo "[sellar-gate] nivel desconocido '${PEDIDO}': config-trivial, liviana, estandar o completa." >&2; exit 1 ;;
    esac
    if [[ "$PEDIDO" != "completa" ]]; then
        calcular_nivel
        if [[ -z "$EXIGIDO" ]]; then
            echo "[sellar-gate] no se pudo calcular el nivel que exige el cambio (sin node o sin nivel-revision.mjs) — NO se selló. Revisá con el nivel completo." >&2
            exit 1
        fi
        if [[ $(rango_nivel "$PEDIDO") -lt $(rango_nivel "$EXIGIDO") ]]; then
            echo "[sellar-gate] el cambio exige una revisión '${EXIGIDO}' y se pidió sellar una '${PEDIDO}' — NO se selló." >&2
            printf '  %s\n  Revisá con el nivel %s.\n' "$MOTIVOS" "$EXIGIDO" >&2
            exit 1
        fi
        if [[ "${1:-}" = "qa" && "$PEDIDO" = "liviana" ]]; then
            ETIQUETA="Gate 3 (no aplica: contenido que no se ejecuta)"
        elif [[ "${1:-}" = "qa" && "$PEDIDO" = "config-trivial" ]]; then
            ETIQUETA="Gate 3 (no aplica: ajuste chico de configuración)"
        else
            ETIQUETA="${ETIQUETA} (revisión ${PEDIDO})"
        fi
    fi
elif [[ -n "${2:-}" ]]; then
    echo "uso: sellar-gate.sh <review|qa> [--config-trivial | --nivel=<liviana|estandar|completa>]" >&2
    exit 1
fi

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
# Cada sello queda registrado con el nivel con que se revisó y el que exigía el
# cambio. Sin `--nivel` se sella como antes —el recálculo protege contra el error
# honesto, no contra quien sella sin declararlo—, pero queda a la vista: un
# auditor busca las líneas donde lo exigido no coincide con lo declarado.
[[ -z "${EXIGIDO+x}" ]] && calcular_nivel
mkdir -p "${PROJECT_DIR}/logs" 2>/dev/null && printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1}" "${PEDIDO:-sin-nivel}" "${EXIGIDO:-desconocido}" \
    "$(dod_delivery_tree commit-a 2>/dev/null || echo sin-arbol)" \
    >> "${PROJECT_DIR}/logs/gate-niveles.log"
echo "[sellar-gate] ${ETIQUETA} sellado sobre el contenido actual."
