#!/usr/bin/env bash
# Shared harness for multi-runtime-skills scenarios.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
no()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { printf '%s' "$1" | grep -qF -- "$2" && ok "$3" || { no "$3"; echo "      missing: $2"; }; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || { no "$3"; echo "      expected=$2 actual=$1"; }; }
finish() { echo "  -- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
