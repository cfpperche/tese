#!/usr/bin/env bash
# .agent0/tests/061-delegation-stop/05-malformed-payload.sh
# Scenario: failure-safe on a malformed payload.
#
# Two sub-cases, both must exit 0 and append NO row:
#   (a) empty stdin            — the hook bails before parsing
#   (b) payload with no agent_id — the hook bails after parsing (agent_id is
#       the mandatory key; without it the closing sub-agent is unidentifiable)
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-stop.sh"

TMP="$(mktemp -d -t spec-061-05-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"
: >"$AUDIT"

# (a) empty stdin
exit_a=0
printf '' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" || exit_a=$?
[ "$exit_a" -eq 0 ] || { printf 'FAIL(a): empty-stdin exit=%d, want 0\n' "$exit_a"; exit 1; }

# (b) payload missing agent_id
exit_b=0
printf '%s' '{"session_id":"s","agent_type":"Explore","hook_event_name":"SubagentStop"}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" || exit_b=$?
[ "$exit_b" -eq 0 ] || { printf 'FAIL(b): missing-agent_id exit=%d, want 0\n' "$exit_b"; exit 1; }

# Neither sub-case may append a close row.
if grep -q '"event":"subagent-stop"' "$AUDIT" 2>/dev/null; then
  printf 'FAIL: a close row was appended for a malformed payload\n'
  cat "$AUDIT"
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
