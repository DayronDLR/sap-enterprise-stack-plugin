#!/bin/bash
# quality-gate.sh — Gate 1 de la Definition of Done.
#
# Verifica linters/smells/Clean Core sobre los archivos cambiados.
#
# Ya NO es un hook `Stop`. Corria al final de cada turno, lo que significaba
# ejecutar cds lint / ui5lint / eslint / ATC scan en cada prompt y volcar su
# salida al contexto cada vez. Ahora se invoca en tres momentos:
#   - delivery-gate.sh, al commitear/pushear
#   - .husky/pre-commit, para commits hechos fuera de Claude
#   - /sap-gates, cuando el dev lo pide
#
# Contrato: texto plano por stdout + exit code (0 sin hallazgos, 1 con hallazgos).
# Acepta --mode=cli por compatibilidad con invocaciones existentes; es el unico
# modo que hay.

set -u

# Opt-out para consumidores del PLUGIN: si el script corre desde .../plugins/...
# (plugin instalado) y SES_SKIP_DOD_GATES=1, se omiten los gates de calidad. En el
# stack clonado/interno la Definition of Done es politica — el bypass auditado es
# via HOTFIX-OVERRIDE (ADR-005), no esta variable.
case "${BASH_SOURCE[0]:-$0}" in
  */plugins/*)
    if [ "${SES_SKIP_DOD_GATES:-}" = "1" ]; then
      echo "[DoD] SES_SKIP_DOD_GATES=1 -> quality gate omitido (opt-out del plugin)." >&2
      exit 0
    fi
    ;;
  *) ;;   # Fuera de plugins/: el opt-out del plugin no aplica.
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HOTFIX_FLAG="${PROJECT_DIR}/tmp/.hotfix-override"

# Stack observability (gap #8) + SLO timing (gap #2)
HOOK_NAME="quality-gate"
# shellcheck disable=SC1091
[[ -f "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh" ]] && \
    source "${PROJECT_DIR}/hooks/scripts/lib/emit-stack-event.sh"
type timed_section_start >/dev/null 2>&1 && timed_section_start
type emit_stack_event >/dev/null 2>&1 && emit_stack_event "start" '{}'

# shellcheck disable=SC1091
[[ -f "$(dirname "${BASH_SOURCE[0]}")/lib/dod-common.sh" ]] && \
    source "$(dirname "${BASH_SOURCE[0]}")/lib/dod-common.sh"

# El exit code es el contrato: lo consumen delivery-gate.sh y .husky/pre-commit.
gate_pass() {
    local msg="${1:-}"
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"approve\"}"
    [[ -n "$msg" ]] && printf '%s\n' "$msg"
    exit 0
}

gate_fail() {
    type emit_stack_event >/dev/null 2>&1 && \
        emit_stack_event "end" "{\"duration_ms\":$(timed_section_end_ms),\"decision\":\"block\"}"
    printf '%s\n' "$1"
    exit 1
}

# HOTFIX-OVERRIDE: en Gate 1 sigue bloqueando CRITICAL (security/regresion grave)
# pero los HIGH se degradan a WARNING. El override requiere razon valida +
# segundo aprobador (gap #6 — two-person rule). Ver docs/adr/005-two-person-hotfix-approval.md
HOTFIX_ACTIVE=0
if [[ -f "$HOTFIX_FLAG" ]]; then
    REASON_LINE=$(head -1 "$HOTFIX_FLAG" 2>/dev/null)
    APPROVER_LINE=$(grep -E '^APPROVED_BY: ' "$HOTFIX_FLAG" 2>/dev/null | head -1)
    REQUESTER=$(git config user.email 2>/dev/null || echo "unknown")
    APPROVER=$(echo "$APPROVER_LINE" | sed 's/^APPROVED_BY: *//')
    if echo "$REASON_LINE" | grep -qE '^REASON: .{20,}' && [[ -n "$APPROVER" ]] && [[ "$APPROVER" != "$REQUESTER" ]]; then
        HOTFIX_ACTIVE=1
    elif echo "$REASON_LINE" | grep -qE '^REASON: .{20,}'; then
        # Razon valida pero falta segundo aprobador → rechazar con mensaje claro
        gate_fail "HOTFIX-OVERRIDE inválido: falta APPROVED_BY (segundo aprobador). Formato requerido en tmp/.hotfix-override:
REASON: <ticket + descripcion + aprobador CAB, min 20 chars>
APPROVED_BY: <email distinto del solicitante ($REQUESTER)>
Ver docs/adr/005-two-person-hotfix-approval.md"
    fi
fi

# `core.quotePath` (default: on) hace que git CITE y escape cualquier path no
# ASCII: `srv/articulo.js` sale como `"srv/art\303\255culo.js"`. Con las
# comillas el path deja de matchear los filtros por extension y el archivo se
# vuelve INVISIBLE para este scan — falla ABIERTO, sin aviso. En un stack cuyo
# idioma de trabajo es el espanol eso no es un caso de borde.
# AUDITORIA A3 — `dod_git_paths` FALLA CERRADO. Antes, un error de git devolvia
# vacio y el gate concluia "no hay archivos que verificar" y aprobaba: el mismo
# mecanismo que mantuvo escondido el bypass por `core.quotePath`.
if [[ "${ABAP_SCAN_INCLUDE_SMOKETEST:-0}" = "1" ]]; then
    CHANGED_FILES=$(dod_git_paths --con-fixtures)
else
    CHANGED_FILES=$(dod_git_paths)
fi
if [[ $? -ne 0 ]]; then
    gate_fail "Gate 1 (Quality): no se pudo determinar que archivos verificar. El gate NO se ejecuto — un error de git no es un arbol limpio."
fi

# Los bundles generados no se escanean: se escanea su fuente.
CHANGED_FILES=$(printf '%s\n' "$CHANGED_FILES" | grep -vE "$DOD_GENERADOS_RE" || true)

CDS_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(cds|ddls|bdef|behv)$' || true)
UI5_CHANGED=$(echo "$CHANGED_FILES" | grep -E 'webapp/.*\.(js|xml)$' || true)
JS_CHANGED=$(echo "$CHANGED_FILES"  | grep '\.js$' || true)
ABAP_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(abap|prog|clas|fugr)$' || true)
MANIFEST_CHANGED=$(echo "$CHANGED_FILES" | grep -E 'webapp/manifest\.json$' || true)

ERRORS=""

# Los linters corren SOLO desde el toolchain LOCAL del proyecto
# (node_modules/.bin — lo crean npm/yarn/pnpm por igual). Un linter solo es fiable
# con la config y los plugins del propio proyecto (eslint config, @sap/eslint-plugin-cds,
# setup de ui5lint); un binario GLOBAL corriendo contra un proyecto ajeno produce
# errores de infra (p.ej. `cds lint` global → "ESLint is not installed") que serían
# CRITICAL falsos — otra forma de imponer toolchain. Por eso: si el linter no está
# instalado en el proyecto, se OMITE (return 127 → el caller lo trata como skip).
run_linter() {
    local bin="$1"; shift
    if [[ -x "${PROJECT_DIR}/node_modules/.bin/${bin}" ]]; then
        "${PROJECT_DIR}/node_modules/.bin/${bin}" "$@"
    else
        return 127
    fi
}

# ── Contabilidad de lo que el gate pudo y no pudo verificar ─────────────────
#
# AUDITORIA A2. `rc=127` (linter no instalado) se trataba igual que `rc=0`:
# skip SILENCIOSO. En este repo eso dejaba 3 de 5 verificaciones apagadas y un
# `.js` con `var`, `==` y variables sin usar pasaba el gate con rc=0.
#
# El razonamiento original era correcto y se conserva: un linter GLOBAL corriendo
# contra un proyecto ajeno produce errores de infraestructura que serian CRITICAL
# falsos. El defecto era no distinguir dos situaciones distintas:
#
#   no hay archivos de ese tipo   -> no aplica, silencio correcto
#   hay archivos y falta el linter -> NO SE PUDO VERIFICAR, y eso bloquea
#
# Un gate que no dice que verifico no es auditable.
VERIFICADO=""
OMITIDO=""
NO_VERIFICABLE=""

registrar_ok()   { VERIFICADO="${VERIFICADO}\n  ✓ $1"; }
registrar_skip() { OMITIDO="${OMITIDO}\n  – $1 (no aplica: sin archivos de ese tipo)"; }

# Hay archivos que requieren este linter y el linter no esta. No se puede
# afirmar que el codigo esta limpio, asi que no se afirma.
registrar_falta() {
    local linter="$1" n="$2" paquete="$3"
    # Se nombra el PAQUETE, no el comando de instalacion. Decir "pnpm add -D x"
    # impone un package manager al proyecto del cliente, que es justo la regla
    # que el stack sostiene en todo lo demas: el plugin corre con npm, yarn o
    # pnpm por igual y no elige por el usuario.
    NO_VERIFICABLE="${NO_VERIFICABLE}\n  ✗ ${linter}: ${n} archivo(s) lo requieren y no esta instalado en el proyecto.\n      Agrega \`${paquete}\` a las devDependencies del proyecto, con tu package manager."
}

# Envuelve una verificacion de linter: decide entre ok / hallazgos / no aplica /
# no verificable, y lo registra.
verificar_con_linter() {
    local etiqueta="$1" bin="$2" archivos="$3" instalar="$4"; shift 4
    if [[ -z "$archivos" ]]; then registrar_skip "$etiqueta"; return 0; fi
    local salida rc
    salida=$(run_linter "$bin" "$@" 2>&1); rc=$?
    if [[ $rc -eq 127 ]]; then
        registrar_falta "$etiqueta" "$(printf '%s\n' "$archivos" | sed '/^$/d' | wc -l | tr -d ' ')" "$instalar"
        return 0
    fi
    if [[ $rc -ne 0 ]]; then
        ERRORS="${ERRORS}\n[CRITICAL] ${etiqueta} fallo:\n${salida}"
        return 0
    fi
    registrar_ok "$etiqueta"
}

# 1) CDS lint
verificar_con_linter "CDS lint" cds "$CDS_CHANGED" "@sap/cds-dk" lint

# 2) UI5 linter
verificar_con_linter "UI5 linter" ui5lint "$UI5_CHANGED" "@ui5/linter"

# 3) ESLint.
#
# Los paths van por ARRAY, no por expansion sin comillas. Con `$JS_CHANGED`
# crudo, `webapp/foo bar.js` se partia en dos argumentos: eslint reportaba un
# error sobre un archivo inexistente y el archivo REAL nunca se revisaba — un
# bloqueo con el nombre equivocado y un archivo sin linter.
JS_ARR=()
while IFS= read -r _p; do [[ -n "$_p" ]] && JS_ARR+=("$_p"); done <<< "$JS_CHANGED"
# `${arr[@]+"${arr[@]}"}` y no `"${arr[@]}"`: en bash 3.2 —el de macOS— expandir
# un array VACIO bajo `set -u` es un "unbound variable" que aborta el gate. La
# forma con `+` expande a nada cuando no hay elementos.
# shellcheck disable=SC2068
verificar_con_linter "ESLint" eslint "$JS_CHANGED" "eslint" ${JS_ARR[@]+"${JS_ARR[@]}"}

# 4) ABAP smell scan (CRITICAL/HIGH bloquea)
if [[ -n "$ABAP_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ABAP_RESULT=$(bash "${SCRIPT_DIR}/abap-smell-scan.sh" 2>&1)
    ABAP_EXIT=$?
    if [[ "$ABAP_EXIT" -ne 0 ]]; then
        ERRORS="${ERRORS}\n${ABAP_RESULT}"
    fi
fi

# 4.5) Clean Core scan (ABAP/CDS) — bloquea modificaciones a SAP standard y APIs no released
if [[ -n "$ABAP_CHANGED" ]] || [[ -n "$CDS_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/clean-core-scan.sh" ]]; then
        CC_RESULT=$(bash "${SCRIPT_DIR}/clean-core-scan.sh" 2>&1)
        CC_EXIT=$?
        if [[ "$CC_EXIT" -ne 0 ]]; then
            ERRORS="${ERRORS}\n${CC_RESULT}"
        fi
    fi
fi

# 4.6) ATC config drift (validate-atc-config.js) — bloquea si config/atc-*.json invalido
ATC_CHANGED=$(echo "$CHANGED_FILES" | grep -E '^config/atc-(variant|exemptions)\.json$' || true)
if [[ -n "$ATC_CHANGED" ]]; then
    if [[ -f "${PROJECT_DIR}/scripts/validate-atc-config.js" ]]; then
        ATC_RESULT=$(node "${PROJECT_DIR}/scripts/validate-atc-config.js" 2>&1)
        ATC_EXIT=$?
        if [[ "$ATC_EXIT" -ne 0 ]]; then
            ERRORS="${ERRORS}\n[CRITICAL] ATC config invalido:\n${ATC_RESULT}"
        fi
    fi
fi

# 4.7) Diagramas SAP (.sapdiag.json) — el gate de composicion del motor sap-diagrams.
#      Un diagrama entregable corre en perfil `showcase`: 0 errores y 0 warnings.
#      Es el equivalente del linter para un artefacto visual: sin esto, un diagrama
#      con cajas solapadas o flechas cruzadas llega al cliente sin que nadie lo mida.
DIAGRAM_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.sapdiag\.json$' || true)
if [[ -n "$DIAGRAM_CHANGED" ]]; then
    # El motor puede venir del checkout del stack o del plugin instalado
    # (hooks/scripts/ y skills/ son hermanos en los dos layouts).
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SAPDIAG="${PROJECT_DIR}/skills/sap-diagrams/bin/sapdiag.mjs"
    [[ -f "$SAPDIAG" ]] || SAPDIAG="${SCRIPT_DIR}/../../skills/sap-diagrams/bin/sapdiag.mjs"
    # Fail-closed a proposito, al reves que los linters: un linter ausente es un
    # toolchain que el proyecto no adopto, pero el motor de diagramas VIENE con
    # el stack. Si no esta y hay un .sapdiag.json cambiado, algo se rompio y el
    # diagrama saldria al cliente sin medir.
    if [[ ! -f "$SAPDIAG" ]]; then
        ERRORS="${ERRORS}\n[CRITICAL] Hay diagramas cambiados pero no se encuentra el motor sap-diagrams (skills/sap-diagrams/bin/sapdiag.mjs). Sin el, el diagrama se entregaria sin validar."
    else
        while IFS= read -r spec; do
            [[ -z "$spec" ]] && continue
            [[ -f "${PROJECT_DIR}/${spec}" ]] || continue
            DIAG_RESULT=$(node "$SAPDIAG" validate "${PROJECT_DIR}/${spec}" --quality showcase 2>&1)
            DIAG_EXIT=$?
            # exit 1 = el diagrama tiene hallazgos. Cualquier otro codigo es el
            # motor que se cayo: son problemas distintos y piden acciones
            # distintas, asi que no pueden salir con el mismo mensaje.
            if [[ "$DIAG_EXIT" -eq 1 ]]; then
                ERRORS="${ERRORS}\n[CRITICAL] Diagrama ${spec} no pasa el gate de composicion:\n${DIAG_RESULT}"
            elif [[ "$DIAG_EXIT" -ne 0 ]]; then
                ERRORS="${ERRORS}\n[CRITICAL] El motor sap-diagrams fallo al validar ${spec} (exit ${DIAG_EXIT}). No es un problema del diagrama:\n${DIAG_RESULT}"
            fi
        done <<< "$DIAGRAM_CHANGED"
    fi
fi

# 5) Manifest UI5 (auto-validate-manifest.sh ya esta en PostToolUse, pero validamos
#    en cierre para detectar drift acumulado)
if [[ -n "$MANIFEST_CHANGED" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/auto-validate-manifest.sh" ]]; then
        MANIFEST_RESULT=$(bash "${SCRIPT_DIR}/auto-validate-manifest.sh" 2>&1) || \
            ERRORS="${ERRORS}\n[CRITICAL] Manifest UI5 invalido:\n${MANIFEST_RESULT}"
    fi
fi

# ── Reporte de alcance ──────────────────────────────────────────────────────
#
# AUDITORIA A2: el gate imprime SIEMPRE que verifico, que no aplicaba y que no
# pudo verificar. Antes salia en silencio con rc=0 y era imposible saber si habia
# aprobado o simplemente no habia corrido nada.
reportar_alcance() {
    [[ -n "$VERIFICADO" ]]      && printf 'Gate 1 verifico:%b\n' "$VERIFICADO"
    [[ -n "$OMITIDO" ]]         && printf 'No aplica:%b\n' "$OMITIDO"
    [[ -n "$NO_VERIFICABLE" ]]  && printf 'NO SE PUDO VERIFICAR:%b\n' "$NO_VERIFICABLE"
    return 0
}

# Un linter que falta con archivos que lo requieren no es un skip: es una
# verificacion que no ocurrio, y afirmar que el codigo esta limpio seria falso.
#
# Se acumula en `$ERRORS` en vez de cortar antes: adelantarlo hacia que un linter
# ausente OCULTARA los hallazgos CRITICAL ya detectados por los otros scanners.
# Perder informacion para reportar un problema distinto es otra forma de
# silenciar. Se reportan los dos.
if [[ -n "$NO_VERIFICABLE" ]]; then
    ERRORS="${ERRORS}\n[CRITICAL] Verificaciones que NO se pudieron ejecutar (un linter ausente no cuenta como aprobado):${NO_VERIFICABLE}"
fi

if [[ -n "$ERRORS" ]]; then
    # En HOTFIX: degradar HIGH a WARNING, mantener bloqueo solo si hay CRITICAL
    if [[ "$HOTFIX_ACTIVE" = "1" ]]; then
        CRIT_ONLY=$(printf '%b' "$ERRORS" | grep -E '\[CRITICAL\]' || true)
        if [[ -z "$CRIT_ONLY" ]]; then
            gate_pass "HOTFIX-OVERRIDE activo: Gate 1 detecto HIGH pero NO CRITICAL. Permitiendo entrega con warning. Findings: $(printf '%b' "$ERRORS" | tr '\n' ' ' | head -c 500)"
        fi
        # Si hay CRITICAL, ni siquiera HOTFIX lo permite
    fi
    gate_fail "$(printf "Gate 1 (Quality) fallo:%b\n\n%b" "$ERRORS" "$(reportar_alcance)")"
fi

gate_pass "$(reportar_alcance)"
