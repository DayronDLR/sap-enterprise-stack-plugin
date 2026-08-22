#!/bin/bash
# auto-lint.sh — lint incremental tras editar un archivo.
#
# Reemplaza a auto-lint-ui5.sh + auto-lint-cds.sh + auto-validate-manifest.sh.
# Antes eran TRES hooks PostToolUse sobre el mismo matcher (Write|Edit|MultiEdit):
# tres invocaciones de bash y tres spawns de python3 por cada edicion, cada uno
# parseando el mismo JSON para leer el mismo campo. Ahora es un dispatcher unico
# que resuelve la extension primero y solo entonces trabaja.
#
# Reglas de salida (importan para el consumo de contexto):
#   - silencio absoluto si el lint pasa: un "todo ok" por edicion es ruido que
#     igual se paga en tokens en cada request posterior
#   - salida acotada a AUTO_LINT_MAX_LINES cuando hay hallazgos
#   - si el linter no esta en el node_modules del proyecto, no se hace nada
#     (nunca un binario global: produce errores de infra, no de codigo)

set -u

AUTO_LINT_MAX_LINES="${AUTO_LINT_MAX_LINES:-40}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

INPUT=$(cat)

# Extraer file_path sin spawnear un interprete: este hook corre en cada edicion.
FILE_PATH=""
if [[ "$INPUT" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FILE_PATH="${BASH_REMATCH[1]}"
fi
[[ -z "$FILE_PATH" ]] && exit 0

# Recorta la salida del linter para que un archivo con 200 hallazgos no vuelque
# 200 lineas al contexto. Las primeras N alcanzan para actuar.
emit() {
    local title="$1" body="$2"
    local total; total=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
    printf '%s\n' "$title"
    printf '%s\n' "$body" | head -n "$AUTO_LINT_MAX_LINES"
    [[ "$total" -gt "$AUTO_LINT_MAX_LINES" ]] && \
        printf '... (%s lineas mas, correr el linter completo para el detalle)\n' "$((total - AUTO_LINT_MAX_LINES))"
}

case "$FILE_PATH" in
    */webapp/*.js|*/webapp/*.xml|webapp/*.js|webapp/*.xml)
        BIN="${PROJECT_DIR}/node_modules/.bin/ui5lint"
        [[ -x "$BIN" ]] || exit 0
        OUT=$("$BIN" --file "$FILE_PATH" 2>/dev/null); RC=$?
        [[ "$RC" -ne 0 && -n "$OUT" ]] && emit "[ui5lint] $FILE_PATH" "$OUT"
        ;;
    *.cds)
        BIN="${PROJECT_DIR}/node_modules/.bin/cds"
        [[ -x "$BIN" ]] || exit 0
        # `cds lint` es un comando de raiz de proyecto: no acepta paths (ver
        # cap.cloud.sap/docs/tools/cds-lint). Pasarle el archivo devolveria un
        # error de uso en cada edicion — justo el ruido que este hook evita.
        # Para acotar por archivo habria que invocar eslint con el plugin de CDS
        # directamente, y eso depende de como cada proyecto configure su lint.
        OUT=$("$BIN" lint 2>/dev/null); RC=$?
        [[ "$RC" -ne 0 && -n "$OUT" ]] && emit "[cds lint] $FILE_PATH" "$OUT"
        ;;
esac

# manifest.json: no hay linter local, se pide validacion via MCP.
case "$FILE_PATH" in
    */manifest.json|manifest.json)
        echo "manifest.json modificado — ejecutar run_manifest_validation (ui5 MCP) para verificar routing, targets y dependencias."
        ;;
esac

exit 0
