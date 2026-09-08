#!/bin/bash
# shrink-input.sh — acota la salida de comandos ruidosos ANTES de ejecutarlos.
#
# PreToolUse sobre `Bash`. Devuelve `updatedInput` con el comando reescrito.
#
# Por que PreToolUse y no PostToolUse: un hook PostToolUse NO puede reemplazar
# la salida de una tool (solo agregar `additionalContext`), asi que comprimir
# despues es imposible. PreToolUse si acepta `updatedInput`, o sea que el unico
# punto de intervencion real es reescribir el comando para que produzca menos.
#
# Reglas de diseño:
#   - Nunca cambiar la semantica del comando. Solo acotar su SALIDA.
#   - Nunca tocar un comando que ya trae su propio limite (`| head`, `| tail`,
#     `-n`, `--max-count`, redireccion a archivo): el modelo ya decidio.
#   - Nunca tocar comandos que escriben (git commit, rm, deploy). Solo lectura.
#   - Preservar siempre los errores: los filtros conservan stderr y las lineas
#     con ERROR/FAIL.
#
# Desactivar: SES_SHRINK=off

set -u

INPUT=$(cat)

[[ "${SES_SHRINK:-}" = "off" ]] && exit 0

# ── Fast path ────────────────────────────────────────────────────────────────
# Corre en cada comando Bash: si no matchea ninguno de los verbos ruidosos,
# salir sin parsear.
case "$INPUT" in
    *"git diff"*|*"git log"*|*"npm test"*|*"pnpm test"*|*"yarn test"*|\
    *"cds build"*|*"cds deploy"*|*"mvn "*|*"ui5 build"*|*"npm run"*|*"pnpm run"*|\
    *"find "*|*"ls -R"*|*"cat "*) ;;
    *) exit 0 ;;
esac

CMD=""
if command -v python3 >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | python3 -c \
        "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
fi
[[ -z "$CMD" ]] && exit 0

# El modelo ya acoto la salida, o la manda a un archivo: no intervenir.
case "$CMD" in
    *"| head"*|*"| tail"*|*"|head"*|*"|tail"*|*"> "*|*">>"*|*"shrink.mjs"*|\
    *"--max-count"*|*"-n "*|*"--stat"*|*"--name-only"*|*"--oneline"*) exit 0 ;;
esac

NEW=""
REASON=""

# Cada rama conserva errores y contexto util; solo recorta volumen.
case "$CMD" in
    # `git diff` completo sobre un repo grande vuelca miles de lineas. El resumen
    # + los nombres alcanzan para decidir que leer en detalle despues.
    "git diff"|"git diff "*)
        case "$CMD" in
            *"--"*) ;;   # ya viene acotado a paths concretos
            *) NEW="$CMD --stat && $CMD | node \"\${CLAUDE_PROJECT_DIR:-.}/scripts/shrink.mjs\" --type=diff --max-lines=120"
               REASON="git diff acotado: --stat + diff comprimido" ;;
        esac
        ;;
    "git log"|"git log "*)
        NEW="$CMD --oneline --max-count=30"
        REASON="git log acotado a 30 commits en formato corto" ;;
    # Suites de test y builds: interesa el resultado y los fallos, no el progreso.
    *"npm test"*|*"pnpm test"*|*"yarn test"*|*"npm run test"*|*"pnpm run test"*)
        NEW="$CMD 2>&1 | node \"\${CLAUDE_PROJECT_DIR:-.}/scripts/shrink.mjs\" --type=log --max-lines=60"
        REASON="salida de tests filtrada a fallos y resumen" ;;
    *"cds build"*|*"cds deploy"*|*"ui5 build"*|*"mvn "*|*"npm run build"*|*"pnpm run build"*)
        NEW="$CMD 2>&1 | node \"\${CLAUDE_PROJECT_DIR:-.}/scripts/shrink.mjs\" --type=log --max-lines=50"
        REASON="salida de build filtrada a errores y warnings" ;;
    # Listados masivos.
    "find "*|*"ls -R"*)
        NEW="$CMD 2>&1 | node \"\${CLAUDE_PROJECT_DIR:-.}/scripts/shrink.mjs\" --type=list --max-lines=60"
        REASON="listado acotado a cabeza y cola" ;;
    # `cat` de un archivo grande: se sugiere Read, que pagina.
    "cat "*)
        FILE=$(printf '%s' "$CMD" | awk '{print $2}')
        if [[ -f "$FILE" ]]; then
            LINES=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
            if [[ "${LINES:-0}" -gt 400 ]]; then
                NEW="sed -n '1,200p' \"$FILE\"; echo '… archivo de $LINES lineas truncado en 200 — usa la tool Read con offset para el resto'"
                REASON="cat de $LINES lineas truncado a 200"
            fi
        fi
        ;;
esac

[[ -z "$NEW" ]] && exit 0

# Emitir updatedInput. El escape lo hace python3 (ya esta disponible: se uso
# para leer el comando).
printf '%s' "$NEW" | python3 -c "
import json, sys
cmd = sys.stdin.read()
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'updatedInput': {'command': cmd},
    'permissionDecisionReason': '[shrink] $REASON'
  }
}))" 2>/dev/null || exit 0

exit 0
