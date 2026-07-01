#!/bin/bash
# auto-lint-cds.sh
# PostToolUse hook: corre CDS lint cuando se modifican archivos .cds

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo correr si el archivo es .cds
if echo "$FILE_PATH" | grep -q "\.cds$"; then
    # Verificar que cds está disponible
    if command -v pnpm dlx &> /dev/null; then
        pnpm --package=@sap/cds-dk dlx cds lint 2>/dev/null
    fi
fi

exit 0
