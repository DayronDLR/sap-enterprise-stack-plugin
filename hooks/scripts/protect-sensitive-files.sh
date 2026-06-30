#!/bin/bash
# protect-sensitive-files.sh
# PreToolUse hook: bloquea edición de archivos sensibles
# Claude recibe el JSON del evento en stdin

# Leer el file_path del input JSON
FILE_PATH=$(cat | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

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

# Verificar si el archivo matchea algún patrón protegido
for PATTERN in "${PROTECTED_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -q "$PATTERN"; then
        echo "BLOQUEADO: No se puede editar '$FILE_PATH' — archivo protegido" >&2
        exit 2
    fi
done

# Si no matchea ningún patrón, permitir
exit 0
