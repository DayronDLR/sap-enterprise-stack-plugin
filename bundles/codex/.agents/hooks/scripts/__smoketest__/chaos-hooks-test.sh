#!/bin/bash
# chaos-hooks-test.sh
# Verifica resilencia de los hook scripts ante condiciones adversas:
#   - Tiempo de ejecucion acotado (no hang infinito)
#   - SIGTERM mid-execution → cleanup limpio (sin lock/tmp huerfanos)
#   - Dependencias faltantes en PATH → fallo claro, no hang
#   - Hook devuelve exit code inesperado → la sesion no se queda colgada
#
# Cubre los hooks que pueden trabar una entrega: el gate de entrega y su
# sellador, el quality gate, la red de husky, y los SubagentStop.
# Uso: bash hooks/scripts/__smoketest__/chaos-hooks-test.sh

set -u
cd "$(dirname "$0")/../../.." || exit 1

# Hard cap por hook (segundos). Si excede → bloqueante.
TIMEOUT_HARD=60
# Soft cap (warning, no falla). Apunta al SLO documentado en docs/SLO-HOOKS.md.
TIMEOUT_SOFT=15

# Los tres primeros son los historicos. Los tres ultimos son los que deciden si
# una entrega sale o no, y NO estaban: la resiliencia del aparato que bloquea
# commits no tenia una sola prueba automatizada. Un chaos test que no incluye el
# hook mas critico del repo da la impresion de cobertura sin darla.
HOOKS_UNDER_TEST=(
    "hooks/scripts/quality-gate.sh"
    "hooks/scripts/protect-sensitive-files.sh"
    "hooks/scripts/log-agent-activity.sh"
    "hooks/scripts/delivery-gate.sh"
    "hooks/scripts/sellar-gate.sh"
    "hooks/scripts/mandatory-review.sh"
)

# Lo que recibe un hook cuando el dev entrega de verdad. Alimentar los hooks con
# stdin vacio los hace salir por el fast path sin tocar una sola dependencia, y
# el test pasa sin haber ejercido nada.
PAYLOAD_ENTREGA='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'

PASS=0
FAIL=0
WARN=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

color_pass() { local msg="$1"; printf '  \033[32mPASS\033[0m  %s\n' "$msg"; PASS=$((PASS+1)); return 0; }
color_fail() { local msg="$1"; printf '  \033[31mFAIL\033[0m  %s\n' "$msg"; FAIL=$((FAIL+1)); return 0; }
color_warn() { local msg="$1"; printf '  \033[33mWARN\033[0m  %s\n' "$msg"; WARN=$((WARN+1)); return 0; }

echo "==> Chaos test de hooks (gap #7)"
echo "    Hard timeout: ${TIMEOUT_HARD}s | Soft SLO: ${TIMEOUT_SOFT}s"
echo ""

# ---------------------------------------------------------------------------
# Test 1 — bounded execution: cada hook completa en <TIMEOUT_HARD segundos
# ---------------------------------------------------------------------------
echo "Test 1: Bounded execution (no hang)"
for hook in "${HOOKS_UNDER_TEST[@]}"; do
    [[ -x "$hook" ]] || { color_warn "$hook no es ejecutable, salteando"; continue; }
    start_ts=$(date +%s)
    # 'timeout' coreutils — si supera el limite, exit 124
    if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_BIN=timeout
    elif command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_BIN=gtimeout
    else
        color_warn "ni 'timeout' ni 'gtimeout' instalado — salteando bounded check"
        break
    fi
    # Payload de ENTREGA, no `</dev/null`. Con stdin vacio el gate sale por el
    # fast path —el JSON no matchea— y el test media una invocacion vacia: el
    # mismo defecto que se arreglo en el Test 3, intacto un test mas arriba. Y es
    # justo este el que tendria que atrapar un cuelgue del lock.
    "$TIMEOUT_BIN" "$TIMEOUT_HARD" bash "$hook" \
        <<< "$PAYLOAD_ENTREGA" >"$TMPDIR/out.txt" 2>&1
    rc=$?
    elapsed=$(( $(date +%s) - start_ts ))
    if [[ "$rc" -eq 124 ]]; then
        color_fail "$hook excedio ${TIMEOUT_HARD}s (HANG)"
    elif [[ "$elapsed" -gt "$TIMEOUT_SOFT" ]]; then
        color_warn "$hook tardo ${elapsed}s (> SLO ${TIMEOUT_SOFT}s) — revisar"
    else
        color_pass "$hook completo en ${elapsed}s (rc=$rc)"
    fi
done
echo ""

# ---------------------------------------------------------------------------
# Test 2 — cleanup tras SIGTERM: ningun .lock / tmp huerfano en hooks/scripts
# ---------------------------------------------------------------------------
echo "Test 2: SIGTERM cleanup (sin lock/tmp huerfano)"
LOCK_PRE=$(find hooks/scripts -name '*.lock' -o -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
for hook in "${HOOKS_UNDER_TEST[@]}"; do
    [[ -x "$hook" ]] || continue
    bash "$hook" </dev/null >"$TMPDIR/out.txt" 2>&1 &
    pid=$!
    sleep 0.3
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
done
LOCK_POST=$(find hooks/scripts -name '*.lock' -o -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LOCK_POST" -gt "$LOCK_PRE" ]]; then
    color_fail "SIGTERM dejo $((LOCK_POST - LOCK_PRE)) archivos huerfanos en hooks/scripts"
else
    color_pass "SIGTERM no dejo huerfanos (locks pre=$LOCK_PRE post=$LOCK_POST)"
fi
echo ""

# ¿Degradar el PATH AFLOJA el veredicto?
#
# La primera version de esta comprobacion exigia que el gate dijera "deny" con el
# PATH degradado, a secas. Estaba mal en las dos direcciones: el veredicto del
# gate depende de si hay commits productivos sin gatear, NO del PATH. Con la rama
# al dia daba FAIL sin que hubiera nada roto, y con commits pendientes daba PASS
# aunque el gate fuera fail-open, porque habia otra razon para denegar. Medido:
# 12 PASS / 1 FAIL, 5 veces de 5, con la rama al dia.
#
# Lo que si es una propiedad del gate, y no del estado del repo: quitarle
# dependencias no puede volverlo MAS permisivo. Se compara contra si mismo.
_degradar_afloja() {
    local hook="$1" normal degradado
    normal=$(printf '%s' "$PAYLOAD_ENTREGA" | bash "$hook" 2>/dev/null | grep -c '"deny"')
    degradado=$(grep -c '"deny"' "$TMPDIR/out.txt" 2>/dev/null)
    [[ "${normal:-0}" -ge 1 && "${degradado:-0}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Test 3 — PATH degradado: cada hook debe fallar claro, no hang
# ---------------------------------------------------------------------------
echo "Test 3: PATH degradado (dependencias faltantes)"
# El `if` de adentro no tenia `else`: sin `timeout` este test entero se saltaba
# en silencio, y el resumen igual decia "1 PASS / 1 WARN" como si hubiera corrido.
# Es el anti-patron que el propio repo condena — un control que desaparece sin
# avisar deja la impresion de estar cubierto. El aviso va UNA vez, no por hook.
if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    color_warn "ni 'timeout' ni 'gtimeout' instalado — Test 3 (PATH degradado) NO se ejecuto"
fi
for hook in "${HOOKS_UNDER_TEST[@]}"; do
    [[ -x "$hook" ]] || continue
    if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_BIN=$(command -v timeout || command -v gtimeout)
        # `/usr/bin:/bin`, y NO solo `/usr/bin`: en macOS `bash` vive en `/bin`,
        # asi que el PATH anterior daba `bash: not found` y las seis lineas
        # pasaban con rc=127 — el hook no arrancaba nunca. Cobertura aparente.
        #
        # Y con stdin vacio tampoco alcanzaba: el fast path de `delivery-gate.sh`
        # mira el JSON de entrada, no matchea, y sale por la puerta de adelante
        # sin tocar una sola dependencia. Hay que darle una entrega de verdad.
        env -i PATH=/usr/bin:/bin HOME="$HOME" CLAUDE_PROJECT_DIR="$PWD" \
            "$TIMEOUT_BIN" "$TIMEOUT_HARD" bash "$hook" \
            <<< '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
            >"$TMPDIR/out.txt" 2>&1
        rc=$?
        if [[ "$rc" -eq 124 ]]; then
            color_fail "$hook hang con PATH degradado (no failsafe)"
        elif [[ "$rc" -eq 127 ]]; then
            color_fail "$hook ni siquiera arranco con PATH degradado (rc=127): el test no prueba nada"
        elif [[ "$hook" = *delivery-gate.sh ]] && _degradar_afloja "$hook"; then
            color_fail "$hook con PATH degradado AFLOJO el veredicto: fail-open"
        else
            color_pass "$hook fallo rapido con PATH degradado (rc=$rc)"
        fi
    fi
done
echo ""

echo "==> Resultado chaos: $PASS PASS / $WARN WARN / $FAIL FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1

# En CI un WARN es un FALLO.
#
# macOS no trae `timeout`/`gtimeout`, asi que en la maquina del dev los tests 1 y
# 3 se saltean y el script sale 0 con dos WARN. Eso esta bien localmente —no se
# le va a pedir a nadie que instale coreutils para commitear—, pero engancharlo a
# CI tal cual daria VERDE ejecutando uno de tres: cobertura aparente, que es la
# forma de falla que este mismo archivo existe para detectar.
#
# En CI (ubuntu) `timeout` esta, asi que un WARN ahi significa que algo se
# degrado de verdad y hay que mirarlo.
if [[ -n "${CI:-}" && "$WARN" -gt 0 ]]; then
    echo "==> En CI un WARN cuenta como fallo: se saltearon comprobaciones." >&2
    exit 1
fi
exit 0
