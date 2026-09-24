#!/bin/bash
# dod-classify.sh — clasifica el contenido de UN commit.
#
# Existe para que el gate local y CI usen exactamente la misma regla. Duplicar la
# clasificacion en dos lenguajes es como se termina con un CI que aprueba lo que
# el hook rechaza, o al reves — y nadie sabe cual tiene razon.
#
# Uso:  bash hooks/scripts/lib/dod-classify.sh <sha>
#       bash hooks/scripts/lib/dod-classify.sh --union <rev-range>
#
# Exit codes (modo <sha>):
#   0  el commit trae codigo productivo que EXIGE los gates 2 y 3
#   2  no aplica: meta-stack, o sin archivos productivos
#   1  no se pudo clasificar (git fallo) — falla CERRADO
#
# Por stdout, la lista de archivos productivos cuando el exit es 0.
#
# MODO UNION. Para decidir si un PUSH entero queda exento no hace falta clasificar
# commit por commit: alcanza con preguntar si ALGUN commit del rango toca codigo
# productivo no-meta. `dod_is_meta_only` exige que TODOS los archivos sean meta,
# asi que la union del rango es meta-only si y solo si cada commit lo es.
#
# Eso importa porque la version anterior clasificaba de a un commit, a 2 procesos
# `git` cada uno, y para acotar el costo habia una ventana de inspeccion de 50.
# Esa ventana era el bug: al excederse se desactivaba la exencion y un push de 120
# commits de SOLO documentacion terminaba denegado — la misma clase de falla que
# este mecanismo existe para evitar. Con una sola pasada de `git log` el rango
# entero se resuelve de una, sin ventana y sin truncar nada.
#
# `--union <rev-range>` aplica la MISMA regla (las mismas variables y la misma
# `dod_is_meta_only` de dod-common.sh), asi que no hay una segunda implementacion
# que pueda divergir. Exit 2 = el rango entero es meta/documentacion; 0 = hay
# codigo productivo; 1 = git fallo, que falla CERRADO igual que el modo individual.

set -u

SHA="${1:-}"
[[ -n "$SHA" ]] || { echo "uso: dod-classify.sh <sha> | --union <rev-range>" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/dod-common.sh" || { echo "no se pudo cargar dod-common.sh" >&2; exit 1; }

# ── Modo union ───────────────────────────────────────────────────────────────
# Resuelve un rango entero con una sola pasada de git. La regla es la de abajo,
# no una copia: mismas variables, misma `dod_is_meta_only`.
if [[ "$SHA" = "--union" ]]; then
    shift
    [[ $# -gt 0 ]] || { echo "uso: dod-classify.sh --union <rev-range>" >&2; exit 1; }
    # `--cc` da los archivos que un merge aporta por su cuenta y `--root` los del
    # commit inicial, igual que el modo individual.
    #
    # `--root` NO es decorativo aca, aunque con la config por defecto parezca
    # no-op: `git log` lo aplica solo si `log.showRoot` esta en true, que es el
    # default. Con `log.showRoot=false` el commit raiz desaparece de la lista y un
    # repo cuyo PRIMER commit trae codigo productivo salia EXENTO — otra vez el
    # veredicto dependiendo de la config del dev.
    #
    # `--no-renames` NO es opcional: es lo que hace que los dos modos vean la
    # misma lista. `git log` es porcelain y respeta `diff.renames`, que viene en
    # `true` desde git 2.9; `git diff-tree` es plumbing y NO lo respeta. Con un
    # rename detectado, `--name-only` imprime SOLO el destino, asi que
    # `git mv srv/app.js hooks/scripts/app.js` hacia desaparecer el origen
    # productivo de la union: el push salia EXENTO mientras `ses gates --ci`
    # —que clasifica commit por commit— lo rechazaba. Es justo el "un CI que
    # aprueba lo que el hook rechaza" que la cabecera de este archivo dice evitar.
    #
    # Peor todavia, el veredicto pasaba a depender de la config del dev
    # (`diff.renames`, `diff.renameLimit`): dos maquinas, dos respuestas sobre el
    # mismo commit.
    #
    # Se alinea la porcelain con la plumbing, no al reves: poner `-M` en el modo
    # individual AGRANDA la exencion en vez de achicarla.
    #
    # stderr va a un archivo APARTE, no a `2>&1`. La auditoria A3 ya enseño que
    # mezclarlos mete los warnings de git en la lista de paths: una linea con
    # `.js` adentro pasa el filtro por extension e inventa un archivo cambiado.
    # Aca eso solo puede SACAR la exencion, pero la regla es la misma.
    _ERR_UNION=$(mktemp 2>/dev/null) || _ERR_UNION=/dev/null
    # `diff.ignoreSubmodules=none` es el segundo eje del mismo problema que
    # `--no-renames`: `git log` respeta esa config del dev y `git diff-tree` no,
    # asi que con `ignoreSubmodules=all` el bump de un submodulo desaparecia de la
    # union y no del modo individual. Hoy no es explotable —un path de submodulo
    # no matchea `DOD_PRODUCTIVE_RE`— pero el compromiso es que el veredicto NO
    # dependa de la configuracion local, y eso lo rompia en silencio.
    ARCHIVOS=$(git -c core.quotePath=false -c diff.ignoreSubmodules=none \
        log --format='' --name-only --cc --root --no-renames "$@" 2>"$_ERR_UNION")
    RC_LOG=$?
    if [[ $RC_LOG -ne 0 ]]; then
        echo "git log fallo sobre el rango: $(head -1 "$_ERR_UNION" 2>/dev/null)" >&2
        [[ "$_ERR_UNION" != /dev/null ]] && rm -f "$_ERR_UNION"
        exit 1
    fi
    [[ "$_ERR_UNION" != /dev/null ]] && rm -f "$_ERR_UNION"

    # La salida generada se excluye SOLO si el emisor confirma que es la suya.
    # `DOD_GENERADOS_OK=1` lo pone el gate despues de correr `ses build --check`;
    # sin esa confirmacion la salida cuenta como productiva (falla cerrado).
    # UNA sola implementacion del filtro: `dod_filtrar_productivos`. Antes este
    # bloque la reimplementaba, y cuando la funcion aprendio a contar el markdown
    # de los bundles como productivo (porque en un stack de agentes ESE markdown
    # es el programa), esta copia no se entero: el commit denegaba y el push
    # permitia el mismo backdoor.
    PROD=$(printf '%s\n' "$ARCHIVOS" | dod_filtrar_productivos | sort -u)
    [[ -z "$PROD" ]] && exit 2
    # Salida generada NO confirmada: no se exime por meta. `plugins/*` esta en la
    # allowlist de `dod_is_meta_only` —y ahi vive el motor de gates que se
    # distribuye—, asi que un backdoor escrito a mano salia como "meta-stack".
    if [[ "${DOD_GENERADOS_OK:-0}" != "1" ]] && dod_toca_generados "$ARCHIVOS"; then
        printf '%s\n' "$PROD"; exit 0
    fi
    dod_is_meta_only "$PROD" && exit 2
    printf '%s\n' "$PROD"
    exit 0
fi

# Los MERGE commits necesitan otra invocacion.
#
# `diff-tree` sin `-m`/`--cc` no imprime NADA para un commit con dos padres, asi
# que un merge se clasificaba como "sin productivos" y quedaba exento — en el
# gate local, en `pre-push` y en CI, que usan este mismo script. Basta resolver
# un conflicto escribiendo cualquier cosa, o `--no-commit` y agregar un archivo
# antes de cerrar el merge, para publicar codigo que nadie reviso.
#
# `--cc` lista exactamente lo que el merge aporta por su cuenta: los archivos que
# difieren de TODOS los padres, o sea la resolucion. Un merge limpio no aporta
# nada y sigue saliendo exento, que es correcto: su contenido son los commits de
# la rama, y esos se clasifican por separado.
# stderr a archivo aparte, igual que el modo union: con `2>&1` un warning de git
# entra a la lista de paths y, si trae un `.js` adentro, pasa el filtro por
# extension e inventa un archivo cambiado. Es la leccion de la auditoria A3.
_ERR_IND=$(mktemp 2>/dev/null) || _ERR_IND=/dev/null
if [[ $(git rev-list --no-walk --count "${SHA}^@" 2>/dev/null) -gt 1 ]]; then
    ARCHIVOS=$(git -c core.quotePath=false -c diff.ignoreSubmodules=none \
        diff-tree --cc --no-commit-id --name-only -r "$SHA" 2>"$_ERR_IND")
    RC_DIFF=$?
else
    # `--root` para que el primer commit de un repo tambien liste sus archivos:
    # sin eso, `diff-tree` no imprime nada para un commit sin padre y el commit
    # inicial se clasificaba como "sin productivos".
    ARCHIVOS=$(git -c core.quotePath=false -c diff.ignoreSubmodules=none \
        diff-tree --no-commit-id --name-only -r --root "$SHA" 2>"$_ERR_IND")
    RC_DIFF=$?
fi
if [[ $RC_DIFF -ne 0 ]]; then
    echo "git diff-tree fallo sobre ${SHA}: $(head -1 "$_ERR_IND" 2>/dev/null)" >&2
    [[ "$_ERR_IND" != /dev/null ]] && rm -f "$_ERR_IND"
    exit 1
fi
[[ "$_ERR_IND" != /dev/null ]] && rm -f "$_ERR_IND"

# Los arboles GENERADOS por los emisores (`fixtures/` y `plugins/` — `dist/` NO se exime nunca) se
# excluyen aca tambien, no solo en `dod_staged_files`. Cuando se filtraban en una
# sola punta, el mismo cambio salia EXENTO al commitear y DENEGADO al pushear —
# acusado de "hooks desactivados, fuera de Claude", sobre un commit que el propio
# hook acababa de aprobar. Sincronizar los cuatro hosts toca `fixtures/` siempre,
# asi que era el caso mas frecuente de este repo.
#
# Es correcto ademas por lo que dice el comentario de `DOD_GENERADOS_RE`: son
# copias de una fuente que ya se clasifica por su cuenta.
# Ver el modo union: la salida generada se excluye solo si el emisor la confirma.
# Mismo filtro compartido que el modo `--union`, por la misma razon.
PROD=$(printf '%s\n' "$ARCHIVOS" | dod_filtrar_productivos)

[[ -z "$PROD" ]] && exit 2
# Ver el modo union: la salida generada no confirmada no se exime por meta.
if [[ "${DOD_GENERADOS_OK:-0}" != "1" ]] && dod_toca_generados "$ARCHIVOS"; then
    printf '%s\n' "$PROD"; exit 0
fi
dod_is_meta_only "$PROD" && exit 2

printf '%s\n' "$PROD"
exit 0
