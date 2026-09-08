#!/bin/bash
# hotfix-override-test.sh — Test e2e del flujo HOTFIX-OVERRIDE.
#
# Desde ADR-008 el punto de control es la ENTREGA (delivery-gate.sh), no el cierre
# de turno. El override se consume y se loguea ahi, no en mandatory-review.sh.
#
# Verifica:
#   1. REASON corto (<20 chars) → override invalido, no se loguea
#   2. Self-approval (APPROVED_BY == solicitante) → rechazado (two-person rule)
#   3. Override valido → consume el flag, loguea y permite la entrega
#   4. Gate 1 con CRITICAL → sigue bloqueando aun con override activo
#   5. Rotacion del log (>1MB → log.1)
#
# Corre en un sandbox git temporal: el resultado no puede depender del estado del
# working tree del repo.

set -u
STACK_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

SANDBOX=$(mktemp -d)
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# ── Montar el sandbox ────────────────────────────────────────────────────────
mkdir -p "$SANDBOX"/{hooks/scripts/lib,tmp,logs,srv}
cp "$STACK_ROOT"/hooks/scripts/*.sh "$SANDBOX/hooks/scripts/"
cp "$STACK_ROOT"/hooks/scripts/lib/*.sh "$SANDBOX/hooks/scripts/lib/"
cp -r "$STACK_ROOT/hooks/scripts/__smoketest__/fixtures" "$SANDBOX/hooks/scripts/__smoketest__/fixtures" 2>/dev/null \
    || { mkdir -p "$SANDBOX/hooks/scripts/__smoketest__"; cp -r "$STACK_ROOT/hooks/scripts/__smoketest__/fixtures" "$SANDBOX/hooks/scripts/__smoketest__/"; }

# Toolchain del sandbox. Este test es sobre la semantica del HOTFIX-OVERRIDE, no
# sobre linting: sin un toolchain que exista, Gate 1 bloquearia por "no se pudo
# verificar" (auditoria A2) y el test mediria otra cosa.
mkdir -p "$SANDBOX/node_modules/.bin"
for _bin in eslint cds ui5lint; do
    printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/node_modules/.bin/$_bin"
    chmod +x "$SANDBOX/node_modules/.bin/$_bin"
done

cd "$SANDBOX" || exit 1
git init -q .
REQUESTER_EMAIL="requester@ci.local"
APPROVER_EMAIL="cab-oncall@cliente.com"
git config user.email "$REQUESTER_EMAIL"
git config user.name "ci"
echo "seed" > seed.txt && git add seed.txt && git commit -qm init

export CLAUDE_PROJECT_DIR="$SANDBOX"
DG="hooks/scripts/delivery-gate.sh"
QG="hooks/scripts/quality-gate.sh"
TMP_FLAG="tmp/.hotfix-override"
HOTFIX_LOG="logs/hotfix-overrides.log"

# Archivo productivo staged: sin esto el gate de entrega no aplica.
echo "module.exports = {};" > srv/service.js
git add srv/service.js

COMMIT_EVENT='{"tool_name":"Bash","tool_input":{"command":"git commit -m hotfix"}}'
run_gate() { printf '%s' "$COMMIT_EVENT" | bash "$DG" 2>&1; }

PASS=0; FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "         actual: $(printf '%s' "$2" | head -c 220)"; FAIL=$((FAIL+1)); }
assert_has() { printf '%s' "$3" | grep -q "$2" && ok "$1" || bad "$1" "$3"; }

echo "==> Test 1: REASON corto (<20 chars) → override invalido"
echo "REASON: corto" > "$TMP_FLAG"
OUT=$(run_gate)
assert_has "rechazado como invalido" "HOTFIX-OVERRIDE invalido" "$OUT"
grep -q "REASON: corto" "$HOTFIX_LOG" 2>/dev/null \
    && bad "REASON corto no debio loguearse" \
    || ok "no se logueo"
rm -f "$TMP_FLAG"

echo ""
echo "==> Test 2: self-approval → rechazado (two-person rule)"
cat > "$TMP_FLAG" <<EOF
REASON: INC-2026-TEST2 self approval debe ser rechazado por la regla
APPROVED_BY: $REQUESTER_EMAIL
EOF
OUT=$(run_gate)
assert_has "self-approval rechazado" "HOTFIX-OVERRIDE invalido" "$OUT"
rm -f "$TMP_FLAG"

echo ""
echo "==> Test 3: override valido → consume flag, loguea y permite entregar"
cat > "$TMP_FLAG" <<EOF
REASON: INC-2026-TEST3 hotfix e2e aprobado por CAB 2026-08-21
APPROVED_BY: $APPROVER_EMAIL
EOF
OUT=$(run_gate)
assert_has "permite la entrega" '"permissionDecision":"allow"' "$OUT"
assert_has "avisa del override" "HOTFIX-OVERRIDE consumido" "$OUT"
[[ ! -f "$TMP_FLAG" ]] && ok "flag consumido (borrado)" || bad "el flag debio borrarse"
grep -q "INC-2026-TEST3" "$HOTFIX_LOG" 2>/dev/null && ok "entrada en log" || bad "no se logueo"
grep -q "approver=$APPROVER_EMAIL" "$HOTFIX_LOG" 2>/dev/null && ok "log incluye al aprobador" || bad "falta approver en log"

echo ""
echo "==> Test 4: CRITICAL sigue bloqueando aun con override activo"
cat > "$TMP_FLAG" <<EOF
REASON: INC-2026-TEST4 critical no debe poder omitirse nunca jamas
APPROVED_BY: $APPROVER_EMAIL
EOF
export ABAP_SCAN_INCLUDE_SMOKETEST=1
git add -A hooks/scripts/__smoketest__/fixtures 2>/dev/null
OUT=$(bash "$QG" 2>&1); RC=$?
unset ABAP_SCAN_INCLUDE_SMOKETEST
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q "CRITICAL"; then
    ok "Gate 1 bloquea con CRITICAL pese al override"
else
    bad "CRITICAL debio bloquear (rc=$RC)" "$OUT"
fi
rm -f "$TMP_FLAG"

echo ""
echo "==> Test 5: rotacion de log (>1MB → log.1)"
perl -e 'print "X" x 1100000' > "$HOTFIX_LOG" 2>/dev/null \
    || python3 -c 'import sys; sys.stdout.write("X"*1100000)' > "$HOTFIX_LOG"
cat > "$TMP_FLAG" <<EOF
REASON: INC-2026-TEST5 rotacion de log al superar el megabyte
APPROVED_BY: $APPROVER_EMAIL
EOF
run_gate >/dev/null 2>&1
[[ -f "${HOTFIX_LOG}.1" ]] && ok "rotacion creo ${HOTFIX_LOG}.1" \
    || bad "no roto el log ($(wc -c < "$HOTFIX_LOG" 2>/dev/null | tr -d ' ') bytes)"

echo ""
echo "================================"
echo "PASS: $PASS  FAIL: $FAIL"
echo "================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
