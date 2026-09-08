#!/bin/bash
# dod-common.sh
# Helper sourceable con la logica compartida de la Definition of Done.
#
# Antes esta logica estaba duplicada en quality-gate.sh y mandatory-review.sh, y
# ambos corrian en el hook `Stop` — que dispara al final de CADA TURNO, no al final
# de la tarea. Resultado: los 3 gates se exigian en cada prompt que tocara un
# archivo productivo, incluido un fix de una linea. Costo real medido: 2-3x tokens
# por tarea (dos subagentes completos por turno) + linters en cada cierre de turno.
#
# Modelo actual (ADR-008): los gates corren en el PUNTO DE ENTREGA —
# `git commit` / `git push` / `gh pr create` — o cuando el dev los pide con
# /sap-gates. Ver rules/DEFINITION-OF-DONE.md.
#
# Uso:
#   source "${CLAUDE_PROJECT_DIR:-.}/hooks/scripts/lib/dod-common.sh"
#   dod_changed_files            -> imprime archivos productivos (vacio si no hay)
#   dod_is_meta_only "$FILES"    -> 0 si TODO es meta-stack (.claude/, hooks/, docs/)
#   dod_flag_fresh "$FLAG_FILE"  -> 0 si el flag existe y tiene < DOD_MAX_AGE_SECONDS
#   dod_delivery_tree "commit"   -> hash del arbol que se va a entregar
#   dod_flag_covers "$FLAG" "$T" -> 0 cubre, 1 ausente/vencido, 2 cubre OTRO arbol
#   dod_hotfix_state             -> imprime "ok|<approver>|<reason>", "invalid" o "none"
#   dod_json_escape "$texto"     -> imprime el texto como string JSON valido

# Red de seguridad, NO el control principal.
#
# El control real es el anclaje al hash del arbol (dod_flag_covers): si lo que se
# entrega es byte a byte lo que se reviso, la revision sigue valiendo aunque
# hayan pasado horas. El tiempo solo existe para que un flag olvidado no aplique
# tras un cambio de base o de dependencias que el arbol no captura.
#
# Antes eran 30 min y ERA el control: un ciclo real de dos gates con agentes
# tarda mas que eso, asi que el primero vencia mientras el segundo trabajaba.
DOD_MAX_AGE_SECONDS="${DOD_MAX_AGE_SECONDS:-86400}"   # 24 h

# Modo de operacion del stack (SES_MODE). Gradua cuanto exige y cuanto inyecta:
#
#   lite   spike, prototipo, exploracion. Solo Gate 1 al entregar (linters y
#          smells, que son baratos e irrenunciables). Sin refuerzo de agente.
#   full   default. Los 3 gates al entregar. Refuerzo cada N turnos.
#   ultra  codigo que va a PRD. Los 3 gates + los flags valen la mitad de tiempo,
#          para que una revision vieja no cubra codigo nuevo. Refuerzo el doble
#          de seguido.
#
# `lite` NO es una via para saltarse la calidad: Gate 1 sigue bloqueando
# CRITICAL. Es para que un spike de 20 minutos no pida dos subagentes.
dod_mode() {
    local m="${SES_MODE:-full}"
    case "$m" in
        lite|full|ultra) printf '%s' "$m" ;;
        *) printf 'full' ;;
    esac
}

# Patrones de archivo que cuentan como "codigo o configuracion ejecutable".
# Los hooks de git no tienen extension, asi que van por path. Un cambio en
# .husky/ altera cuando y como se enforcean los gates: es codigo productivo.
DOD_PRODUCTIVE_RE='\.(abap|prog|clas|cds|hdbcds|hdbcalculationview|hdbprocedure|hdbtable|js|mjs|cjs|ts|mts|cts|xml|json|yaml|yml|sh|sql|hdbtablefunction|hdbview|properties)$|^\.husky/'
DOD_EXCLUDE_RE='^(\.claude/|tmp/|node_modules/|\.git/|docs/|client-docs/|coverage/|dist/|logs/|README|CHANGELOG|memory/)|\.md$'

# ── Descubrimiento de archivos: falla CERRADO ───────────────────────────────
#
# AUDITORIA A3. Los tres scanners y el gate descubren archivos con
# `git diff --name-only HEAD 2>/dev/null`. Si git falla —repo sin HEAD, indice
# corrupto, git ausente— el comando devuelve VACIO y el gate concluye "no hay
# nada que revisar" y aprueba. Es el mismo mecanismo que mantuvo escondido el
# bypass por `core.quotePath` durante meses: los fallos se veian como "limpio".
#
# `dod_git_paths` separa las dos situaciones:
#   git responde y no hay archivos  -> vacio, exito (0). No hay nada, correcto.
#   git FALLA                       -> exit 1 + motivo por stderr. El llamador
#                                      NO puede interpretarlo como "limpio".
#
# Uso: dod_git_paths [--con-fixtures]   (imprime un path por linea)
dod_git_paths() {
    local con_fixtures=0
    [[ "${1:-}" = "--con-fixtures" ]] && con_fixtures=1

    # stdout y stderr SEPARADOS. Con `2>&1` un warning de git ("warning: unable to
    # access ...") entraba a la lista de paths y podia pasar el filtro por
    # extension, inventando un archivo cambiado.
    local diff_out ls_out rc_diff rc_ls err_diff err_ls
    err_diff=$(mktemp) ; err_ls=$(mktemp)
    diff_out=$(git -c core.quotePath=false diff --name-only HEAD 2>"$err_diff"); rc_diff=$?
    ls_out=$(git -c core.quotePath=false ls-files --others --exclude-standard 2>"$err_ls"); rc_ls=$?

    if [[ $rc_diff -ne 0 ]]; then
        printf '[DoD] no se pudo listar los archivos modificados (git diff exit %s): %s\n' \
            "$rc_diff" "$(head -2 "$err_diff" | tr '\n' ' ')" >&2
        rm -f "$err_diff" "$err_ls"; return 1
    fi
    if [[ $rc_ls -ne 0 ]]; then
        printf '[DoD] no se pudo listar los archivos nuevos (git ls-files exit %s): %s\n' \
            "$rc_ls" "$(head -2 "$err_ls" | tr '\n' ' ')" >&2
        rm -f "$err_diff" "$err_ls"; return 1
    fi
    rm -f "$err_diff" "$err_ls"

    {
        printf '%s\n' "$diff_out"
        printf '%s\n' "$ls_out"
        if [[ $con_fixtures -eq 1 ]]; then
            git -c core.quotePath=false ls-files 'hooks/scripts/__smoketest__/fixtures/*' 2>/dev/null || true
        fi
    } | sed '/^$/d' | sort -u
}

# 0 (true) si el archivo se puede leer para escanearlo.
#
# Un archivo BORRADO sigue apareciendo en `git diff --name-only`, y no poder
# leerlo es lo esperado: no hay nada que escanear. Pero un archivo que EXISTE y
# no se puede leer es otra cosa — el scan no ocurrio, y decir "limpio" seria
# falso. El llamador distingue con `dod_no_legible`.
dod_es_legible() { [[ -r "$1" ]]; }
dod_no_legible() { [[ -e "$1" && ! -r "$1" ]]; }

# Arboles GENERADOS por los emisores. Se escanea la FUENTE, no la salida.
#
# Sin esto, un template ABAP vendored copiado a `fixtures/` se reportaba una vez
# por host —el mismo archivo, cuatro veces— y encima sobre contenido de terceros
# que el stack no edita. El hallazgo era real en el archivo original y ya se
# evalua ahi; repetirlo en las copias solo entrena a ignorar el gate.
DOD_GENERADOS_RE='^(fixtures/|plugins/|dist/)'

# Archivos productivos modificados o nuevos respecto de HEAD.
# `core.quotePath` (default: on) hace que git cite y escape cualquier path no
# ASCII: `srv/articulo.js` sale como `"srv/art\303\255culo.js"`. Con las comillas,
# el path deja de matchear `\.js$` y el archivo se vuelve INVISIBLE para el gate:
# entregaba sin gates 2 y 3. En un stack en espanol eso no es hipotetico.
# `-c core.quotePath=false` lo apaga por invocacion, sin tocar la config del dev.
dod_changed_files() {
    local paths
    # Si el descubrimiento falla, se propaga: quien llama no puede concluir
    # "no hay archivos productivos" a partir de un error de git.
    paths=$(dod_git_paths) || return 1
    printf '%s\n' "$paths" \
      | grep -vE "$DOD_EXCLUDE_RE" \
      | grep -vE "$DOD_GENERADOS_RE" \
      | grep -E "$DOD_PRODUCTIVE_RE" \
      || true
}

# Archivos productivos que van en el commit (staged). Usado por el gate de entrega:
# lo que importa al commitear es lo que se commitea, no todo el working tree.
dod_staged_files() {
    git -c core.quotePath=false diff --cached --name-only 2>/dev/null \
      | grep -vE "$DOD_EXCLUDE_RE" \
      | grep -vE "$DOD_GENERADOS_RE" \
      | grep -E "$DOD_PRODUCTIVE_RE" \
      || true
}

# 0 (true) si TODOS los archivos son del meta-stack: cambios al propio stack SAP,
# no a un entregable de cliente. Para estos, la DoD exige solo Gate 1.
# NOTA sobre `.husky/`: NO esta en la allowlist de abajo a proposito, asi que un
# cambio ahi exige los 3 gates, mientras que `hooks/scripts/` se conforma con el
# Gate 1. La asimetria es deliberada: `.husky/` decide si los hooks corren, o
# sea, si los gates existen. Es la unica pieza que no deberia poder debilitarse
# a si misma bajo un gate mas liviano.
#
# `hooks/scripts/` tiene una propiedad parecida y hoy SI es meta-only. Endurecer
# eso cambiaria el nivel de exigencia de casi todos los commits del stack, asi
# que queda como decision abierta del dueno del repo, no de un fix puntual.
#
# PORTABILIDAD MULTI-HOST (ADR-012). Entra UNA sola entrada nueva, y con nombre
# propio: `schemas/ses-*.schema.json`.
#
# El patron tiene que ser especifico porque ESTE ARCHIVO SE ENVIA AL CLIENTE
# dentro del plugin. Un `schemas/` a secas convertia en meta-only al `schemas/`
# de cualquier proyecto CAP u OData que instale el stack — contratos de API,
# fixtures con logica — y esos archivos habrian entregado sin gates 2 y 3 en el
# repo del cliente. Una allowlist que viaja necesita nombres que no colisionen.
# Por lo mismo NO se agregan `emitters/` ni `fixtures/`: todavia no existen, y
# cuando existan van namespaceados.
#
# Quedan FUERA a proposito, junto a `.husky/`:
#
#   bin/ lib/    motor de gates (`ses gates`, `ses guard`). ADR-013 lo vuelve el
#                mecanismo primario de la DoD en los 4 hosts.
#   emitters/    traduciran la DoD al bundle de cada host. Un emisor que omite
#                un hook por bug hace que ese gate no exista en ese host — mismo
#                efecto que desactivarlo, y no lo atrapa ningun linter.
#   stack.manifest.json
#                driver operativo de los 4 bundles. `validate-manifest.js` atrapa
#                rutas rotas y contradicciones, pero no atrapa intencion: un
#                `capabilities: ["exec"]` agregado a un agente que no deberia
#                tener shell valida perfecto. Eso lo ve un review, no un schema.
#
# HONESTIDAD SOBRE EL ALCANCE DE ESTE CRITERIO: `hooks/*` y `plugins/*` ya estan
# en la allowlist, y ahi vive el motor de gates actual — incluida la copia que se
# publica. O sea que el criterio "la pieza que decide si los gates existen no
# puede debilitarse a si misma" hoy se aplica a lo nuevo, no a lo que ya estaba.
# Cerrar esa brecha cambia el nivel de exigencia de casi todos los commits del
# stack y es decision del dueno del repo, no de este cambio.
dod_is_meta_only() {
    local files="$1"
    [[ -z "$files" ]] && return 0
    # Iterar por linea, no por palabra: un path con espacios se partiria en dos
    # y un archivo productivo podria clasificarse como meta-stack, saltandose
    # los gates 2 y 3.
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # `schemas/../srv/evil.js` empieza con un prefijo permitido y termina en
        # otro lado. Git normaliza sus paths, asi que no es explotable desde los
        # llamadores reales, pero la clasificacion no debe depender de eso.
        case "$f" in */../*|../*|*/..) return 1 ;; *) ;; esac  # El resto sigue.
        # Los schemas del stack se chequean con `[[ =~ ]]`, no con `case`: en un
        # patron de `case` el `*` CRUZA las barras, asi que
        # `schemas/ses-*.schema.json` tambien matchea
        # `schemas/ses-account/PurchaseOrder.schema.json` — justo el archivo de
        # cliente que el patron pretendia excluir. `[^/]+` ancla a un segmento.
        # Los demas patrones de abajo SI quieren ser recursivos.
        [[ "$f" =~ ^schemas/ses-[^/]+\.schema\.json$ ]] && continue
        case "$f" in
            hooks/*|scripts/*|.github/*|orchestrator/*|config/*|rules/*|shared/*|agents/*|commands/*|plugins/*|evals/*|tests/*|settings.json|CLAUDE.md) ;;
            *) return 1 ;;
        esac
    done <<< "$files"
    return 0
}

# Arbol que se va a entregar, segun el tipo de entrega.
#
#   commit -> el arbol del INDICE: es exactamente lo que se va a commitear.
#   push / PR -> el arbol de HEAD: ahi lo que se entrega son commits ya hechos,
#                y el indice ya no es lo relevante.
#
# `git write-tree` escribe objetos de arbol sueltos como efecto colateral. Son
# inofensivos y los recoge el `gc`; se menciona para que no sorprenda.
dod_delivery_tree() {
    if [[ "${1:-commit}" = "commit" ]]; then
        git write-tree 2>/dev/null
    else
        # `--verify` es lo que hace que un repo sin commits devuelva vacio en vez
        # de la cadena literal "HEAD^{tree}", que producia el mensaje equivocado
        # ("el codigo cambio despues") cuando en realidad no hay HEAD.
        git rev-parse --verify --quiet "HEAD^{tree}" 2>/dev/null
    fi
}

# Registro de entregas efectivamente gateadas.
#
# Existe por dos razones que resultaron ser la misma. La primera: `git push` no
# tenia forma de saber si los commits que publica pasaron los gates, asi que
# terminaba sin control (el atajo de "nada cambio" lo dejaba pasar con el arbol
# limpio). La segunda: cuando un flag desaparecia, la ausencia era
# indistinguible de "nunca se sello", y eso costo cinco rondas de diagnostico.
#
# Un registro de lo que SI paso resuelve las dos: el push verifica contra el, y
# cualquiera puede ver que se aprobo y cuando.
#
# Vive en logs/, que esta gitignored: es un ATAJO LOCAL, no el registro de
# auditoria. No viaja entre clones, y eso esta bien — en un clon nuevo no hay
# registro, el atajo no aplica y el push cae al control normal de sellos. Falla
# cerrado, que es la direccion correcta.
DOD_DELIVERY_LOG="${DOD_DELIVERY_LOG:-logs/gate-deliveries.log}"

dod_delivery_log_path() {
    printf '%s/%s' "${CLAUDE_PROJECT_DIR:-.}" "$DOD_DELIVERY_LOG"
}

# Cuantas lineas se barren buscando la base del registro. Acotado a proposito:
# tras un rebase que reescribe shas, TODAS las lineas quedan muertas y el barrido
# spawnea un `git cat-file` por cada una. Medido sin techo: 20.000 lineas = 83
# segundos en cada push, y un hook `PreToolUse` que tarda eso se lee como un
# cuelgue. Si en las primeras N no hay ninguna viva, no hay base utilizable y el
# push cae al control normal de sellos — falla cerrado.
DOD_REGISTRO_SCAN_MAX="${DOD_REGISTRO_SCAN_MAX:-200}"
DOD_REGISTRO_MAX_LINEAS="${DOD_REGISTRO_MAX_LINEAS:-2000}"

# Anota que un commit se entrego con los gates satisfechos.
dod_log_delivery() {
    local sha="$1" tree="$2" archivo lineas
    archivo=$(dod_delivery_log_path)
    mkdir -p "$(dirname "$archivo")" 2>/dev/null
    # Rotacion ANTES de escribir. Al reves, la entrega recien anotada se iba con
    # el archivo rotado y el registro activo quedaba vacio: el commit que acababa
    # de pasar los gates no figuraba en ningun lado.
    #
    # El registro crece una linea por commit gateado, para siempre, y el costo
    # del peor caso crece con el. Mismo patron que dod_log_hotfix.
    # El `2>/dev/null` de `wc` no cubre el fallo del REDIRECT del shell, que
    # ocurre antes: sin este guard, la primera corrida escupe "No such file or
    # directory" a stderr.
    lineas=0
    [[ -f "$archivo" ]] && lineas=$(wc -l < "$archivo" 2>/dev/null | tr -d ' ')
    if [[ "${lineas:-0}" -ge "$DOD_REGISTRO_MAX_LINEAS" ]]; then
        [[ -f "${archivo}.1" ]] && mv "${archivo}.1" "${archivo}.2" 2>/dev/null
        mv "$archivo" "${archivo}.1" 2>/dev/null
        # Rotar mueve la frontera hacia adelante: lo rotado pasa a contar como
        # historia anterior a la adopcion. Es la degradacion aceptable — la
        # alternativa es un barrido sin techo en cada push.
    fi
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sha" "$tree" >> "$archivo" 2>/dev/null
}

# 0 (true) si ese commit figura como entregado con gates.
dod_delivery_logged() {
    local sha="$1" archivo
    archivo=$(dod_delivery_log_path)
    [[ -f "$archivo" ]] || return 1
    grep -qF " $sha " "$archivo" 2>/dev/null
}

# Commits que un push publicaria: los que no estan en ningun remoto.
dod_commits_a_publicar() {
    git rev-list HEAD --not --remotes 2>/dev/null | head -50
}

# Primer commit registrado que existe en este repo: la frontera del mecanismo.
#
# Se usa ASCENDENCIA y no fechas. Con fechas la frontera se corre sola —el
# registro se escribe despues del commit, y con granularidad de segundos el
# propio commit registrado puede quedar del lado excluido— y el resultado es una
# ventana que a veces incluye y a veces no. La ascendencia es exacta: o el commit
# es anterior a la adopcion, o no.
dod_registro_base() {
    local archivo sha n=0
    archivo=$(dod_delivery_log_path)
    [[ -s "$archivo" ]] || return 1
    while read -r _ sha _; do
        [[ -n "$sha" ]] || continue
        n=$((n + 1))
        [[ "$n" -gt "$DOD_REGISTRO_SCAN_MAX" ]] && return 1
        if git cat-file -e "${sha}^{commit}" 2>/dev/null; then printf '%s' "$sha"; return 0; fi
    done < "$archivo"
    return 1
}

# 0 (true) si ese ARBOL figura entregado con gates.
#
# Respaldo del chequeo por sha: un `git commit --amend` que solo cambia el
# mensaje produce un sha nuevo sobre el mismo arbol, y el contenido revisado no
# cambio. Sin esto obligaba a re-correr los dos gates por editar una coma del
# mensaje.
dod_delivery_tree_logged() {
    local tree="$1" archivo
    [[ -n "$tree" ]] || return 1
    archivo=$(dod_delivery_log_path)
    [[ -f "$archivo" ]] || return 1
    # Anclado al fin de linea. Sin anclar, un token mas largo que empiece con el
    # hash tambien matchea. Hoy no es alcanzable —el escritor pone 3 campos de
    # 40 hex— pero lo seria en cuanto el log se edite a mano, se corrompa, o el
    # formato gane un campo. Cuesta lo mismo y elimina la clase entera.
    grep -qE " ${tree}\$" "$archivo" 2>/dev/null
}

# 0 (true) si el commit es anterior a la adopcion del registro: a la historia
# previa no se le pueden pedir gates retroactivos.
dod_anterior_al_registro() {
    local sha="$1" base
    base=$(dod_registro_base) || return 1
    [[ "$sha" = "$base" ]] && return 1
    git merge-base --is-ancestor "$sha" "$base" 2>/dev/null
}

# 0 (true) si el flag cubre EXACTAMENTE este arbol.
#
# Es el control que reemplaza al reloj. Un approval deja de ser reutilizable para
# otro diff: si se edita una linea, el arbol cambia y el flag no cubre nada. Eso
# es mas friccion que antes — el flujo pasa a ser correr gates, no tocar nada,
# entregar — pero es la unica forma de que "revise esto" signifique lo que dice.
#
# Devuelve 2 (y no 1) cuando el flag existe pero apunta a otro arbol, para que el
# caller pueda distinguir "falta correr los gates" de "el codigo cambio despues
# de correrlos". Son problemas distintos y piden mensajes distintos.
dod_flag_covers() {
    local flag="$1" tree="$2"
    [[ -f "$flag" ]] || return 1
    dod_flag_fresh "$flag" || return 1
    [[ -n "$tree" ]] || return 1
    # El flag es una LISTA de arboles aprobados, uno por linea, no un valor unico.
    #
    # Con un solo valor, dos sesiones sobre el mismo repo se pisaban: si B corria
    # sus gates, A quedaba bloqueada sin entender por que. No era un agujero de
    # seguridad —el anclaje ya impedia que B usara el approval de A para otro
    # contenido— pero si un bloqueo mutuo. Una lista deja convivir los approvals
    # de cada arbol sin que uno invalide al otro.
    grep -qx "$tree" "$flag" 2>/dev/null && return 0
    # Hay contenido pero ninguna linea cubre este arbol. Un flag vacio (formato
    # viejo, un `touch` pelado) no dice que reviso: cuenta como ausente.
    [[ -s "$flag" ]] || return 1
    grep -qE '^[0-9a-f]{40}$' "$flag" 2>/dev/null || return 1
    return 2
}

# Anota un arbol aprobado sin pisar los que ya estaban.
# Devuelve 0 si el sello quedo escrito, no-0 si NO se pudo.
#
# `dod_con_lock` ahora puede devolver 75 (no se consiguio exclusion y la
# operacion NO se ejecuto). Ignorar ese rc reintroduce exactamente el
# silenciamiento que la auditoria vino a quitar: el llamador cree que sello, el
# flag no existe, y la entrega se bloquea sin explicacion. El rc se propaga y los
# llamadores lo miran.
dod_flag_seal() {
    local flag="$1" tree="$2" max="${3:-20}"
    [[ -n "$tree" ]] || return 1
    mkdir -p "$(dirname "$flag")" 2>/dev/null
    # TODO el sellado va bajo el lock, append incluido.
    #
    # Dejar el `>>` afuera parecia inofensivo —`O_APPEND` hace atomica la
    # escritura de una linea— pero el riesgo no era la escritura sino la
    # convivencia: una liberacion concurrente lee el archivo, el append agrega
    # una linea, y el `mv` de la liberacion se la lleva. Medido: 16 de 20 sellos
    # perdidos bajo contencion. El lock y el mktemp ensancharon esa ventana de
    # microsegundos a milisegundos, asi que lo teorico paso a ser lo habitual.
    local rc
    dod_con_lock "$flag" _dod_seal "$flag" "$tree" "$max"; rc=$?
    if [[ $rc -ne 0 ]]; then
        printf '[DoD] el sello de %s NO quedo registrado (rc=%s). El gate va a seguir pidiendolo.\n' \
            "$(basename "$flag")" "$rc" >&2
        return "$rc"
    fi
    # Verificacion positiva: el sello solo cuenta si esta en el archivo.
    grep -qx "$tree" "$flag" 2>/dev/null || {
        printf '[DoD] el sello de %s se ejecuto pero no quedo en el archivo.\n' \
            "$(basename "$flag")" >&2
        return 1
    }
}

_dod_seal() {
    local flag="$1" tree="$2" max="$3"
    grep -qx "$tree" "$flag" 2>/dev/null || printf '%s\n' "$tree" >> "$flag"
    # Techo: el archivo no puede crecer sin limite en una sesion larga.
    if [[ -f "$flag" && $(wc -l < "$flag" 2>/dev/null || echo 0) -gt "$max" ]]; then
        _dod_truncar "$flag" "$max"
    fi
}

# Mutex portable: `mkdir` es atomico en POSIX y no necesita flock, que en macOS
# no viene por defecto. Sin esto, dos procesos reescribiendo el mismo archivo con
# un temporal de nombre fijo se pisan — y el modo de falla no es "se perdio una
# linea" sino "desaparecio el archivo", porque uno evalua el temporal del otro,
# concluye que quedo vacio y borra approvals que seguian siendo validos.
# Log propio y no el de entregas: ese tiene formato fijo de 3 campos y lo parsea
# `dod_registro_base`, asi que una linea ajena se leeria como un sha muerto y
# gastaria presupuesto de barrido — reintroduciendo por la puerta de atras el
# costo que costo arreglar en M-12.
#
# UNICO log de la DoD SIN rotacion, y es deliberado: no lo "arregles" por
# simetria con dod_log_hotfix o gate-deliveries.log. Solo escribe en el camino de
# rendicion del lock, que ademas se auto-cura —el que se rinde hace `rmdir`, asi
# que un lock trabado no genera una linea por entrega para siempre— y cada evento
# cuesta 2 s de espera real. Llegar a 1 MB pide ~7.800 degradaciones, o sea horas
# de contencion acumulada. Si copias este patron a una ruta mas caliente, ahi si
# necesita rotacion.
DOD_LOCK_LOG="${DOD_LOCK_LOG:-logs/dod-lock-degradado.log}"

dod_log_lock_degradado() {
    local recurso="$1" archivo
    archivo="${CLAUDE_PROJECT_DIR:-.}/${DOD_LOCK_LOG}"
    mkdir -p "$(dirname "$archivo")" 2>/dev/null
    # No alcanza con `$$`: en bash devuelve el PID del shell INVOCANTE, asi que
    # todas las operaciones lanzadas como subshells desde el mismo shell se
    # registran con el mismo pid. Este log existe para diagnosticar contencion, y
    # diagnosticar contencion pide distinguir a los participantes — justo el caso
    # donde `$$` se aplana.
    #
    # `$BASHPID` lo resuelve, pero llego en bash 4.0 y macOS trae 3.2, que es
    # donde corre buena parte del stack. El `exec sh -c 'echo $PPID'` da el PID
    # del subshell actual en cualquiera de las dos. Cuesta dos procesos, y solo
    # se paga en el camino de rendicion del lock, que es raro por diseno.
    #
    # El `exec` NO es cosmetico: hace que `sh` REEMPLACE al subshell de la
    # sustitucion, asi que su `$PPID` es el proceso llamante — el que queremos.
    # Sin `exec`, `sh` seria hijo de ese subshell y `$PPID` devolveria el pid
    # efimero de la sustitucion, que no sirve para nada. Sacarlo "para ahorrar un
    # fork" deja el campo indiagnosticable en silencio.
    local pid="${BASHPID:-}"
    [[ -n "$pid" ]] || pid=$(exec sh -c 'echo $PPID')
    printf '%s pid=%s recurso=%s sin-exclusion\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$pid" "$recurso" >> "$archivo" 2>/dev/null
}

# Segundos tras los cuales un lock se considera HUERFANO (proceso muerto sin
# limpiar). Las operaciones que protege son de milisegundos, asi que 5s ya es
# tres ordenes de magnitud de margen. Mas bajo arriesgaria robarle el lock a un
# proceso vivo en una maquina cargada — que produce justo la corrupcion que esto
# viene a evitar. Configurable para los tests, que no pueden esperar 5s.
DOD_LOCK_HUERFANO_SEG="${DOD_LOCK_HUERFANO_SEG:-5}"
# Techo duro. Si ni con la toma de huerfanos se consigue, se ABANDONA la
# operacion — no se ejecuta sin exclusion.
DOD_LOCK_INTENTOS_MAX="${DOD_LOCK_INTENTOS_MAX:-300}"

# Edad en segundos de un archivo o directorio, o rc!=0 si no se puede
# determinar. Unico lector de mtime del archivo: ver el comentario de orden.
_dod_edad_seg() {
    local d="$1" ahora mt
    ahora=$(date +%s 2>/dev/null) || return 1

    # ORDEN GNU PRIMERO, y no es cosmetico.
    #
    # En GNU coreutils `stat -f` es `--file-system`: NO falla, devuelve rc=0 y
    # imprime el punto de montaje. Con el orden inverso el `||` nunca dispara, la
    # aritmetica recibe `/` y revienta, `edad` queda vacia, y la toma de lock
    # huerfano queda MUERTA en Linux — que es donde corre CI, BAS y Cloud Foundry.
    # El resultado seria un cuelgue de 30s y rc=75 en cada commit con un lock
    # huerfano, en la plataforma donde nadie lo probaria a mano.
    #
    # Este repo ya habia tropezado con el mismo `stat -f` en `dod_log_hotfix`
    # (ver el comentario de `wc -c`). Se repitio el bug; el orden lo cierra.
    mt=$(stat -c %Y "$d" 2>/dev/null) || mt=$(stat -f %m "$d" 2>/dev/null) || return 1
    # Solo un entero es utilizable: cualquier otra cosa (un punto de montaje, un
    # mensaje) se descarta en vez de romper la aritmetica.
    case "$mt" in
        ''|*[!0-9]*) return 1 ;;
        *) ;;   # Un entero: utilizable.
    esac
    printf '%s' "$((ahora - mt))"
}

dod_con_lock() {
    local recurso="$1"; shift
    local lock="${recurso}.lock" intentos=0
    while ! mkdir "$lock" 2>/dev/null; do
        intentos=$((intentos + 1))

        # AUDITORIA A5. Antes, tras ~20 intentos (~2s) se ejecutaba la operacion
        # SIN exclusion. El comentario decia que el peor caso "vuelve a ser el de
        # antes", pero el de antes era perder sellos: medido en el smoketest,
        # 2 a 3 de 20 approvals concurrentes desaparecian, porque una liberacion
        # lee el archivo, un append agrega una linea, y el `mv` de la liberacion
        # se la lleva. Un approval que se gano y se pierde es exactamente el
        # error que no se puede silenciar.
        #
        # La preocupacion original —no colgar una entrega por un lock huerfano—
        # sigue siendo valida, y se resuelve TOMANDO el huerfano en vez de
        # ignorando la exclusion.
        local edad
        edad=$(_dod_edad_seg "$lock" 2>/dev/null || echo '')
        if [[ -n "$edad" && "$edad" -ge "$DOD_LOCK_HUERFANO_SEG" ]]; then
            dod_log_lock_degradado "$recurso"
            printf '[DoD] lock huerfano de %ss sobre %s: se toma.\n' \
                "$edad" "$(basename "$recurso")" >&2
            rmdir "$lock" 2>/dev/null
            continue
        fi

        if [[ "$intentos" -gt "$DOD_LOCK_INTENTOS_MAX" ]]; then
            # Rastro en un LOG, no solo en stderr.
            #
            # El unico invocador automatico de la liberacion es .husky/post-commit,
            # que manda todo a /dev/null — y con razon, no debe ensuciar la salida
            # del commit. O sea que un aviso por stderr queda encendido en la ruta
            # interactiva, que ya es observable, y apagado en la automatica, que es
            # la que nadie mira. Mismo principio que quedo tras el bug del
            # SessionStart: lo que toca el estado de un gate deja rastro donde
            # nadie lo pueda redirigir.
            # No se ejecuta la operacion. Devolver un error es lo unico honesto:
            # el llamador tiene que saber que su sello NO quedo registrado.
            dod_log_lock_degradado "$recurso"
            printf '[DoD] no se pudo tomar el lock de %s tras %s intentos: la operacion NO se ejecuto.\n' \
                "$(basename "$recurso")" "$intentos" >&2
            return 75
        fi
        sleep 0.1
    done
    "$@"
    local rc=$?
    rmdir "$lock" 2>/dev/null
    return $rc
}

_dod_truncar() {
    local flag="$1" max="$2" tmp
    tmp=$(mktemp "${flag}.XXXXXX") || return 1
    tail -n "$max" "$flag" > "$tmp" 2>/dev/null && mv "$tmp" "$flag" || rm -f "$tmp"
}

_dod_release() {
    local flag="$1" tree="$2" tmp
    tmp=$(mktemp "${flag}.XXXXXX") || return 1
    grep -vx "$tree" "$flag" > "$tmp" 2>/dev/null || : > "$tmp"
    if [[ -s "$tmp" ]]; then mv "$tmp" "$flag"; else rm -f "$tmp" "$flag"; fi
}

# Saca un arbol del flag. Si no queda ninguno, borra el archivo.
dod_flag_release() {
    local flag="$1" tree="$2"
    [[ -f "$flag" ]] || return 0
    if [[ -n "$tree" ]]; then
        dod_con_lock "$flag" _dod_release "$flag" "$tree"
    else
        rm -f "$flag"
    fi
}

# Archivos que trajo el ultimo commit. En el commit raiz no hay con que comparar.
dod_commit_files() {
    if git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
        git -c core.quotePath=false diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E "$DOD_PRODUCTIVE_RE" | sed '/^$/d'
    else
        git -c core.quotePath=false ls-tree -r --name-only HEAD 2>/dev/null | grep -E "$DOD_PRODUCTIVE_RE" | sed '/^$/d'
    fi
}

# El comando que la herramienta va a ejecutar, sea cual sea el host.
#
# Cada host nombra distinto el mismo dato: Claude Code usa `tool_input.command`,
# Codex usa `tool_input.cmd` para `exec_command`, y algunos mandan `argv` como
# lista. Leer solo `command` —que es lo que hacia `delivery-gate.sh`— devolvia
# vacio en Codex, el gate no veia ningun `git commit` y PERMITIA la entrega.
#
# La lista es la misma que `lib/hook-contract.mjs` usa para `ses guard`. Si un
# host suma otra clave se agrega ACA y en el contrato, no en cada script.
dod_tool_command() {
    local entrada="$1" cmd=""
    if command -v python3 >/dev/null 2>&1; then
        cmd=$(printf '%s' "$entrada" | python3 -c "
import json,sys
try:
    i = json.load(sys.stdin).get('tool_input') or {}
    v = i.get('command') or i.get('cmd') or i.get('argv') or ''
    print(' '.join(v) if isinstance(v, list) else v)
except Exception:
    print('')" 2>/dev/null)
    fi
    printf '%s' "$cmd"
}

# 0 (true) si el flag existe y es mas reciente que DOD_MAX_AGE_SECONDS.
dod_flag_fresh() {
    local f="$1"
    [[ -f "$f" ]] || return 1

    # `_dod_edad_seg` y no `stat` a mano. La version previa hacia
    # `stat -f %m || stat -c %Y`, con el orden invertido respecto de la leccion
    # que este mismo archivo documenta 100 lineas mas arriba: en GNU coreutils
    # `stat -f` es `--file-system`, devuelve rc=0 e imprime el punto de montaje,
    # asi que el `||` nunca disparaba. `mtime` quedaba `/`, la aritmetica
    # reventaba, `age` quedaba VACIA — y `[[ "" -le 1800 ]]` es VERDADERO en
    # bash. En Linux (CI, BAS, Cloud Foundry) la red de vencimiento por tiempo
    # respondia "fresco" siempre, para cualquier flag por viejo que fuera.
    #
    # El anclaje al arbol (ADR-011) seguia sosteniendo el control principal, asi
    # que el agujero era el vencimiento, no el approval. Igual se cierra: una
    # red que siempre dice que si no es una red.
    local age
    age=$(_dod_edad_seg "$f") || return 1   # No verificable no es fresco.
    [[ -n "$age" ]] || return 1
    [[ "$age" -le "$DOD_MAX_AGE_SECONDS" ]]
}

# Estado del HOTFIX-OVERRIDE (two-person rule, ADR-005).
# Imprime: "ok|<approver>|<reason>" | "invalid" | "none"
dod_hotfix_state() {
    local flag="${1:-${CLAUDE_PROJECT_DIR:-.}/tmp/.hotfix-override}"
    [[ -f "$flag" ]] || { echo "none"; return 0; }

    local reason_line approver requester
    reason_line=$(grep -E '^REASON: ' "$flag" 2>/dev/null | head -1)
    approver=$(grep -E '^APPROVED_BY: ' "$flag" 2>/dev/null | head -1 | sed 's/^APPROVED_BY: *//')
    requester=$(git config user.email 2>/dev/null || echo "unknown")

    if ! echo "$reason_line" | grep -qE '^REASON: .{20,}'; then echo "invalid"; return 0; fi
    if [[ -z "$approver" || "$approver" == "$requester" ]]; then echo "invalid"; return 0; fi
    echo "ok|${approver}|${reason_line#REASON: }"
}

# Registra un uso de HOTFIX-OVERRIDE en logs/hotfix-overrides.log, rotando el
# archivo si supera 1MB (se mantienen 3 generaciones).
# AUDITORIA A12 — `SES_GATES=off` desactivaba el gate de entrega y NO dejaba
# rastro en ningun log, mientras `hotfix-override` —que es mas restrictivo,
# exige two-person rule y se consume— si se audita. La via mas facil de omitir
# los gates era la unica invisible.
#
# No bloquea: el punto no es impedirlo (es una decision legitima del dev) sino
# que quede constancia de que se tomo, sobre que contenido y por quien.
#
# Uso: dod_log_gates_off <log_file> <arbol> <archivos>
dod_log_gates_off() {
    local log="$1" arbol="$2" archivos="$3"
    # Si no se puede escribir el log, se DICE. Un `|| return 0` aca hacia que el
    # llamador anunciara "Registrado en logs/gates-off.log" sobre un archivo que
    # nunca se escribio — el unico caso que este log existe para evitar.
    if ! mkdir -p "$(dirname "$log")" 2>/dev/null; then
        printf '[DoD] no se pudo crear %s: el uso de SES_GATES=off NO quedo registrado.\n' \
            "$(dirname "$log")" >&2
        return 1
    fi

    if [[ -f "$log" ]]; then
        local size; size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
        if [[ "${size:-0}" -gt 1048576 ]]; then
            [[ -f "${log}.2" ]] && mv "${log}.2" "${log}.3"
            [[ -f "${log}.1" ]] && mv "${log}.1" "${log}.2"
            mv "$log" "${log}.1"
        fi
    fi

    local n; n=$(printf '%s\n' "$archivos" | sed '/^$/d' | wc -l | tr -d ' ')
    printf '[%s] user=%s session=%s tree=%s archivos=%s — SES_GATES=off\n%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(git config user.email 2>/dev/null || echo unknown)" \
        "${CLAUDE_SESSION_ID:-no-session}" \
        "${arbol:0:12}" "$n" \
        "$(printf '%s\n' "$archivos" | sed '/^$/d' | sed 's/^/    /')" >> "$log" || {
        printf '[DoD] no se pudo escribir %s: el uso de SES_GATES=off NO quedo registrado.\n' \
            "$log" >&2
        return 1
    }
}

# Uso: dod_log_hotfix <log_file> <requester> <approver> <reason>
dod_log_hotfix() {
    local log="$1" requester="$2" approver="$3" reason="$4"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0

    # `wc -c` y no `stat -f %z`: en GNU coreutils `-f` es `--file-system` y
    # devuelve el block size, con lo que la rotacion nunca se disparaba.
    if [[ -f "$log" ]]; then
        local size; size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
        if [[ "${size:-0}" -gt 1048576 ]]; then
            [[ -f "${log}.2" ]] && mv "${log}.2" "${log}.3"
            [[ -f "${log}.1" ]] && mv "${log}.1" "${log}.2"
            mv "$log" "${log}.1"
        fi
    fi

    printf '[%s] user=%s approver=%s session=%s — REASON: %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$requester" "$approver" \
        "${CLAUDE_SESSION_ID:-no-session}" "$reason" >> "$log"
}

# Escapa un texto arbitrario como string JSON. Sin dependencia de python3:
# los hooks corren en cada tool call y un spawn de interprete por hook es
# latencia pura. Cubre los escapes que exige RFC 8259 para texto de mensajes.
dod_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//	/\\t}"
    s="${s//$'\r'/}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
}
