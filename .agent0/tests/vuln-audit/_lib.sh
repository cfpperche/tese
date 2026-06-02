#!/usr/bin/env bash
# .agent0/tests/vuln-audit/_lib.sh
# Shared harness for vuln-audit scenarios.
#
# Provides a FAKE osv-scanner stub on a temp PATH so scenarios are deterministic
# and offline (mirrors .agent0/tests/secrets-scan/ canned-binary pattern).
#
# The tool resolves its engine via $VULN_AUDIT_ENGINE; we set it to "fake-osv".
# The stub emits $FAKE_OSV_JSON (a file path) to stdout and exits $FAKE_OSV_EXIT.

set -uo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/vuln-audit.sh"

WORK="$(mktemp -d -t vuln-audit-test-XXXXXX)"
BIN="$WORK/bin"
mkdir -p "$BIN"
trap 'rm -rf "$WORK"' EXIT

# Write the fake osv-scanner stub.
cat > "$BIN/fake-osv" <<'STUB'
#!/usr/bin/env bash
# fake osv-scanner: ignore args, emit $FAKE_OSV_JSON, exit $FAKE_OSV_EXIT.
if [ -n "${FAKE_OSV_JSON:-}" ] && [ -f "${FAKE_OSV_JSON}" ]; then
  cat "${FAKE_OSV_JSON}"
fi
exit "${FAKE_OSV_EXIT:-0}"
STUB
chmod +x "$BIN/fake-osv"

export PATH="$BIN:$PATH"
export VULN_AUDIT_ENGINE="fake-osv"

PASS=0
FAIL=0

# assert_contains <haystack> <needle> <msg>
assert_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS+1)); echo "  ✓ $3"
  else
    FAIL=$((FAIL+1)); echo "  ✗ $3"; echo "      expected to contain: $2"; echo "      in: $1" | head -c 500; echo
  fi
}

# assert_not_contains <haystack> <needle> <msg>
assert_not_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then
    FAIL=$((FAIL+1)); echo "  ✗ $3"; echo "      expected NOT to contain: $2"
  else
    PASS=$((PASS+1)); echo "  ✓ $3"
  fi
}

# assert_eq <actual> <expected> <msg>
assert_eq() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS+1)); echo "  ✓ $3"
  else
    FAIL=$((FAIL+1)); echo "  ✗ $3"; echo "      expected: $2"; echo "      actual:   $1"
  fi
}

finish() {
  echo "  -- $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}

# write a fixture file, echo its path
fixture() { local f="$WORK/fixture-$$-$RANDOM.json"; cat > "$f"; echo "$f"; }
