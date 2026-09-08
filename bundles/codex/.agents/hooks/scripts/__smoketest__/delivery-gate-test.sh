#!/bin/bash
# delivery-gate-test.sh — contrato del gate de entrega y de lib/dod-common.sh (ADR-008).
#
# Cubre lo que la revision de la propia implementacion levanto:
#   - el fast path no hace nada en comandos que no son entregas
#   - un `echo "git push"` no cuenta como entrega
#   - un path con espacios NO se clasifica como meta-stack (se saltaria gates 2+3)
#   - los flags vencidos no valen
#   - el contador de turnos no se comparte entre sesiones concurrentes
#
# Corre en un sandbox git temporal: no depende del estado del working tree.

set -u
STACK_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX"/{hooks/scripts/lib,tmp,srv}
cp "$STACK_ROOT"/hooks/scripts/*.sh "$SANDBOX/hooks/scripts/"
cp "$STACK_ROOT"/hooks/scripts/lib/*.sh "$SANDBOX/hooks/scripts/lib/"
# Toolchain del sandbox. Estos tests son sobre el anclaje de approvals, los
# modos de sesion y la interaccion entre capas de enforcement — NO sobre linting.
# Como Gate 1 ahora bloquea cuando hay archivos que requieren un linter ausente
# (auditoria A2), el sandbox necesita un toolchain que exista. Un stub que
# aprueba es correcto aca: el sujeto del test es otro, y sin esto los tests
# medirian la ausencia del linter en vez de lo que quieren medir.
mkdir -p "$SANDBOX/node_modules/.bin"
for _bin in eslint cds ui5lint; do
    printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/node_modules/.bin/$_bin"
    chmod +x "$SANDBOX/node_modules/.bin/$_bin"
done

cd "$SANDBOX" || exit 1
git init -q . && git config user.email dev@ci.local && git config user.name ci
echo seed > seed.txt && git add seed.txt && git commit -qm init
export CLAUDE_PROJECT_DIR="$SANDBOX"

DG="hooks/scripts/delivery-gate.sh"

# Los flags dejaron de ser archivos vacios: guardan el hash del arbol revisado.
# `flags_ok` los emite para el arbol actual; `flags_de_otro_arbol`, para uno ajeno.
flags_ok()  { local t; t=$(git write-tree); echo "$t" > tmp/.review-done; echo "$t" > tmp/.qa-nfr-done; }
flags_viejo() { : > tmp/.review-done; : > tmp/.qa-nfr-done; }
# En push lo que se entrega son commits, no el indice: el approval tiene que
# cubrir el arbol de HEAD.
flags_ok_head() { local t; t=$(git rev-parse "HEAD^{tree}"); echo "$t" > tmp/.review-done; echo "$t" > tmp/.qa-nfr-done; }
flags_de_otro_arbol() {
    echo "0000000000000000000000000000000000000000" > tmp/.review-done
    echo "0000000000000000000000000000000000000000" > tmp/.qa-nfr-done
}
# shellcheck disable=SC1091
source hooks/scripts/lib/dod-common.sh

PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
# Un fallo se escribe TAMBIEN a un archivo, no solo a stdout.
#
# Este smoketest tiene casos de concurrencia y de lock: un fallo puede aparecer
# una vez cada muchas corridas. Cuando eso pasa, la salida se suele perder — el
# llamador la filtro con un `tail`, o volvio a correr y la segunda paso. Sin la
# evidencia, un fallo intermitente real es indistinguible de ruido, que es
# exactamente como se cerro mal la primera vez (A5 de la auditoria).
DGT_FAIL_LOG="${DGT_FAIL_LOG:-${TMPDIR:-/tmp}/ses-smoketest-fails.log}"
bad() {
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "         actual: $(printf '%s' "$2" | head -c 200)"
    {
        printf '%s  FAIL  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
        [[ -n "${2:-}" ]] && printf '        actual: %s\n' "$(printf '%s' "$2" | head -c 500)"
    } >> "$DGT_FAIL_LOG" 2>/dev/null || true
    FAIL=$((FAIL+1))
}
gate() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$DG" 2>&1; }

echo "==> Fast path: comandos que no son entregas"
for cmd in "ls -la" "rg -n foo src/" "npm test" "git status" "git diff HEAD"; do
    OUT=$(gate "$cmd")
    [[ -z "$OUT" ]] && ok "sin salida: $cmd" || bad "salida inesperada en: $cmd" "$OUT"
done

echo ""
echo "==> Falsos positivos: la frase aparece pero no es una entrega"
OUT=$(gate 'echo \"git push\"')
[[ -z "$OUT" ]] && ok "echo con la frase no dispara el gate" || bad "falso positivo" "$OUT"
OUT=$(gate 'git commit --dry-run')
[[ -z "$OUT" ]] && ok "--dry-run no es entrega" || bad "--dry-run bloqueado" "$OUT"

echo ""
echo "==> Entrega real con codigo productivo sin gates → deny"
echo "module.exports = {};" > srv/service.js && git add srv/service.js
OUT=$(gate "git commit -m feat")
printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"' && ok "bloquea la entrega" || bad "no bloqueo" "$OUT"
printf '%s' "$OUT" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{JSON.parse(s);process.exit(0)}catch(e){process.exit(1)}})" \
    && ok "JSON valido (mensaje multilinea escapado)" || bad "JSON invalido"

echo ""
echo "==> Flags frescos permiten; vencidos no"
flags_ok
OUT=$(gate "git commit -m feat")
[[ -z "$OUT" ]] && ok "flags frescos dejan pasar" || bad "bloqueo con flags validos" "$OUT"
flags_ok
touch -t 202001010000 tmp/.review-done tmp/.qa-nfr-done
OUT=$(gate "git push")
printf '%s' "$OUT" | grep -q deny && ok "flags vencidos rechazados" || bad "acepto flags vencidos" "$OUT"
rm -f tmp/.review-done tmp/.qa-nfr-done

echo ""
echo "==> dod_is_meta_only con datos sucios"
dod_is_meta_only $'hooks/scripts/x.sh\nsrv/mi servicio.js' \
    && bad "path con espacios clasificado como meta-stack (saltaria gates 2+3)" \
    || ok "path con espacios detectado como productivo"
dod_is_meta_only $'hooks/a.sh\ntests/unit/b.test.js\nsettings.json' \
    && ok "meta-stack puro reconocido" || bad "falso positivo en meta-stack"

echo ""
echo "==> Allowlist de portabilidad multi-host (ADR-012)"
# `dod-common.sh` viaja al cliente dentro del plugin: la allowlist tiene que
# distinguir los schemas del stack de los de un proyecto CAP/OData cualquiera.
dod_is_meta_only 'schemas/ses-manifest.schema.json' \
    && ok "schemas/ses-*.schema.json es meta-stack" \
    || bad "el schema del propio stack exige los 3 gates"
dod_is_meta_only 'schemas/api-contract.json' \
    && bad "schemas/ de un proyecto de cliente clasificado como meta-stack (entregaria sin gates 2+3)" \
    || ok "schemas/ de cliente conserva los 3 gates"
dod_is_meta_only 'stack.manifest.json' \
    && bad "el manifiesto entra sin review — es el driver de los 4 bundles" \
    || ok "stack.manifest.json exige los 3 gates"
dod_is_meta_only 'emitters/claude.js' \
    && bad "un emisor entra sin review — un hook omitido deja al host sin gate" \
    || ok "emitters/ exige los 3 gates"
dod_is_meta_only $'schemas/ses-manifest.schema.json\nsrv/evil.js' \
    && bad "un productivo escondido detras de un meta-stack paso" \
    || ok "lista mixta clasificada como productiva"
dod_is_meta_only 'schemas/../srv/evil.js' \
    && bad "path traversal clasificado como meta-stack" \
    || ok "path traversal detectado como productivo"

echo ""
echo "==> protect-sensitive-files sobre comandos de shell"

# El hook solo miraba `tool_input.file_path`, o sea las tools de escritura del
# host de referencia. Dos agujeros: en Claude `Bash: echo x >> .env` pasaba sin
# aviso, y en Codex —que NO tiene tool de escritura, edita por `exec_command`— el
# hook no cubria absolutamente nada.
spf() { printf '%s' "$1" | bash "$STACK_ROOT/hooks/scripts/protect-sensitive-files.sh" >/dev/null 2>&1; echo $?; }

[[ "$(spf '{"tool_name":"Bash","tool_input":{"command":"echo S=1 >> .env"}}')" = "2" ]] \
    && ok "bloquea una escritura a .env por Bash (host de referencia)" \
    || bad "una escritura a .env por Bash NO se bloqueo" ""

[[ "$(spf '{"tool_name":"exec_command","tool_input":{"cmd":"echo S=1 > .env"}}')" = "2" ]] \
    && ok "bloquea una escritura a .env por exec_command (Codex)" \
    || bad "una escritura a .env por exec_command NO se bloqueo" ""

[[ "$(spf '{"tool_name":"exec_command","tool_input":{"cmd":"cp tpl xs-security.json"}}')" = "2" ]] \
    && ok "bloquea un cp sobre xs-security.json" \
    || bad "un cp sobre xs-security.json NO se bloqueo" ""

# Exigir INTENCION de escritura, no la sola mencion: bloquear toda referencia
# volveria el hook inusable y la gente lo terminaria desactivando.
[[ "$(spf '{"tool_name":"Bash","tool_input":{"command":"grep DB_HOST .env"}}')" = "0" ]] \
    && ok "una LECTURA de .env sigue permitida" \
    || bad "se bloqueo una lectura de .env" ""

[[ "$(spf '{"tool_name":"Edit","tool_input":{"file_path":".env"}}')" = "2" ]] \
    && ok "la cobertura por file_path sigue intacta" \
    || bad "se perdio la cobertura por file_path" ""

echo ""
echo "==> Correcciones del review de la auditoria"

# `stat -f` en GNU coreutils es `--file-system`: NO falla y devuelve el punto de
# montaje. Con el orden invertido, `_dod_edad_seg` devolvia basura, la toma de
# lock huerfano quedaba MUERTA en Linux, y cada commit con un lock huerfano se
# colgaba 30s. Se exige un entero o nada.
EDAD_DIR=$(mktemp -d)
EDAD=$(_dod_edad_seg "$EDAD_DIR")
case "$EDAD" in
    ''|*[!0-9]*) bad "_dod_edad_seg no devolvio un entero" "[$EDAD]" ;;
    *) ok "_dod_edad_seg devuelve un entero (portable BSD/GNU)" ;;
esac
_dod_edad_seg "$EDAD_DIR/no-existe" >/dev/null 2>&1 \
    && bad "_dod_edad_seg aprobo un directorio inexistente" \
    || ok "_dod_edad_seg falla con un directorio inexistente"
rmdir "$EDAD_DIR"

# El MISMO bug, en `dod_flag_fresh`, sobrevivio a la correccion de arriba: tenia
# `stat -f %m || stat -c %Y` con el orden invertido. En Linux `mtime` quedaba `/`,
# la aritmetica reventaba, `age` quedaba VACIA — y `[[ "" -le 1800 ]]` es
# VERDADERO en bash. La red de vencimiento por tiempo respondia "fresco" para
# CUALQUIER flag, por viejo que fuera, en CI/BAS/CF. Fail-open.
FRESH_F=$(mktemp)
echo "arbol" > "$FRESH_F"
DOD_MAX_AGE_SECONDS=1800 dod_flag_fresh "$FRESH_F" \
    && ok "dod_flag_fresh: un flag recien sellado es fresco" \
    || bad "dod_flag_fresh rechazo un flag recien creado" ""

touch -t 202001010000 "$FRESH_F"
DOD_MAX_AGE_SECONDS=1800 dod_flag_fresh "$FRESH_F" \
    && bad "dod_flag_fresh acepto un flag de 2020" "la red de vencimiento esta muerta" \
    || ok "dod_flag_fresh: un flag vencido se rechaza"

# Y con un `stat` que se comporta como GNU, que es donde el bug vivia: `-f` no
# falla, devuelve rc=0 e imprime el punto de montaje.
(
    stat() { if [ "$1" = "-f" ]; then echo "/"; return 0; fi; command stat "$@"; }
    DOD_MAX_AGE_SECONDS=1800 dod_flag_fresh "$FRESH_F"
) && bad "dod_flag_fresh acepto un flag vencido con stat GNU" "vuelve a estar fail-open" \
   || ok "dod_flag_fresh: vencido tambien con stat estilo GNU"
rm -f "$FRESH_F"

# El sello tiene que AVISAR cuando no pudo escribirse. Ignorar el rc dejaba al
# llamador creyendo que sello y al dev con una entrega bloqueada sin motivo.
SEAL_DIR=$(mktemp -d)
dod_flag_seal "$SEAL_DIR/f" "$(printf 'd%039d' 1)" \
    && ok "dod_flag_seal devuelve 0 cuando sella" \
    || bad "dod_flag_seal fallo en el camino feliz"
mkdir -p "$SEAL_DIR/g.lock"    # lock permanente: no se puede sellar
( DOD_LOCK_HUERFANO_SEG=99999 DOD_LOCK_INTENTOS_MAX=2 dod_flag_seal "$SEAL_DIR/g" "$(printf 'e%039d' 1)" ) >/dev/null 2>&1 \
    && bad "dod_flag_seal devolvio exito sin haber sellado" \
    || ok "dod_flag_seal propaga el fallo en vez de fingir que sello"
[[ ! -s "$SEAL_DIR/g" ]] \
    && ok "el flag no sellado queda vacio, coherente con el rc" \
    || bad "escribio el flag pese a no tener el lock"
rm -rf "$SEAL_DIR"

# `dod_git_paths` no debe mezclar stderr de git con los paths: un warning que
# terminara en una extension productiva se volvia un archivo cambiado inventado.
PATHS_OUT=$(dod_git_paths)
INEXISTENTES=$(printf '%s\n' "$PATHS_OUT" | sed '/^$/d' | while IFS= read -r _f; do [ -e "$_f" ] || echo "$_f"; done)
[[ -z "$INEXISTENTES" ]] \
    && ok "dod_git_paths solo devuelve paths que existen" \
    || bad "dod_git_paths devolvio paths inexistentes (stderr mezclado)" "$INEXISTENTES"

# `protect-sensitive-files` es un hook de SEGURIDAD: sin python3 no puede fallar
# abierto. Se fuerza la rama de respaldo.
PF=$(mktemp)
sed 's|if command -v python3 >/dev/null 2>&1; then|if false; then|' \
    "$STACK_ROOT/hooks/scripts/protect-sensitive-files.sh" > "$PF"
echo '{"tool_input":{"file_path":".env"}}' | bash "$PF" >/dev/null 2>&1 \
    && bad "sin python3 permitio escribir .env" \
    || ok "sin python3 el respaldo sigue bloqueando .env"
echo '{"tool_input":{"path":"xs-security.json"}}' | bash "$PF" >/dev/null 2>&1 \
    && bad "sin python3 permitio escribir xs-security.json" \
    || ok "el respaldo cubre las variantes de clave de ruta"
echo '{"tool_input":{"file_path":"srv/normal.js"}}' | bash "$PF" >/dev/null 2>&1 \
    && ok "el respaldo no bloquea un archivo normal" \
    || bad "el respaldo bloqueo un archivo que no esta protegido"
rm -f "$PF"

# Un path con espacios tiene que llegar ENTERO al linter.
ESP_DIR=$(mktemp -d) && ESP_OLD=$PWD
git init -q "$ESP_DIR" && cd "$ESP_DIR"
git config user.email t@t.t && git config user.name t
mkdir -p srv node_modules/.bin
printf 'x\n' > README.md && git add -A && git commit -qm init
# Un eslint de mentira que registra, uno por linea, los argumentos que recibe.
# Con heredoc y no printf: anidar escapes de printf dentro de printf es como se
# genero un stub roto que no escribia nada y hacia fallar el caso por su propio
# andamiaje, no por el codigo bajo prueba.
cat > node_modules/.bin/eslint <<STUB
#!/bin/sh
for a in "\$@"; do echo "\$a"; done > "${ESP_DIR}/args.txt"
exit 0
STUB
chmod +x node_modules/.bin/eslint
printf 'var a = 1\n' > "srv/con espacio.js" && git add -A
CLAUDE_PROJECT_DIR="$ESP_DIR" bash "$ESP_OLD/hooks/scripts/quality-gate.sh" --mode=cli >/dev/null 2>&1
grep -qx "srv/con espacio.js" "$ESP_DIR/args.txt" 2>/dev/null \
    && ok "un path con espacios llega entero al linter" \
    || bad "el path con espacios se partio" "$(tr '\n' '|' < "$ESP_DIR/args.txt" 2>/dev/null)"
cd "$ESP_OLD" && rm -rf "$ESP_DIR"

echo ""
echo '==> pre-push delega en `ses gates --ci`, no reimplementa la regla'
# La primera version verificaba contra logs/gate-deliveries.log mientras CI
# verificaba el trailer SES-Gated-Tree. Dos reglas para lo mismo, y ya
# divergieron: el hook rechazaba commits que CI acepta.
PP="$STACK_ROOT/.husky/pre-push"
if [ -x "$PP" ]; then
    ok "pre-push existe y es ejecutable"
    grep -q "ses.mjs gates --ci" "$PP" \
        && ok "delega en el mismo comando que corre CI" \
        || bad "pre-push reimplementa la verificacion en vez de delegar"
    head -1 "$PP" | grep -q bash \
        && ok "declara bash (dod-common no parsea bajo dash)" \
        || bad "pre-push no declara bash"
    grep -q 'SES_GATES:-' "$PP" && grep -q 'dod_log_gates_off' "$PP" \
        && ok "SES_GATES=off deja rastro tambien en push" \
        || bad "omitir los gates en push no queda registrado"
else
    bad ".husky/pre-push ausente o no ejecutable — el push no tiene barrera local"
fi

echo "==> Gate 1: un linter ausente NO cuenta como aprobado (auditoria A2)"
# `rc=127` (linter no instalado) se trataba igual que `rc=0`. En este repo eso
# dejaba 3 de 5 verificaciones apagadas, y un `.js` con `var` y `==` pasaba el
# gate limpio.
G1_DIR=$(mktemp -d) && G1_OLD=$PWD
git init -q "$G1_DIR" && cd "$G1_DIR"
git config user.email t@t.t && git config user.name t
mkdir -p srv node_modules/.bin
# Commit inicial: el descubrimiento del gate usa `git diff HEAD`, que en un repo
# sin commits no resuelve y devuelve vacio — el gate no veria ningun archivo.
printf 'inicial\n' > README.md && git add -A && git commit -qm inicial
printf 'var x = 1\nif (x == "1") { console.log(1) }\n' > srv/probe.js
git add srv/probe.js
# Sin eslint en node_modules/.bin: hay archivos que lo requieren y no esta.
OUT=$(CLAUDE_PROJECT_DIR="$G1_DIR" bash "$G1_OLD/hooks/scripts/quality-gate.sh" --mode=cli 2>&1); RC=$?
[[ "$RC" -ne 0 ]] \
    && ok "bloquea cuando falta un linter que los archivos requieren" \
    || bad "aprobo sin poder verificar (rc=$RC)" "$OUT"
printf '%s' "$OUT" | grep -q "NO SE PUDO VERIFICAR" \
    && ok "el reporte distingue 'no verificable' de 'aprobado'" \
    || bad "no reporta que no pudo verificar" "$OUT"
# Sin archivos de ese tipo: no aplica, y eso SI es un skip legitimo.
git rm -q --cached srv/probe.js && rm -f srv/probe.js
OUT=$(CLAUDE_PROJECT_DIR="$G1_DIR" bash "$G1_OLD/hooks/scripts/quality-gate.sh" --mode=cli 2>&1); RC=$?
[[ "$RC" -eq 0 ]] \
    && ok "sin archivos del tipo, el linter no aplica y no bloquea" \
    || bad "bloqueo sin archivos que verificar (rc=$RC)" "$OUT"
cd "$G1_OLD" && rm -rf "$G1_DIR"

echo ""
echo "==> Paths que git cita (core.quotePath)"
# Un nombre no ASCII sale citado y escapado de git; con las comillas dejaba de
# matchear DOD_PRODUCTIVE_RE y el archivo se volvia invisible para el gate.
# En un stack en espanol, `srv/articulo.js` no es un caso de borde.
QP_DIR=$(mktemp -d) && QP_OLD=$PWD
git init -q "$QP_DIR" && cd "$QP_DIR"
git config user.email t@t.t && git config user.name t
mkdir -p srv && printf 'x' > "srv/artículo.js" && git add -A
QP_SEEN=$(dod_staged_files | grep -c 'art' || true)
[[ "$QP_SEEN" -ge 1 ]] \
    && ok "path con acento visible para el gate" \
    || bad "path con acento INVISIBLE — entregaria sin gates 2+3"
dod_is_meta_only "$(dod_staged_files)" \
    && bad "path con acento clasificado como meta-stack" \
    || ok "path con acento clasificado como productivo"
cd "$QP_OLD" && rm -rf "$QP_DIR"

echo ""
echo "==> Concurrencia: el contador de turnos no se comparte entre sesiones"
rm -f tmp/.agent-turn-count-* 2>/dev/null
CLAUDE_SESSION_ID=sesA bash hooks/scripts/agent-reinforcement.sh <<< '{"prompt":"/sap-abap x"}' >/dev/null
CLAUDE_SESSION_ID=sesB bash hooks/scripts/agent-reinforcement.sh <<< '{"prompt":"/sap-cap y"}' >/dev/null
N=$(find tmp -name '.agent-turn-count-*' | wc -l | tr -d ' ')
[[ "$N" -eq 2 ]] && ok "un contador por sesion" || bad "contador compartido ($N archivos)"

echo ""
echo "==> shrink-input: solo acota, nunca cambia semantica"
si(){ printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash hooks/scripts/shrink-input.sh 2>/dev/null; }
[[ -z "$(si 'ls -la')" ]] && ok "comando inocuo intacto" || bad "intervino en un comando inocuo"
[[ -z "$(si 'git commit -m x')" ]] && ok "no toca comandos de escritura" || bad "reescribio un git commit"
[[ -z "$(si 'rm -rf build')" ]] && ok "no toca comandos destructivos" || bad "reescribio un rm"
[[ -z "$(si 'npm test | tail -20')" ]] && ok "respeta el limite ya declarado" || bad "re-acoto una salida ya acotada"
printf '%s' "$(si 'git log')" | grep -q updatedInput && ok "git log acotado via updatedInput" || bad "no acoto git log"
[[ -z "$(SES_SHRINK=off bash -c "printf '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git log\"}}' | bash hooks/scripts/shrink-input.sh")" ]] \
    && ok "SES_SHRINK=off desactiva" || bad "SES_SHRINK=off ignorado"

echo ""
echo "==> mcp-guard: techo por defecto solo si el modelo no puso uno"
mg(){ printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2" | bash hooks/scripts/mcp-guard.sh 2>/dev/null; }
printf '%s' "$(mg mcp__sap-adt__GetTableContents '{"table_name":"MARA"}')" | grep -q '"max_rows":100' \
    && ok "GetTableContents sin limite -> 100 filas" || bad "no aplico el techo"
[[ -z "$(mg mcp__sap-adt__GetTableContents '{"table_name":"MARA","max_rows":5000}')" ]] \
    && ok "respeta el limite explicito del modelo" || bad "piso el limite del modelo"
[[ -z "$(mg mcp__sap-ui5__get_guidelines '{}')" ]] && ok "tool sin limite conocido: no interviene" || bad "toco una tool desconocida"

echo ""
echo "==> SES_MODE gradua los gates"
rm -f tmp/.review-done tmp/.qa-nfr-done
gate_mode() {
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m feat"}}' \
        | SES_MODE="$1" bash "$DG" 2>&1
}
printf '%s' "$(gate_mode lite)" | grep -q '"permissionDecision":"allow"' \
    && ok "lite entrega con Gate 1 solamente" || bad "lite no dejo entregar" "$(gate_mode lite)"
printf '%s' "$(gate_mode full)" | grep -q deny \
    && ok "full sigue exigiendo los 3 gates" || bad "full no bloqueo" "$(gate_mode full)"
[[ -z "$(SES_MODE=lite bash hooks/scripts/agent-reinforcement.sh <<< '{"prompt":"/sap-abap x"}')" ]] \
    && ok "lite no inyecta refuerzo de agente" || bad "lite emitio refuerzo"

echo ""
echo "==> Las dos capas de enforcement no se anulan entre si"
# Regresion real: delivery-gate.sh (PreToolUse) validaba los flags, los BORRABA
# y aprobaba el commit; despues .husky/pre-commit corria mandatory-review.sh,
# no encontraba nada y rechazaba el commit que el gate acababa de aprobar.
# Resultado: ningun commit de codigo productivo podia pasar desde Claude Code.
mkdir -p srv && echo "module.exports={};" > srv/service.js && git add srv/service.js
flags_ok
COMMIT_JSON='{"tool_name":"Bash","tool_input":{"command":"git commit -m feat"}}'
# Con los flags frescos el gate aprueba en SILENCIO (exit 0, sin JSON): el JSON
# de decision solo se emite para denegar o para el allow explicito de SES_MODE.
# Por eso el contrato que se verifica es el exit code, no la salida.
DG_OUT="$(printf '%s' "$COMMIT_JSON" | bash "$DG" 2>&1)"; DG_RC=$?
[[ "$DG_RC" -eq 0 && "$DG_OUT" != *deny* ]] \
    && ok "delivery-gate aprueba el commit con los flags frescos" || bad "no aprobo el commit" "rc=$DG_RC $DG_OUT"
[[ -f tmp/.review-done && -f tmp/.qa-nfr-done ]] \
    && ok "en commit NO consume los flags (los consume husky)" \
    || bad "delivery-gate borro los flags que husky necesita"
bash hooks/scripts/mandatory-review.sh >/dev/null 2>&1 \
    && ok "mandatory-review los encuentra despues del gate" || bad "husky habria rechazado el commit aprobado"
# pre-commit VALIDA sin consumir: `git commit` sin -m abre el editor despues del
# hook, y un mensaje vacio abortaria el commit con los flags ya gastados.
[[ -f tmp/.review-done && -f tmp/.qa-nfr-done ]] \
    && ok "pre-commit valida sin consumir (el editor puede abortar el commit)" || bad "pre-commit consumio de mas"
# El consumo libera SOLO el arbol entregado, y solo si el commit exigia gates.
# Se emula un commit productivo real para que `dod_commit_files` tenga que mirar.
git -c core.hooksPath=/dev/null commit -qm "productivo" >/dev/null 2>&1
flags_ok
ARBOL_ENTREGADO=$(git rev-parse "HEAD^{tree}")
echo "$ARBOL_ENTREGADO" >> tmp/.review-done; echo "$ARBOL_ENTREGADO" >> tmp/.qa-nfr-done
DOD_CONSUME_ONLY=1 bash hooks/scripts/mandatory-review.sh >/dev/null 2>&1
grep -qx "$ARBOL_ENTREGADO" tmp/.review-done 2>/dev/null \
    && bad "el approval del arbol entregado sobrevivio" || ok "DOD_CONSUME_ONLY libera el arbol entregado"

# Y el approval de OTRO arbol —una sesion en paralelo— no se toca.
echo "1111111111111111111111111111111111111111" >> tmp/.review-done
DOD_CONSUME_ONLY=1 bash hooks/scripts/mandatory-review.sh >/dev/null 2>&1
grep -qx "1111111111111111111111111111111111111111" tmp/.review-done 2>/dev/null \
    && ok "no pisa el approval de otra sesion" || bad "borro el approval de un arbol ajeno"

# El commit de arriba dejo el arbol limpio; los bloques siguientes necesitan
# contenido productivo staged para que la DoD aplique.
echo "module.exports={v:2};" > srv/service.js && git add srv/service.js

flags_ok_head
printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | bash "$DG" >/dev/null 2>&1
[[ -f tmp/.review-done && -f tmp/.qa-nfr-done ]] \
    && ok "el push tampoco consume: el consumo vive solo en post-commit" || bad "el push consumio los flags"

echo ""
echo "==> Los approvals se anclan al arbol, no al reloj"
# Un flag que cubre otro arbol es distinto de un flag ausente: el primero
# significa "revisaron, y despues editaste"; el segundo, "nadie reviso".
flags_de_otro_arbol
OUT=$(gate "git commit -m x")
printf '%s' "$OUT" | grep -q "OTRO contenido" \
    && ok "distingue 'reviso otro arbol' de 'falta correr los gates'" || bad "mensaje generico" "$OUT"
[[ -f tmp/.review-done ]] && ok "un rechazo no consume el approval ajeno" || bad "borro flags al denegar"

# Un `touch` pelado (formato viejo) no dice QUE se reviso: no puede valer.
flags_viejo
printf '%s' "$(gate "git commit -m x")" | grep -q deny \
    && ok "un flag vacio (formato viejo) ya no alcanza" || bad "acepto un flag sin hash"

# El control ya no es el tiempo: con el arbol intacto, un approval viejo sirve.
flags_ok
touch -t 202001010000 tmp/.review-done tmp/.qa-nfr-done 2>/dev/null
OUT=$(DOD_MAX_AGE_SECONDS=86400 gate "git commit -m x")
printf '%s' "$OUT" | grep -q deny \
    && ok "la red de vencimiento por tiempo sigue existiendo" || bad "un flag de 2020 paso"

# commit mira el indice; push mira HEAD. Confundirlos deja el push trabado o abierto.
flags_ok
printf '%s' "$(gate "git push origin main")" | grep -q deny \
    && ok "un approval del indice NO habilita un push" || bad "el push acepto el arbol del indice"
flags_ok_head
[[ -z "$(gate "git push origin main")" ]] \
    && ok "un approval de HEAD si habilita el push" || bad "el push rechazo su propio arbol"

# Con los hooks desactivados los flags sobreviven, y eso ES seguro: estan
# anclados al hash del arbol, asi que solo cubren ese contenido exacto. El gate
# ya no necesita adivinar `--no-verify` mirando el texto del comando — esa
# heuristica reintroducia el deadlock con cualquier mensaje que trajera una
# palabra con guion terminada en `n`.
for variante in "git commit --no-verify -m x" "git commit -nm x" "git commit -n"; do
    flags_ok
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$variante" | bash "$DG" >/dev/null 2>&1
    [[ -f tmp/.review-done ]] \
        && ok "no adivina hooks desactivados: $variante" || bad "consumio de mas en: $variante"
done

# Y el approval sobreviviente no habilita otro contenido.
flags_ok
echo "cambio" >> srv/service.js && git add srv/service.js
printf '%s' "$(gate "git commit -m x")" | grep -q "OTRO contenido" \
    && ok "un flag sobreviviente no cubre un arbol distinto" || bad "el flag viejo aprobo contenido nuevo"
git checkout -- srv/service.js 2>/dev/null || true

# Regresion: el mensaje de commit NO puede activar la deteccion de opciones.
# Una palabra con guion terminada en `n` hacia que el gate consumiera creyendo
# que los hooks estaban desactivados; husky corria igual, no encontraba nada y
# rechazaba el commit recien aprobado. El deadlock original, por un mensaje.
for msg in "feat: nuevo endpoint" "fix: handle non-blocking IO" "feat: add sign-in flow" \
           "refactor: plug-in loader" "chore: re-run the pipeline" "docs: update add-on list"; do
    flags_ok
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"%s\\""}}' "$msg" \
        | bash "$DG" >/dev/null 2>&1
    [[ -f tmp/.review-done && -f tmp/.qa-nfr-done ]] \
        && ok "el mensaje no dispara la deteccion: $msg" || bad "deadlock por el mensaje: $msg"
done

echo ""
echo "==> Que cuenta como codigo productivo"
prod() { echo "$1" | grep -qE "$DOD_PRODUCTIVE_RE"; }
prod "skills/x/lib/render.mjs" && ok ".mjs es productivo (el motor no puede ser invisible)" || bad ".mjs invisible para la DoD"
prod "scripts/x.cjs" && ok ".cjs es productivo" || bad ".cjs invisible"
prod ".husky/pre-commit" && ok "los hooks de git son productivos (no tienen extension)" || bad ".husky/ invisible"
prod "docs/adr/README.md" && bad "un .md no deberia exigir gates 2+3" || ok "la documentacion no dispara gates"

echo ""
echo "==> El push se valida contra el registro de entregas gateadas"
# El atajo de "nada cambio" dejaba TODO push sin control: despues de un commit el
# working tree esta limpio, asi que la maquinaria de anclaje nunca se activaba.
# Un push publica commits, no archivos sin commitear.
rm -f tmp/.review-done tmp/.qa-nfr-done
# Primero una entrega registrada: fija la frontera desde la que el registro
# puede exigir. A la historia anterior no se le piden gates retroactivos.
echo "primero" > srv/primero.js && git add srv/primero.js
git -c core.hooksPath=/dev/null commit -qm "primero" 2>/dev/null
bash -c '. hooks/scripts/lib/dod-common.sh; dod_log_delivery "$(git rev-parse HEAD)" "$(git rev-parse HEAD^{tree})"'
sleep 1
# Y ahora uno hecho con los hooks desactivados, posterior a la frontera.
echo "para push" > srv/parapush.js && git add srv/parapush.js
git -c core.hooksPath=/dev/null commit -qm "sin registrar" 2>/dev/null
OUT=$(gate "git push origin main")
printf '%s' "$OUT" | grep -q "no figuran en el registro" \
    && ok "un commit posterior a la frontera y sin registro bloquea el push y lo nombra" \
    || bad "el push paso sin control" "$OUT"

# Sin registro todavia (adopcion), el push no queda abierto: cae al control
# normal de sellos, que es el comportamiento previo.
rm -f logs/gate-deliveries.log
printf '%s' "$(gate "git push origin main")" | grep -q deny \
    && ok "sin registro, el push cae al control de sellos en vez de abrirse" || bad "el push quedo abierto sin registro"

# Con el commit registrado, el push pasa sin pedir una revision nueva del mismo
# contenido: ya se reviso al commitear.
# En el flujo real cada commit queda registrado al hacerse; acá se emula
# registrando todos los que quedan por publicar.
bash -c '. hooks/scripts/lib/dod-common.sh
  for sha in $(git rev-list HEAD --not --remotes); do
    dod_log_delivery "$sha" "$(git rev-parse "$sha^{tree}")"
  done'
printf '%s' "$(gate "git push origin main")" | grep -q '"permissionDecision":"deny"' \
    && bad "el push rechazo commits ya gateados" || ok "commits registrados habilitan el push"

echo ""
echo "==> El hook post-commit consume tras un commit REAL"
# Regresion: post-commit corre con HEAD ya movido, asi que `git diff HEAD` da
# vacio. La evaluacion normal salia por "sin archivos productivos" y NUNCA
# consumia: un solo juego de gates cubria todos los commits de los 30 min.
# Este bloque corre `git commit` de verdad con core.hooksPath, no simula.
POSTDIR="$SANDBOX/realhooks"
mkdir -p "$POSTDIR"
cp "$STACK_ROOT/.husky/post-commit" "$POSTDIR/post-commit"
chmod +x "$POSTDIR/post-commit"
git config core.hooksPath "$POSTDIR"

# El arbol tiene que quedar REALMENTE limpio antes de este bloque.
#
# Antes los hooks copiados quedaban untracked, asi que `dod_changed_files` nunca
# daba vacio y el codigo con el bug de H-2 consumia igual: el mutante
# "reintroducir la evaluacion del working tree en DOD_CONSUME_ONLY" sobrevivia al
# harness. Con la infra commiteada y tmp/ y logs/ ignorados, post-commit corre en
# la misma condicion que en un repo real.
printf 'tmp/\nlogs/\nrealhooks/\n' > .gitignore
git add -A >/dev/null 2>&1
git -c core.hooksPath=/dev/null commit -qm "infra del sandbox" >/dev/null 2>&1
[[ -z "$(git status --porcelain)" ]] \
    && ok "el sandbox parte de un arbol limpio (si no, el mutante de H-2 sobrevive)" \
    || bad "el arbol del sandbox no quedo limpio" "$(git status --porcelain | head -3)"

echo "productivo" > srv/otro.js && git add srv/otro.js
flags_ok
ANTES=$(git rev-parse HEAD)
git commit -qm "entrega real" 2>/dev/null
[[ "$(git rev-parse HEAD)" != "$ANTES" ]] \
    && ok "el commit real se creo" || bad "el commit no se creo"
[[ ! -f tmp/.review-done && ! -f tmp/.qa-nfr-done ]] \
    && ok "post-commit consumio los flags con el arbol limpio" \
    || bad "los flags sobrevivieron a un commit exitoso (un juego de gates cubriria todos)"

# Mutante: sin el hook, los flags tienen que sobrevivir. Si esta asercion pasa
# igual sin post-commit, la de arriba no estaba probando nada.
rm -f "$POSTDIR/post-commit"
echo "otro" > srv/tercero.js && git add srv/tercero.js
flags_ok
git commit -qm "sin post-commit" 2>/dev/null
[[ -f tmp/.review-done && -f tmp/.qa-nfr-done ]] \
    && ok "sin el hook los flags sobreviven (la asercion anterior mide algo)" \
    || bad "el mutante no cambio nada: el test no cubre post-commit"
git config --unset core.hooksPath

echo ""
echo "==> Concurrencia y costo del registro"
# Regresion: los dos caminos que REESCRIBEN el flag usaban un temporal de nombre
# fijo sin lock. Dos procesos escribian el mismo .tmp, uno evaluaba el del otro,
# concluia "quedo vacio" y borraba approvals validos. El modo de falla no era
# "se perdio una linea" sino "desaparecio el archivo".
CONC="$SANDBOX/conc"; mkdir -p "$CONC"
for i in $(seq 1 30); do printf '%040d\n' "$i" >> "$CONC/flag"; done
for i in $(seq 1 20); do ( dod_flag_release "$CONC/flag" "$(printf '%040d' "$i")" ) & done
wait
[[ -f "$CONC/flag" && "$(wc -l < "$CONC/flag" | tr -d ' ')" = "10" ]] \
    && ok "20 liberaciones en paralelo dejan los 10 approvals ajenos" \
    || bad "liberacion concurrente perdio approvals" "$([[ -f "$CONC/flag" ]] && wc -l < "$CONC/flag" || echo 'el archivo desaparecio')"
[[ -z "$(ls "$CONC" | grep -v '^flag$')" ]] \
    && ok "no deja temporales ni locks huerfanos" || bad "quedo basura" "$(ls "$CONC")"

# Regresion M-13: el append quedaba FUERA del lock. La escritura de una linea es
# atomica por `O_APPEND`, pero el riesgo no era la escritura sino la convivencia:
# una liberacion concurrente lee el archivo, el append agrega una linea, y el
# `mv` de la liberacion se la lleva.
CONC2="$SANDBOX/conc2"; mkdir -p "$CONC2"
for i in $(seq 1 15); do printf '%040d\n' "$i" >> "$CONC2/flag"; done
for i in $(seq 1 20); do
    ( dod_flag_seal "$CONC2/flag" "$(printf 'a%039d' "$i")" 200 ) &
    ( dod_flag_release "$CONC2/flag" "$(printf '%040d' "$i")" ) &
done
wait 2>/dev/null
[[ "$(grep -c '^a' "$CONC2/flag" 2>/dev/null || echo 0)" = "20" ]] \
    && ok "sellar y liberar en paralelo no pierde sellos" \
    || bad "se perdieron sellos concurrentes" "presentes: $(grep -c '^a' "$CONC2/flag" 2>/dev/null || echo 0)/20"

# LOW-10: el aviso de degradacion del lock tiene que quedar en un LOG. El unico
# invocador automatico de la liberacion (post-commit) manda stderr a /dev/null,
# asi que un aviso por stream esta apagado justo en la ruta que nadie mira.
LOCKD="$SANDBOX/lockd"; mkdir -p "$LOCKD/flag.lock"   # lock huerfano permanente
rm -f "${CLAUDE_PROJECT_DIR}/logs/dod-lock-degradado.log"
# `DOD_LOCK_HUERFANO_SEG=0`: el test no puede esperar los 5s del umbral real.
( DOD_LOCK_HUERFANO_SEG=0 dod_flag_seal "$LOCKD/flag" "$(printf 'c%039d' 1)" ) >/dev/null 2>&1
[[ -s "${CLAUDE_PROJECT_DIR}/logs/dod-lock-degradado.log" ]] \
    && ok "la degradacion del lock queda registrada aunque se silencie stderr" \
    || bad "el aviso se perdio al redirigir stderr"

# El log existe para diagnosticar contencion, y eso pide distinguir a los
# participantes. `$$` los aplana a todos en el pid del shell invocante, y
# `$BASHPID` no existe en el bash 3.2 que trae macOS.
mkdir -p "$LOCKD/f2.lock"
rm -f "${CLAUDE_PROJECT_DIR}/logs/dod-lock-degradado.log"
for i in 1 2 3 4; do ( dod_flag_seal "$LOCKD/f2" "$(printf 'd%039d' "$i")" ) >/dev/null 2>&1 & done
wait 2>/dev/null
PIDS=$(awk '{print $2}' "${CLAUDE_PROJECT_DIR}/logs/dod-lock-degradado.log" 2>/dev/null | sort -u | wc -l | tr -d ' ')
[[ "${PIDS:-0}" -gt 1 ]] \
    && ok "el log distingue a los participantes de la contencion" \
    || bad "todos los eventos comparten pid: no se puede diagnosticar" "pids distintos: ${PIDS:-0}"
rmdir "$LOCKD/f2.lock" 2>/dev/null
rmdir "$LOCKD/flag.lock" 2>/dev/null

# LOW-8: el chequeo por arbol tiene que estar anclado. Sin anclar, un token mas
# largo que empiece con el hash da falso positivo.
LOGX=$(dod_delivery_log_path); mkdir -p "$(dirname "$LOGX")"
printf '2026-01-01T00:00:00Z %040d %s\n' 1 "$(printf 'b%039d' 1)deadbeef" > "$LOGX"
dod_delivery_tree_logged "$(printf 'b%039d' 1)" \
    && bad "falso positivo: un token mas largo matcheo" || ok "el chequeo por arbol esta anclado"

# LOW-9: la primera corrida no puede ensuciar stderr.
rm -f "$LOGX"
[[ -z "$(dod_log_delivery aaa bbb 2>&1 >/dev/null)" ]] \
    && ok "dod_log_delivery no escupe a stderr en la primera corrida" || bad "ruido en stderr"

# El barrido del registro esta acotado: tras un rebase que reescribe shas TODAS
# las lineas quedan muertas, y sin techo el push pagaba decenas de segundos.
LOGD=$(dod_delivery_log_path); mkdir -p "$(dirname "$LOGD")"
: > "$LOGD"
for i in $(seq 1 3000); do printf '2026-01-01T00:00:00Z %040d %040d\n' "$i" "$i"; done >> "$LOGD"
INICIO=$(date +%s)
dod_registro_base >/dev/null 2>&1
[[ $(( $(date +%s) - INICIO )) -le 5 ]] \
    && ok "3000 lineas muertas: el barrido corta por techo, no recorre todo" || bad "el barrido no esta acotado"
dod_registro_base >/dev/null 2>&1 \
    && bad "invento una base con el registro muerto" || ok "sin base utilizable falla cerrado"

# Rotacion ANTES de escribir: si no, la entrega recien anotada se va con el
# archivo rotado y el registro activo queda vacio.
: > "$LOGD"
for i in $(seq 1 2000); do printf '2026-01-01T00:00:00Z %040d %040d\n' "$i" "$i"; done >> "$LOGD"
dod_log_delivery "$(git rev-parse HEAD)" "$(git rev-parse HEAD^{tree})"
[[ "$(wc -l < "$LOGD" | tr -d ' ')" -le 2 && -f "${LOGD}.1" ]] \
    && ok "rota y la entrega nueva queda en el registro activo" || bad "la entrega se fue con el archivo rotado"
grep -q "$(git rev-parse HEAD)" "$LOGD" \
    && ok "el commit recien registrado figura" || bad "el commit no quedo registrado"

# LOW-7: un amend de solo mensaje no puede costar dos gates. Mismo arbol, sha nuevo.
: > "$LOGD"
dod_log_delivery "0000000000000000000000000000000000000001" "$(git rev-parse HEAD^{tree})"
dod_delivery_tree_logged "$(git rev-parse HEAD^{tree})" \
    && ok "el registro reconoce el arbol aunque el sha sea otro" || bad "no reconocio el arbol"

echo ""
echo "================================"
echo "PASS: $PASS  FAIL: $FAIL"
echo "================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
