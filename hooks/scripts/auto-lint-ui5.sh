#!/bin/bash
# auto-lint-ui5.sh
# PostToolUse hook: corre UI5 linter en archivos de webapp/ después de editar

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo correr si el archivo está dentro de webapp/ y es .js o .xml
if echo "$FILE_PATH" | grep -q "webapp/.*\.\(js\|xml\)$"; then
    # Verificar que el linter está disponible
    if command -v pnpm dlx &> /dev/null; then
        pnpm dlx @ui5/linter --file "$FILE_PATH" 2>/dev/null
    fi
fi

exit 0
