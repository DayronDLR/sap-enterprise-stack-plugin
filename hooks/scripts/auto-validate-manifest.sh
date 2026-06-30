#!/bin/bash
# auto-validate-manifest.sh
# PostToolUse hook: detecta edición de manifest.json y solicita validación MCP

FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if echo "$FILE_PATH" | grep -q "manifest\.json$"; then
    echo "manifest.json modificado — ejecutar mcp__ui5-mcp__run_manifest_validation para verificar routing, targets y dependencias."
fi

exit 0
