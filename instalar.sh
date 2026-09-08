#!/usr/bin/env bash
# instalar.sh — copia el bundle de un host a tu proyecto.
#
# Existe para quien tiene el repo PUBLICO y no el fuente: los bundles ya vienen
# generados, asi que instalar es copiar. Quien tenga el repo fuente puede usar
# `node bin/ses.mjs init --host <host> --dir <proyecto>`, que hace lo mismo con
# mejor reporte de conflictos.
set -euo pipefail

HOST="${1:-}"
DESTINO="${2:-$PWD}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/bundles"

if [[ -z "$HOST" || ! -d "$AQUI/$HOST" ]]; then
    echo "uso: ./instalar.sh <codex|opencode|copilot> [directorio del proyecto]" >&2
    echo "" >&2
    echo "  Claude Code no usa este script: se instala desde el marketplace." >&2
    exit 1
fi

[[ -d "$DESTINO" ]] || { echo "✗ el destino no existe: $DESTINO" >&2; exit 1; }

# Aditivo y sin pisar: un archivo que ya existe con otro contenido DETIENE la
# instalacion. El proyecto es de quien lo abre, no del bundle.
conflictos=()
while IFS= read -r rel; do
    origen="$AQUI/$HOST/$rel"
    destino="$DESTINO/$rel"
    [[ -e "$destino" ]] || continue
    cmp -s "$origen" "$destino" || conflictos+=("$rel")
done < <(cd "$AQUI/$HOST" && find . -type f | sed 's|^\./||')

if [[ ${#conflictos[@]} -gt 0 && "${3:-}" != "--force" ]]; then
    echo "✗ ${#conflictos[@]} archivo(s) del proyecto difieren del bundle. No se toco nada:" >&2
    printf '    %s\n' "${conflictos[@]:0:20}" >&2
    echo "" >&2
    echo "  Revisalos y, si el bundle debe ganar, repeti con --force." >&2
    exit 1
fi

cp -R "$AQUI/$HOST/." "$DESTINO/"
find "$DESTINO" -name '*.sh' -path '*hooks*' -exec chmod 700 {} + 2>/dev/null || true

echo "✓ bundle de $HOST instalado en $DESTINO"
case "$HOST" in
    codex)
        echo ""
        echo "  Un paso mas: abri Codex una vez en el proyecto y aceptá cuando"
        echo "  pregunte si confiás en la carpeta. Hasta entonces los hooks no corren."
        ;;
    *) ;;
esac
