#!/usr/bin/env bash
# Scenario 9: missing HANDOFF.md emits advisory and proceeds.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-092-09-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
export CLAUDE_PROJECT_DIR="$TMPDIR"

exit_code=0
output="$(printf '%s' '{"source":"startup","session_id":"test-092-09"}' | bash "$START_HOOK" 2>&1)" || exit_code=$?

if [ "$exit_code" -ne 0 ]; then
  printf 'FAIL: session-start exited non-zero on missing handoff (exit=%d)\n%s\n' "$exit_code" "$output"
  exit 1
fi
if ! printf '%s' "$output" | grep -q '=== handoff-advisory ==='; then
  printf 'FAIL: handoff advisory opening banner missing\n%s\n' "$output"
  exit 1
fi
if ! printf '%s' "$output" | grep -q "'.agent0/HANDOFF.md' missing"; then
  printf 'FAIL: missing handoff advisory body missing\n%s\n' "$output"
  exit 1
fi

printf 'PASS\n'
exit 0
