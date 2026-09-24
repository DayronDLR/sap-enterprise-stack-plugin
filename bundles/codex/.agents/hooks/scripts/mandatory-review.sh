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
    # El rc se lee, igual que en `delivery-gate.sh`. Era la tercera reincidencia
    # del mismo patron: el helper propaga 1 cuando el log no queda escrito —su
    # cabecera dice que existe para eso— y este consumidor anunciaba el registro
    # igual. Una entrega sin gates que ademas no deja rastro contradice A12.
    if dod_log_gates_off "${PROJECT_DIR}/logs/gates-off.log" \
        "$(dod_delivery_tree commit)" "$(dod_staged_files)"; then
        say "[DoD] SES_GATES=off -> gates 2+3 omitidos. Registrado en logs/gates-off.log."
    else
        say "[DoD] SES_GATES=off -> gates 2+3 omitidos."
        say "[DoD] ATENCION: el registro en logs/gates-off.log NO se pudo escribir."
        say "[DoD] Esta entrega queda sin rastro auditable."
    fi
    exit 0
fi

# Consumo puro, sin evaluar el working tree. Lo usa .husky/post-commit, que
# corre DESPUES de que HEAD se movio: ahi `git diff HEAD` da vacio y la
# evaluacion normal saldria por "sin archivos productivos" sin llegar nunca a
# consumir. La decision de si hacian falta gates ya la tomo pre-commit.
# LA SEÑAL ES UN ARGUMENTO, NO UNA VARIABLE DE ENTORNO.
#
# Era `DOD_CONSUME_ONLY=1` en el entorno, y esa es la cuarta variable de la misma
# clase en este ciclo: estado del gate que bash importa del entorno y se lee
# ANTES de escribirse. Las otras tres —`_DOD_RAICES_*`, `_DOD_GEN_KEY`,
# `_DOD_NONCE`— se cerraron una por una con un nonce, mirando el caso y no la
# clase. Esta seguia viva a diez lineas de distancia, y es la peor de las cuatro:
# no altera un veredicto, SALTEA LA EVALUACION ENTERA de los gates 2 y 3 en la
# red de husky. Reproducido: con la variable exportada, un commit con codigo
# productivo sin revisar sale rc=0 y sin una linea en ningun log —a diferencia de
# `SES_GATES=off`, que si queda registrado.
#
# Un argumento lo pone QUIEN INVOCA. Una variable de entorno la pone cualquiera:
# un `.envrc`, un wrapper de shell, un IDE que exporta de mas. Esa es la
# diferencia que cierra la clase, y por eso la variable se ignora incluso si
# viene seteada.
_CONSUMO_PURO=no
for _arg in "$@"; do
    [[ "$_arg" = "--consume-only" ]] && _CONSUMO_PURO=si
done

if [[ "$_CONSUMO_PURO" = "si" ]]; then
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

# El flag se resuelve ANTES de calcular CHANGED: `dod_filtrar_productivos` lo lee
# en el momento de la llamada, asi que calcularlo primero dejaba los generados
# adentro y el husky denegaba el mismo sync que el hook aprobaba — la mitad
# exacta del problema que esta unificacion vino a cerrar.
#
# DOS arboles, a proposito, y conviene ser exacto sobre cual hace que:
#
#   - `commit-a` (superconjunto: indice + tracked modificado) para VERIFICAR la
#     salida generada. Es el conservador: un `plugins/` sucio en el working tree
#     endurece el veredicto, no lo ablanda.
#   - `commit` (el indice) para COMPROBAR los approvals, porque esto corre desde
#     `.husky/pre-commit` y lo que se commitea es el indice.
#
# Una version anterior de este comentario afirmaba que la asimetria estaba
# "cerrada". No lo estaba, y funcionaba de casualidad: `sellar-gate.sh` sella los
# DOS arboles, asi que el flag cubria los dos casos. El dia que el sellador
# sellara uno solo, este script denegaba en silencio un commit que el gate de
# entrega ya habia aprobado. Ahora la comprobacion tiene el mismo respaldo que
# `delivery-gate.sh`: si el flag no cubre el indice pero cubre el superconjunto y
# la diferencia no es codigo productivo, vale.
# El rc se verifica, por lo mismo que en `delivery-gate.sh`: una lista recortada
# hace que la exencion por salida generada se afirme habiendo verificado un solo
# arbol.
if ! _ARBOLES_HUSKY=$(dod_arboles_de_entrega commit); then
    say "[DoD] no se pudieron calcular los arboles de entrega (ver arriba)."
    say "[DoD] la red de husky NO pudo verificar nada: revisa el estado del repo."
    exit 1
fi
_ARBOL_HUSKY=$(printf '%s\n' "$_ARBOLES_HUSKY" | sed '/^$/d' | tail -1)
# La lista COMPLETA, igual que el gate de entrega: la exencion por salida
# generada solo vale si cada arbol candidato coincide con sus emisores. Pasar uno
# solo era el bypass de `plugins/` staged-y-revertido.
dod_resolver_generados_ok commit-a "$(git -c core.quotePath=false diff --cached --name-only 2>/dev/null
    git -c core.quotePath=false diff --name-only 2>/dev/null)" "$_ARBOLES_HUSKY"
# El rc se verifica: `dod_changed_files` documenta que PROPAGA el error justamente
# para que nadie concluya "no hay archivos productivos" a partir de un fallo de
# git. `$( )` captura stdout y tira el rc, asi que el vacio de un error y el vacio
# de "no hay nada" eran el mismo valor — y este script elegia el segundo, dejando
# pasar el commit. Es el mismo mecanismo que mantuvo escondido el bypass por
# `core.quotePath`, en el caller que quedo suelto.
CHANGED=$(dod_changed_files) || {
    say "[DoD] no se pudo listar los archivos productivos (git fallo)."
    say "[DoD] la red de husky NO pudo verificar nada: revisa el estado del repo."
    exit 1
}
if [[ -z "$CHANGED" ]]; then
    say "[DoD] Sin archivos productivos modificados — gates 2+3 no aplican."
    exit 0
fi

if dod_alcanza_gate1 "$CHANGED"; then
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
        2) if [[ "$_ARBOL_HUSKY" = "$DELIVERY_TREE" ]]; then
               # Un solo arbol en la lista: no hay con que comparar, y decir
               # "cubre otro contenido" manda al dev a buscar una edicion que no
               # hizo.
               # No es "no se pudo calcular": son dos arboles que dieron el
               # MISMO hash (el indice y el working tree coinciden), asi que no
               # hay un arbol alternativo contra el cual probar equivalencia.
               # Decir lo otro mandaba al dev a debuggear un problema de calculo
               # que no existio.
               MISSING=1; say "  OTRO ARBOL  ${etiqueta} — cubre otro contenido; indice y working tree coinciden, no hay arbol alternativo con que comparar"
               return 1
           fi
           if [[ -n "$_ARBOL_HUSKY" ]] \
              && dod_arboles_equivalentes "$DELIVERY_TREE" "$_ARBOL_HUSKY" \
              && dod_flag_covers "$flag" "$_ARBOL_HUSKY"; then
               return 0
           fi
           MISSING=1; say "  OTRO ARBOL  ${etiqueta} — cubre otro contenido: editaste despues, u otra sesion sello lo suyo" ;;
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
    # via `--consume-only`.
    exit 0
fi

say ""
say "Archivos productivos sin revisar:"
say "$(echo "$CHANGED" | sed 's/^/  /')"
say ""
say "Corre /sap-gates para ejecutarlos, y entrega sin tocar nada mas: los approvals"
say "se anclan al hash del contenido revisado (arbol ${DELIVERY_TREE:0:12})."

# El caso que dejaba al dev en un bucle, detectado donde SI se puede detectar.
#
# `git commit <ruta>` no entrega el indice ni el working tree entero: git arma un
# TERCER arbol —HEAD mas esa ruta— y lo commitea ignorando el indice. Ese arbol no
# existe hasta que el commit arranca, asi que `/sap-gates` no lo puede sellar. El
# dev corria los gates, reintentaba, volvia a fallar, y el mensaje le decia otra
# vez "corre /sap-gates". Reproducido 3 de 3, igual con `--only` y con `-i`.
#
# El primer intento de avisar comparaba el arbol entregado contra la lista de
# candidatos, y era CODIGO MUERTO: los dos salen de `dod_delivery_tree`, asi que
# en un commit parcial dan el mismo valor y la condicion era falsa POR
# CONSTRUCCION. Nunca disparo.
#
# (Una version anterior de este parrafo decia que los dos "honran el
# GIT_INDEX_FILE que git exporta al hook". Eso dejo de ser cierto por un rato,
# cuando `dod_delivery_tree commit` paso a copiar siempre del indice real, y
# volvio a serlo despues. La razon por la que la condicion no sirve no depende de
# eso: sirve o no sirve porque los dos valores salen del mismo lugar.)
#
# El señalador real es ese mismo `GIT_INDEX_FILE`: en un commit parcial apunta a
# `<gitdir>/next-index-<pid>.lock`, y en uno normal al indice de siempre.
#
# Y se DENIEGA aca, antes de Gate 1 y de los sellos: el tercer arbol no se puede
# sellar —los subconjuntos posibles son exponenciales—, asi que el deny es el
# estado terminal igual. Llegar antes le ahorra al dev el ciclo entero para
# recibir despues un diagnostico equivocado.
_ruta_canonica() {
    local d b
    d=$(cd "$(dirname "$1")" 2>/dev/null && pwd) || return 1
    b=$(basename "$1")
    printf '%s/%s' "$d" "$b"
}
if [[ -n "${GIT_INDEX_FILE:-}" ]]; then
    _INDICE_REAL="$(git rev-parse --git-dir 2>/dev/null)/index"
    _A=$(_ruta_canonica "$GIT_INDEX_FILE" 2>/dev/null || echo "$GIT_INDEX_FILE")
    _B=$(_ruta_canonica "$_INDICE_REAL" 2>/dev/null || echo "$_INDICE_REAL")
    if [[ "$_A" != "$_B" ]]; then
        say ""
        say "Estas commiteando con ruta (nombrando archivos, o con --only / -i)."
        say ""
        say "Eso arma un arbol propio —HEAD mas esa ruta— que no existe hasta este"
        say "momento, asi que /sap-gates no lo pudo haber sellado. Correr los gates"
        say "de nuevo NO va a destrabarlo."
        say ""
        say "El camino que funciona:"
        say "    git add <ruta>   y despues commitea sin nombrar rutas"
        exit 1
    fi
fi

exit 1
