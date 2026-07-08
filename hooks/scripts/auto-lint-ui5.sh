#!/bin/bash
# auto-lint-ui5.sh
# PostToolUse hook: corre UI5 linter en archivos de webapp/ después de editar

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo correr si el archivo está dentro de webapp/ y es .js o .xml
if echo "$FILE_PATH" | grep -q "webapp/.*\.\(js\|xml\)$"; then
    # Usa SOLO el `ui5lint` LOCAL del proyecto (su setup); si no está instalado, no
    # hace nada (no usa un ui5lint global — evita falsos errores en proyectos no-UI5 —
    # ni impone pnpm ni descarga).
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
    if [[ -x "${PROJECT_DIR}/node_modules/.bin/ui5lint" ]]; then
        "${PROJECT_DIR}/node_modules/.bin/ui5lint" --file "$FILE_PATH" 2>/dev/null
    fi
fi

exit 0
