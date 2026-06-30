#!/bin/bash
# clean-core-scan.sh
# Detecta uso de APIs SAP NO liberadas (modificaciones a estandar, namespaces internos)
# en codigo ABAP/CDS. Bloquea con CRITICAL si encuentra patrones que violan Clean Core.
# Para validacion exhaustiva con MCP sap_get_object_details, usar /sap-cleancore-check.

set -u

CHANGED_FILES=$(
    {
        git diff --name-only HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
        if [ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]; then
            git ls-files 'hooks/scripts/__smoketest__/fixtures/*' 2>/dev/null
        fi
    } \
        | sort -u | grep -E '\.(abap|prog|clas|fugr|cds|ddls|bdef|behv|asfc|asinc|asinf)(\.|$)' \
        | { if [ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]; then cat; else grep -v '__smoketest__/'; fi; } \
        || true
)

[ -z "$CHANGED_FILES" ] && exit 0

FINDINGS=""

add() {
    FINDINGS="${FINDINGS}\n[$1] $2:$3 — $4"
}

scan() {
    local f="$1"
    [ -f "$f" ] || return 0

    # 1) Modificacion a estandar SAP (cualquier objeto sin Z*/Y*/namespace cliente /XX/)
    # Heuristica: clases/funciones con nombres CL_* o FUNCTION_MODULE sin Z/Y/namespace
    if [[ "$f" == *.clas* ]] || [[ "$f" == *.prog* ]]; then
        # Header del objeto: si el nombre del archivo empieza con CL_ (no ZCL_/YCL_) -> modificacion
        local base=$(basename "$f" | tr 'a-z' 'A-Z')
        if [[ "$base" =~ ^(CL_|IF_|FUNCTION_|FORM_|PROG_)[A-Z] ]] && [[ ! "$base" =~ ^(ZCL_|YCL_|ZIF_|YIF_|Z_|Y_|/[A-Z]+/) ]]; then
            add "CRITICAL" "$f" "1" "Modificacion a objeto SAP estandar detectada — usar enhancement/BAdI/CDS extension"
        fi
    fi

    # 2) Uso de namespace SAP internal (CL_ABAP_*, CL_GUI_*, CL_HTTP_* sin wrapper)
    # NOTA: usamos process substitution `< <(...)` (NO `| while`) para que el
    # subshell no se coma las modificaciones a FINDINGS (bug clasico de bash).
    while IFS=: read -r ln rest; do
        add "CRITICAL" "$f" "$ln" "Uso de API SAP internal (no released) — buscar alternativa released con sap_get_object_details"
    done < <(grep -niE '\b(CL_ABAP_INTERNAL|CL_BAL_INTERNAL|CL_SQL_INTERNAL|CL_DB_INTERNAL)' "$f" 2>/dev/null || true)

    # 3) CALL FUNCTION a modulos SAP standard NO liberados
    while IFS=: read -r ln rest; do
        local fname=$(echo "$rest" | grep -oE "'[A-Z][A-Z0-9_]+'" | head -1)
        add "HIGH" "$f" "$ln" "CALL FUNCTION $fname — verificar si es released API (preferir BAPI_* o /NS/* o wrappers Z)"
    done < <(grep -niE "CALL\s+FUNCTION\s+'[A-Z][A-Z0-9_]+'" "$f" 2>/dev/null | grep -vE "'(Z_|Y_|/[A-Z]+/|BAPI_)" || true)

    # 4) Acceso directo a tablas SAP standard via UPDATE/INSERT/MODIFY/DELETE
    while IFS=: read -r ln rest; do
        add "CRITICAL" "$f" "$ln" "Escritura DIRECTA a tabla SAP standard — usar BAPI/BO/RAP behavior, NO acceso directo"
    done < <(grep -niE '^\s*(UPDATE|INSERT|MODIFY|DELETE\s+FROM)\s+(MARA|MARC|MBEW|EKKO|EKPO|VBAK|VBAP|BKPF|BSEG|KNA1|LFA1|MAKT|T001)\b' "$f" 2>/dev/null || true)

    # 5) CDS view extendiendo vista SAP standard sin namespace cliente
    if [[ "$f" == *.cds* ]] || [[ "$f" == *.ddls* ]]; then
        while IFS=: read -r ln rest; do
            add "HIGH" "$f" "$ln" "EXTEND VIEW sin namespace cliente — usar metadata extension (.metadata) o append CDS"
        done < <(grep -niE '^\s*extend\s+view\s+' "$f" 2>/dev/null | grep -viE '\bextend\s+view\s+(Z|Y|/[A-Z]+/)' || true)
    fi

    # 6) RAP BDEF extendiendo behavior SAP standard
    if [[ "$f" == *.bdef* ]] || [[ "$f" == *.behv* ]]; then
        while IFS=: read -r ln rest; do
            add "HIGH" "$f" "$ln" "RAP behavior extension de objeto SAP — validar que sea released (sap_get_object_details)"
        done < <(grep -niE '^\s*extension\s+' "$f" 2>/dev/null | grep -viE '\bextension\s+(Z|Y|/[A-Z]+/)' || true)
    fi
}

for f in $CHANGED_FILES; do
    scan "$f"
done

if [ -n "$FINDINGS" ]; then
    if echo -e "$FINDINGS" | grep -qE '^\[(CRITICAL|HIGH)\]'; then
        echo "Clean Core scan — violaciones detectadas:"
        echo -e "$FINDINGS" | grep -E '^\[(CRITICAL|HIGH)\]'
        echo ""
        echo "Para validacion exhaustiva con catalogo SAP oficial, ejecutar: /sap-cleancore-check"
        exit 1
    fi
fi

exit 0
