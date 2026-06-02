#!/usr/bin/env bash
set -uo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
MEETING="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
no() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

assert_file() { [ -f "$1" ] && ok "$2" || { no "$2"; echo "      missing file: $1"; }; }

assert_eq() {
  # assert_eq <actual> <expected> <label>
  if [ "$1" = "$2" ]; then ok "$3"; else no "$3"; echo "      expected: [$2]"; echo "      actual:   [$1]"; fi
}

assert_contains() {
  local file=$1 needle=$2 label=$3
  if grep -Fq -- "$needle" "$file"; then ok "$label"; else no "$label"; echo "      missing: $needle"; fi
}

assert_exit() {
  # assert_exit <expected-code> <label> -- <command...>
  local expected=$1 label=$2; shift 2
  [ "$1" = "--" ] && shift
  "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$expected" ]; then ok "$label"; else no "$label"; echo "      expected exit $expected, got $rc"; fi
}

# init a throwaway meeting; echoes the meeting.md path
make_meeting() {
  local dir=$1
  "$MEETING" init --dir "$dir" --slug demo --topic "Should we ship X: a test" \
    --convener claude --roster "claude,codex,human" --rotation "claude,codex"
}

finish() { echo "  -- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
