#!/bin/bash
# auto-lint-ui5.sh
# PostToolUse hook: corre UI5 linter en archivos de webapp/ después de editar

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo correr si el archivo está dentro de webapp/ y es .js o .xml
if echo "$FILE_PATH" | grep -q "webapp/.*\.\(js\|xml\)$"; then
    # Usa el `ui5lint` LOCAL del proyecto (respeta su package manager); si no está,
    # no hace nada (no impone pnpm ni descarga).
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
    if [[ -x "${PROJECT_DIR}/node_modules/.bin/ui5lint" ]]; then
        "${PROJECT_DIR}/node_modules/.bin/ui5lint" --file "$FILE_PATH" 2>/dev/null
    elif command -v ui5lint &> /dev/null; then
        ui5lint --file "$FILE_PATH" 2>/dev/null
    fi
fi

exit 0
