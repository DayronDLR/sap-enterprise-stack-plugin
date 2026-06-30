#!/bin/bash
# abap-smell-scan.sh
# Escaneo de smells CRITICOS en codigo ABAP modificado.
# Sale con exit 1 + stdout descriptivo si encuentra hallazgos CRITICAL.
# Usado por quality-gate.sh (Gate 1) y mandatory-review.sh (Gate 2).

set -u

# Archivos ABAP modificados o nuevos (incluye .abap y .clas/.prog si fueran texto)
ABAP_FILES=$(
    {
        git diff --name-only HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
        # En smoketest, incluir fixtures aunque ya esten commiteados (caso CI)
        if [ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]; then
            git ls-files 'hooks/scripts/__smoketest__/fixtures/*' 2>/dev/null
        fi
    } \
        | sort -u | grep -E '\.(abap|prog|clas|fugr|asfc|asinc|asinf)(\.|$)' \
        | { if [ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]; then cat; else grep -v '__smoketest__/'; fi; } \
        || true
)

if [ -z "$ABAP_FILES" ]; then
    # Nada que escanear -> exito silencioso
    exit 0
fi

FINDINGS=""

add_finding() {
    local sev="$1"
    local file="$2"
    local line="$3"
    local msg="$4"
    FINDINGS="${FINDINGS}\n[${sev}] ${file}:${line} — ${msg}"
}

scan_file() {
    local f="$1"
    [ -f "$f" ] || return 0

    # 1) SELECT * en codigo productivo
    # NOTA: process substitution `< <(...)` (NO `| while`) para no perder findings en subshell
    while IFS=: read -r ln rest; do
        add_finding "CRITICAL" "$f" "$ln" "SELECT * — usar lista de campos explicita"
    done < <(grep -niE '^\s*SELECT\s+\*' "$f" 2>/dev/null || true)

    # 2) SELECT ... INTO TABLE sin PACKAGE SIZE (riesgo OOM en masivos)
    # NOTA: awk POSIX no soporta el modificador /re/i — usamos tolower() en todas las comparaciones
    while IFS='|' read -r ln msg; do
        [ -n "$ln" ] && add_finding "CRITICAL" "$f" "$ln" "$msg"
    done < <(awk '
        BEGIN { in_sel=0; has_pkg=0; start_ln=0; buf="" }
        { lc=tolower($0) }
        !in_sel && lc ~ /^[[:space:]]*select[[:space:]]/ { in_sel=1; start_ln=NR; buf=""; has_pkg=0 }
        in_sel {
            buf = buf " " lc
            if (lc ~ /package size/) has_pkg=1
            if (lc ~ /\./) {
                if (buf ~ /into table/ && !has_pkg && buf !~ /up to .* rows/) {
                    print start_ln "|SELECT ... INTO TABLE sin PACKAGE SIZE ni UP TO N ROWS — riesgo OOM en volumenes"
                }
                in_sel=0; has_pkg=0; buf=""
            }
        }
    ' "$f" 2>/dev/null)

    # 3) LOOP ... MODIFY DB acoplado (anti-patron clasico)
    while IFS='|' read -r ln msg; do
        [ -n "$ln" ] && add_finding "CRITICAL" "$f" "$ln" "$msg"
    done < <(awk '
        BEGIN { in_loop=0; loop_ln=0 }
        { lc=tolower($0) }
        lc ~ /^[[:space:]]*loop[[:space:]]+at/ { in_loop=1; loop_ln=NR; next }
        in_loop && lc ~ /^[[:space:]]*(update|modify|delete)[[:space:]]+[a-z]/ && lc !~ /^[[:space:]]*(modify|update|delete)[[:space:]]+(table|itab|lt_|gt_|ls_|gs_|<)/ {
            print loop_ln "|LOOP con UPDATE/MODIFY/DELETE en DB — desacoplar lectura/escritura"
            in_loop=0
            next
        }
        lc ~ /^[[:space:]]*endloop/ { in_loop=0 }
    ' "$f" 2>/dev/null)

    # 4) UPDATE/MODIFY/DELETE en DB sin SY-SUBRC verificado dentro de 5 lineas
    while IFS='|' read -r ln msg; do
        [ -n "$ln" ] && add_finding "HIGH" "$f" "$ln" "$msg"
    done < <(awk '
        { lc=tolower($0) }
        lc ~ /^[[:space:]]*(update|modify|delete)[[:space:]]+[a-z]/ && lc !~ /^[[:space:]]*(update|modify|delete)[[:space:]]+(table|itab|lt_|gt_|ls_|gs_|<)/ {
            ln=NR; check=0
            for (i=1; i<=5 && (getline next_line)>0; i++) {
                if (tolower(next_line) ~ /sy-subrc/) { check=1; break }
            }
            if (!check) print ln "|Escritura en DB sin chequeo de SY-SUBRC en las siguientes 5 lineas"
        }
    ' "$f" 2>/dev/null)

    # 5) ENQUEUE_E* sin DEQUEUE_E* en el mismo archivo (lock fugado)
    if grep -qE 'ENQUEUE_E[A-Z0-9_]+' "$f" 2>/dev/null; then
        if ! grep -qE 'DEQUEUE_E[A-Z0-9_]+|DEQUEUE_ALL' "$f" 2>/dev/null; then
            ln=$(grep -nE 'ENQUEUE_E[A-Z0-9_]+' "$f" 2>/dev/null | head -1 | cut -d: -f1)
            add_finding "HIGH" "$f" "${ln:-1}" "ENQUEUE_E* sin DEQUEUE_E* / DEQUEUE_ALL en el archivo"
        fi
    fi

    # 6) EML MODIFY ENTITIES sin FAILED/REPORTED capturado
    if grep -qE 'MODIFY\s+ENTITIES\b' "$f" 2>/dev/null; then
        if ! grep -qE 'FAILED\s+DATA\(|REPORTED\s+DATA\(|failed\s+=|reported\s+=' "$f" 2>/dev/null; then
            ln=$(grep -nE 'MODIFY\s+ENTITIES\b' "$f" 2>/dev/null | head -1 | cut -d: -f1)
            add_finding "CRITICAL" "$f" "${ln:-1}" "MODIFY ENTITIES sin capturar FAILED/REPORTED — errores RAP silenciados"
        fi
    fi

    # 7) COMMIT WORK al final de bucle masivo (anti-patron)
    if grep -qiE 'package size' "$f" 2>/dev/null; then
        commit_count=$(grep -ciE 'COMMIT WORK' "$f" 2>/dev/null)
        commit_count=${commit_count:-0}
        if [ "$commit_count" -le 1 ]; then
            ln=$(grep -niE 'package size' "$f" 2>/dev/null | head -1 | cut -d: -f1)
            add_finding "HIGH" "$f" "${ln:-1}" "PACKAGE SIZE detectado pero <=1 COMMIT WORK — falta commit boundary por paquete"
        fi
    fi

    # 8) ABAP_TRUE / ABAP_FALSE hardcoded como 'X' o ' ' (legibilidad / smell)
    while IFS=: read -r ln rest; do
        add_finding "INFO" "$f" "$ln" "Comparacion contra 'X' literal — preferir abap_true"
    done < <(grep -niE "= '\s*X\s*'" "$f" 2>/dev/null || true)
}

for f in $ABAP_FILES; do
    scan_file "$f"
done

if [ -n "$FINDINGS" ]; then
    # Si hay CRITICAL o HIGH, bloquear
    if echo -e "$FINDINGS" | grep -qE '^\[(CRITICAL|HIGH)\]'; then
        echo "ABAP smell scan — hallazgos CRITICAL/HIGH:"
        echo -e "$FINDINGS" | grep -E '^\[(CRITICAL|HIGH)\]'
        exit 1
    else
        # Solo INFO -> reportar pero no bloquear
        echo "ABAP smell scan — info (no bloquea):"
        echo -e "$FINDINGS"
        exit 0
    fi
fi

exit 0
