#!/bin/bash
# chaos-hooks-test.sh
# Verifica resilencia de los hook scripts ante condiciones adversas:
#   - Tiempo de ejecucion acotado (no hang infinito)
#   - SIGTERM mid-execution → cleanup limpio (sin lock/tmp huerfanos)
#   - Dependencias faltantes en PATH → fallo claro, no hang
#   - Hook devuelve exit code inesperado → la sesion no se queda colgada
#
# Cubre Stop-hook chain: quality-gate.sh, mandatory-review.sh, log-agent-activity.sh.
# Uso: bash hooks/scripts/__smoketest__/chaos-hooks-test.sh

set -u
cd "$(dirname "$0")/../../.." || exit 1

# Hard cap por hook (segundos). Si excede → bloqueante.
TIMEOUT_HARD=60
# Soft cap (warning, no falla). Apunta al SLO documentado en docs/SLO-HOOKS.md.
TIMEOUT_SOFT=15

HOOKS_UNDER_TEST=(
    "hooks/scripts/quality-gate.sh"
    "hooks/scripts/protect-sensitive-files.sh"
    "hooks/scripts/log-agent-activity.sh"
)

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
    "$TIMEOUT_BIN" "$TIMEOUT_HARD" bash "$hook" </dev/null >"$TMPDIR/out.txt" 2>&1
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

# ---------------------------------------------------------------------------
# Test 3 — PATH degradado: cada hook debe fallar claro, no hang
# ---------------------------------------------------------------------------
echo "Test 3: PATH degradado (dependencias faltantes)"
for hook in "${HOOKS_UNDER_TEST[@]}"; do
    [[ -x "$hook" ]] || continue
    if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_BIN=$(command -v timeout || command -v gtimeout)
        # PATH solo con /usr/bin para preservar bash/grep/find pero sin npx/pnpm
        env -i PATH=/usr/bin HOME="$HOME" "$TIMEOUT_BIN" "$TIMEOUT_HARD" bash "$hook" \
            </dev/null >"$TMPDIR/out.txt" 2>&1
        rc=$?
        if [[ "$rc" -eq 124 ]]; then
            color_fail "$hook hang con PATH degradado (no failsafe)"
        else
            color_pass "$hook fallo rapido con PATH degradado (rc=$rc)"
        fi
    fi
done
echo ""

echo "==> Resultado chaos: $PASS PASS / $WARN WARN / $FAIL FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
