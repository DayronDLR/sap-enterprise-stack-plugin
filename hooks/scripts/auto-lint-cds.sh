#!/bin/bash
# auto-lint-cds.sh
# PostToolUse hook: corre CDS lint cuando se modifican archivos .cds

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo correr si el archivo es .cds
if echo "$FILE_PATH" | grep -q "\.cds$"; then
    # Usa SOLO el `cds` LOCAL del proyecto (su config + @sap/eslint-plugin-cds); si
    # no está instalado, no hace nada (no usa un cds global — evita falsos errores de
    # infra — ni impone pnpm ni descarga).
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
    if [[ -x "${PROJECT_DIR}/node_modules/.bin/cds" ]]; then
        "${PROJECT_DIR}/node_modules/.bin/cds" lint 2>/dev/null
    fi
fi

exit 0
