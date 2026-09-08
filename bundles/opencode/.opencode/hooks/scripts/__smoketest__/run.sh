#!/bin/bash
# run.sh
# Smoke test del Gate 1 (quality-gate.sh) usando fixtures intencionalmente sucios.
# Verifica que abap-smell-scan + clean-core-scan detectan y bloquean.
# Uso: bash hooks/scripts/__smoketest__/run.sh

set -u
cd "$(dirname "$0")/../../.." || exit 1

FIXTURE="hooks/scripts/__smoketest__/fixtures/zcl_bad_example.clas.abap"
[ -f "$FIXTURE" ] || { echo "FIXTURE NOT FOUND: $FIXTURE"; exit 2; }

echo "==> Smoke test Gate 1 (fixtures bajo __smoketest__/)"
echo ""

export ABAP_SCAN_INCLUDE_SMOKETEST=1

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

run_check() {
    local name="$1"; local script="$2"; local expected_exit="$3"
    set +e
    bash "$script" > "$TMPDIR/out.txt" 2>&1
    local rc=$?
    set -e
    if [ "$rc" -eq "$expected_exit" ]; then
        echo "  PASS  $name (exit=$rc)"
        PASS=$((PASS+1))
    else
        echo "  FAIL  $name (exit=$rc, esperado=$expected_exit)"
        cat "$TMPDIR/out.txt"
        FAIL=$((FAIL+1))
    fi
}

run_check "abap-smell-scan bloquea con fixture sucio" "hooks/scripts/abap-smell-scan.sh" 1
run_check "clean-core-scan bloquea con fixture sucio" "hooks/scripts/clean-core-scan.sh" 1

echo ""
echo "==> Resultado: $PASS PASS / $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
