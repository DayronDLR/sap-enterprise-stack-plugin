#!/bin/bash
# protect-sensitive-files.sh
# PreToolUse hook: el agente no escribe SECRETOS ni SALIDA GENERADA.
# Recibe el JSON del evento (contrato ses.hook.v1) por stdin; corre sobre las
# tools de escritura Y sobre el shell.
#
# TRES CATEGORIAS, no una lista.
#
# La version anterior tenia una sola lista y la comparaba por substring. Mezclaba
# dos cosas que no se parecen:
#
#   - secretos (`.env`, `default-env.json`): el agente no tiene por que escribirlos;
#   - configuracion del proyecto (`package.json`, `manifest.json`, `mta.yaml`,
#     `xs-security.json`): el agente TIENE que editarlos. El flujo del agente
#     Fiori incluye una ronda de `manifest.json` y el de CAP escribe `mta.yaml` y
#     `xs-security.json`.
#
# Bloquear la configuracion no la protegia: el agente daba vueltas y terminaba
# editandola por el shell, que este hook no miraba. Ahora:
#
#   SECRETO   -> se deniega, por Edit/Write y por el shell. Lo edita la persona.
#   GENERADO  -> se deniega la escritura a mano (se regenera con su herramienta).
#   CONFIG    -> se permite. El control es determinístico y en el lugar correcto:
#                el Gate 1 revisa el cambio (`config-risk-scan.mjs`: scripts de
#                ciclo de vida, dependencias fuera del registro, lockfiles, etc.).
#
# Y se compara por NOMBRE de archivo o componente de ruta, nunca por substring:
# `.env.example`, `srv/lib/.environment.js` o `docs/how-to-edit-package.json.md`
# no son secretos.

set -u

INPUT=$(cat)

deny() {
    echo "BLOQUEADO: $1" >&2
    exit 2
}

# ── Clasificacion ────────────────────────────────────────────────────────────
# Imprime `secreto`, `generado` o nada.
clasificar() {
    local ruta nombre
    # Sin distinguir mayusculas: en APFS (macOS) y NTFS `.ENV` ES `.env`.
    ruta=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    nombre="${ruta%/}"
    nombre="${nombre##*/}"
    case "$nombre" in
        .env.example|.env.sample|.env.template|.env.dist|.env.defaults) ;;
        default-env.json|default-services.json|.cdsrc-private.json|.env.*|.env \
        |*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|service-key*.json \
        |.npmrc|.netrc|id_rsa|id_rsa.*|id_ecdsa|id_ecdsa.*|id_ed25519|id_ed25519.*)
            echo secreto; return ;;
        *.mtar|package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock)
            echo generado; return ;;
        *) ;;  # configuracion o codigo: se sigue con la ruta completa
    esac
    case "/${ruta}/" in
        */node_modules/*|*/mta_archives/*|*/.git/*) echo generado ;;
        *) ;;  # ni secreto ni generado: sin categoria, se permite
    esac
}

motivo() {
    case "$1" in
        secreto)  printf "'%s' guarda credenciales. El agente no escribe secretos: editalo a mano." "$2" ;;
        generado) printf "'%s' es salida generada. No se edita a mano: se regenera (npm install, mbt build, git)." "$2" ;;
        *) printf "'%s' esta protegido." "$2" ;;
    esac
}

# ── Rutas de las tools de escritura ──────────────────────────────────────────
# Se leen TODAS las variantes de clave (`file_path` en Claude, `path` en Codex y
# OpenCode), igual que `rutasDe()` en lib/hook-contract.mjs. Leer solo la del
# host de referencia dejaba el hook sin efecto en los otros.
#
# Este hook es de SEGURIDAD: sin python3 —posible en una imagen minima de BAS,
# Cloud Foundry o CI— no puede fallar abierto. El respaldo es bash puro.
CMD=""
if command -v python3 >/dev/null 2>&1; then
    # `-I -S`: un PYTHONPATH o un sitecustomize plantado no cambia el parseo,
    # igual que en `dod_tool_command`.
    SALIDA=$(printf '%s' "$INPUT" | python3 -I -S -c "
import json, sys, base64
try:
    d = json.load(sys.stdin)
except Exception:
    print('__ENTRADA_INVALIDA__')
    sys.exit(0)
i = d.get('tool_input') or {}
crudas = [i.get('file_path'), i.get('path'), i.get('filePath'), i.get('notebook_path')]
crudas += i.get('file_paths') or []
for r in crudas:
    if isinstance(r, str) and r:
        print('R\t' + r)
c = i.get('command') or i.get('cmd')
if isinstance(c, list):
    c = ' '.join(str(x) for x in c)
if isinstance(c, str) and c:
    print('C\t' + base64.b64encode(c.encode()).decode())
" 2>/dev/null)
    if [[ "$SALIDA" = "__ENTRADA_INVALIDA__" ]]; then
        # Bloquear cada escritura por un JSON raro deja al dev sin poder trabajar.
        echo "[protect-sensitive-files] la entrada del hook no es JSON valido: no se pudo evaluar." >&2
        exit 0
    fi
    RUTAS=$(printf '%s\n' "$SALIDA" | sed -n 's/^R	//p')
    CMD_B64=$(printf '%s\n' "$SALIDA" | sed -n 's/^C	//p')
    [[ -n "$CMD_B64" ]] && CMD=$(printf '%s' "$CMD_B64" | base64 -d 2>/dev/null || printf '%s' "$CMD_B64" | base64 -D 2>/dev/null)
else
    echo "[protect-sensitive-files] python3 no disponible: se usa el extractor de respaldo (menos preciso)." >&2
    RUTAS=$(printf '%s' "$INPUT" \
        | tr ',{}' '\n\n\n' \
        | grep -oE '"(file_path|path|filePath|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    _SPF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    if [[ -f "${_SPF_DIR}/lib/dod-common.sh" ]]; then
        # shellcheck source=lib/dod-common.sh
        source "${_SPF_DIR}/lib/dod-common.sh"
        CMD=$(dod_tool_command "$INPUT" 2>/dev/null || printf '')
    fi
fi

while IFS= read -r RUTA; do
    [[ -z "$RUTA" ]] && continue
    CLASE=$(clasificar "$RUTA")
    [[ -n "$CLASE" ]] && deny "$(motivo "$CLASE" "$RUTA")"
done <<< "$RUTAS"

[[ -z "$CMD" ]] && exit 0

# ── Comandos de shell ────────────────────────────────────────────────────────
# Camino rapido: si el comando no MENCIONA nada sensible, no hay nada que mirar.
# Es el caso de casi todos los comandos, y cuesta un grep, no un node.
SENSIBLE_RE='default-env\.json|default-services|cdsrc-private|\.env\.|\.env[^A-Za-z0-9]|\.env$|\.pem|\.key|\.p12|\.pfx|\.jks|keystore|service-key|\.npmrc|\.netrc|id_rsa|id_ecdsa|id_ed25519|node_modules|mta_archives|\.mtar|\.git|package-lock|shrinkwrap|pnpm-lock|yarn\.lock'
printf '%s' "$CMD" | grep -qiE "$SENSIBLE_RE" || exit 0

# Heuristica CERRADA para secretos: intencion de escritura en el comando + un
# secreto mencionado. Se usa cuando no se pudo seguir el destino: sin node, si el
# analizador fallo, o si el destino depende de algo que solo se resuelve al
# ejecutar (`> "$F"`). Bloquea de mas antes que dejar pasar un secreto; la salida
# generada no justifica bloquear a ciegas.
heuristica_secreto() {
    local motivo="$1"
    local escribe='(^|[^A-Za-z_=-])(>>?|tee|dd[[:space:]]|install[[:space:]])|(^|[[:space:]])(cp|mv|ln|truncate|rm|sed[[:space:]]+-i|perl[[:space:]]+-i)([[:space:]]|$)'
    local secreto='(^|[/[:space:]"'"'"'$=>{,])(default-env\.json|default-services\.json|\.cdsrc-private\.json|[^[:space:]]*\.(pem|key|p12|pfx|jks|keystore)|service-key[^[:space:]]*\.json|\.npmrc|\.netrc|id_(rsa|ecdsa|ed25519)[^[:space:]]*|\.env\.[A-Za-z0-9_-]+|\.env)([[:space:]"'"'"';|&)`\\*?{},]|$)'
    local cmd_min
    # Las plantillas (`.env.example` y compañía) no son secretos: el clasificador
    # principal ya las exime, y la heuristica tiene que decir lo mismo.
    cmd_min=$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/\.env\.(example|sample|template|dist|defaults)([^a-z0-9_-]|$)/\2/g')
    if printf '%s' "$cmd_min" | grep -qE "$escribe" && printf '%s' "$cmd_min" | grep -qE "$secreto"; then
        deny "el comando parece escribir un secreto y $motivo. Hacelo a mano."
    fi
}

_SPF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if ! command -v node >/dev/null 2>&1 || [[ ! -f "${_SPF_DIR}/lib/destinos-escritura.mjs" ]]; then
    echo "[protect-sensitive-files] node no disponible: se usa la heuristica de respaldo para secretos." >&2
    heuristica_secreto "sin node no se puede comprobar el destino"
    exit 0
fi

# Se sigue cada DESTINO hasta su comando: `cat package.json > /tmp/x` escribe
# /tmp/x, no package.json.
if ! DESTINOS=$(printf '%s' "$CMD" | node "${_SPF_DIR}/lib/destinos-escritura.mjs" 2>/dev/null); then
    # Un analizador que falla no puede terminar en "sin destinos, se permite".
    echo "[protect-sensitive-files] el analizador de destinos fallo: se usa la heuristica de respaldo." >&2
    heuristica_secreto "no se pudo analizar el comando"
    exit 0
fi
while IFS=$'\t' read -r TIPO RUTA; do
    [[ -z "$RUTA" ]] && continue
    if [[ "$TIPO" == dinamico-* ]]; then
        # Si el ultimo componente es literal (`"$TMPDIR/build"`, `"$HOME/.env"`), el
        # nombre del archivo se conoce: se clasifica ese. Si no (`"$F"`, `{}`, un
        # glob), solo queda la heuristica sobre el comando.
        COLA="${RUTA##*/}"
        if [[ "$RUTA" == */* && -n "$COLA" && ! "$COLA" =~ [\$\`\{\}\(\)\*\?\[] ]]; then
            CLASE=$(clasificar "$COLA")
            [[ "$TIPO" = "dinamico-borra" && "$CLASE" != "secreto" ]] && continue
            [[ -n "$CLASE" ]] && deny "$(motivo "$CLASE" "$RUTA")"
            continue
        fi
        heuristica_secreto "el destino '$RUTA' solo se conoce al ejecutar"
        continue
    fi
    CLASE=$(clasificar "$RUTA")
    # Borrar salida generada es legitimo (`rm -rf node_modules`); borrar un
    # secreto, no.
    [[ "$TIPO" = "borra" && "$CLASE" != "secreto" ]] && continue
    [[ -n "$CLASE" ]] && deny "$(motivo "$CLASE" "$RUTA")"
done <<< "$DESTINOS"
exit 0
