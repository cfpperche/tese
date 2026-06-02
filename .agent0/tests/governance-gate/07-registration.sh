#!/usr/bin/env bash
# Scenario: the gate is registered on PreToolUse(Bash) in settings.json and the
# command points at the (post-move) .agent0/hooks/ home.
set -euo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SETTINGS="$AGENT0_ROOT/.claude/settings.json"

[ -f "$SETTINGS" ] || { printf 'FAIL: %s not found\n' "$SETTINGS"; exit 1; }
jq -e . "$SETTINGS" >/dev/null 2>&1 || { printf 'FAIL: settings.json invalid JSON\n'; exit 1; }

# A PreToolUse(Bash) hook command references governance-gate.sh under .agent0/hooks/.
if ! jq -e '
  [ .hooks.PreToolUse[]? | select((.matcher // "") | test("Bash")) | .hooks[]?.command ]
  | any(. != null and contains(".agent0/hooks/governance-gate.sh"))
' "$SETTINGS" >/dev/null 2>&1; then
  printf 'FAIL: no PreToolUse(Bash) hook registered for .agent0/hooks/governance-gate.sh\n'
  exit 1
fi

# The old .claude/hooks/ path must no longer be referenced (hard move).
if jq -e '
  [ .hooks.PreToolUse[]? | .hooks[]?.command ]
  | any(. != null and contains(".claude/hooks/governance-gate.sh"))
' "$SETTINGS" >/dev/null 2>&1; then
  printf 'FAIL: stale .claude/hooks/governance-gate.sh reference still in settings.json\n'
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
