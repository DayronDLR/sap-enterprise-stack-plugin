#!/bin/bash
# protect-sensitive-files.sh
# PreToolUse hook: bloquea edicion de archivos sensibles.
# Recibe el JSON del evento (contrato ses.hook.v1) por stdin.

set -u

# `dod_tool_command` normaliza el comando entre hosts (`command` en Claude, `cmd`
# en Codex). Si la lib no esta, se degrada a la cobertura vieja —solo rutas
# explicitas— con aviso: un hook de seguridad no puede desaparecer en silencio.
_SPF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "${_SPF_DIR}/lib/dod-common.sh" ]]; then
    # shellcheck source=lib/dod-common.sh
    source "${_SPF_DIR}/lib/dod-common.sh"
else
    echo "[protect-sensitive-files] lib/dod-common.sh no encontrado: no se inspeccionan comandos de shell." >&2
    dod_tool_command() { printf ''; }
fi

# AUDITORIA A1 / PORTABILIDAD (ADR-012). Antes leia UNICAMENTE
# `tool_input.file_path`, que es la clave de Claude Code. Codex nombra el
# parametro `path` en `apply_patch` y OpenCode tambien usa `path`, asi que en
# esos hosts la proteccion no aplicaba: el hook corria, no encontraba ruta, y
# permitia escribir `.env`. Fallar abierto en un hook de seguridad es peor que
# no tenerlo, porque da la impresion de estar cubierto.
#
# Se leen TODAS las variantes, igual que `rutasDe()` en lib/hook-contract.mjs.
INPUT=$(cat)

# Este hook es de SEGURIDAD: no puede fallar abierto. Sin python3 —posible en una
# imagen minima de BAS, Cloud Foundry o CI— el `2>/dev/null` devolvia vacio, el
# bucle no iteraba, y una escritura a `.env` se permitia sin un solo aviso.
# El extractor de respaldo es bash puro sobre las cuatro claves que importan:
# menos preciso que un parser JSON, pero infinitamente mejor que no mirar.
if command -v python3 >/dev/null 2>&1; then
RUTAS=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    # Entrada invalida: no se puede evaluar. Se avisa por stderr y se permite;
    # bloquear cada escritura por un JSON raro deja al dev sin poder trabajar.
    print('__ENTRADA_INVALIDA__')
    sys.exit(0)
i = d.get('tool_input') or {}
crudas = [i.get('file_path'), i.get('path'), i.get('filePath'), i.get('notebook_path')]
crudas += i.get('file_paths') or []
for r in crudas:
    if isinstance(r, str) and r:
        print(r)
" 2>/dev/null)

else
    # Respaldo sin python3: se extraen los valores de las claves de ruta con
    # herramientas POSIX. Se avisa, porque es un modo degradado.
    echo "[protect-sensitive-files] python3 no disponible: se usa el extractor de respaldo (menos preciso)." >&2
    RUTAS=$(printf '%s' "$INPUT" \
        | tr ',{}' '\n\n\n' \
        | grep -oE '"(file_path|path|filePath|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
fi

if [[ "$RUTAS" = "__ENTRADA_INVALIDA__" ]]; then
    echo "[protect-sensitive-files] la entrada del hook no es JSON valido: no se pudo evaluar." >&2
    exit 0
fi

# Lista de archivos/patrones protegidos
PROTECTED_PATTERNS=(
    ".env"
    "default-env.json"
    "xs-security.json"
    "manifest.json"
    "mta.yaml"
    "package.json"
    "node_modules/"
    ".git/"
    "package-lock.json"
    "*.mtar"
    "mta_archives/"
)

# Un comando de shell que ESCRIBE sobre un archivo protegido cuenta igual.
#
# Hasta ahora el hook solo miraba `tool_input.file_path` y equivalentes, o sea las
# tools de escritura del host de referencia. Eso dejaba dos agujeros:
#
#   1. En Claude Code, `Bash: echo SECRET=1 >> .env` pasaba sin un solo aviso.
#   2. En Codex NO HAY tool de escritura —los archivos se editan por
#      `exec_command`— asi que el hook no cubria absolutamente nada.
#
# Se exige INTENCION DE ESCRITURA, no la sola mencion: `grep foo .env` sigue
# permitido, `echo x > .env` no. Bloquear toda mencion volveria el hook inusable
# y la gente lo terminaria desactivando, que es peor que no tenerlo.
CMD=$(dod_tool_command "$INPUT" 2>/dev/null || printf '')
if [[ -n "$CMD" ]]; then
    # Redireccion (`>`, `>>`), o un comando que escribe por naturaleza.
    ESCRIBE_RE='(^|[^0-9A-Za-z_])(>>?|tee|dd[[:space:]]|install[[:space:]])|(^|[[:space:]])(cp|mv|ln|truncate|sed[[:space:]]+-i|perl[[:space:]]+-i|vi|vim|nano|emacs)([[:space:]]|$)'
    if printf '%s' "$CMD" | grep -qE "$ESCRIBE_RE"; then
        RUTAS=$(printf '%s\n%s' "$RUTAS" "$CMD")
    fi
fi

# Verificar cada ruta contra cada patron protegido. Una sola coincidencia
# bloquea: si la herramienta toca varios archivos y uno esta protegido, la
# operacion completa no procede.
while IFS= read -r RUTA; do
    [[ -z "$RUTA" ]] && continue
    for PATTERN in "${PROTECTED_PATTERNS[@]}"; do
        if printf '%s' "$RUTA" | grep -qF "$PATTERN"; then
            echo "BLOQUEADO: No se puede editar '$RUTA' — archivo protegido" >&2
            exit 2
        fi
    done
done <<< "$RUTAS"

# Si no matchea ningún patrón, permitir
exit 0
