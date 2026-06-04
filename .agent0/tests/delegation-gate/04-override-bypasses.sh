#!/usr/bin/env bash
# Scenario: a valid `# OVERRIDE:` marker (reason >=10 chars) bypasses the field
# check. Given a fieldless prompt with the marker at line start, When the gate
# fires, Then it exits 0 and the audit row records override=<reason> with
# formatted=false (defensive-override use is distinguishable from a real bypass).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-04-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PROMPT="# OVERRIDE: quick throwaway spike to probe an idea
just explore the codebase"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p}}')"
rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?

[ "$rc" -eq 0 ] || { printf 'FAIL: exit=%d want 0 (override should allow)\n' "$rc"; exit 1; }
ROW="$(tail -1 "$AUDIT" 2>/dev/null || true)"
[ -n "$ROW" ] || { printf 'FAIL: no audit row\n'; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.override')" = "quick throwaway spike to probe an idea" ] \
  || { printf 'FAIL: override reason not logged: %s\n' "$ROW"; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.formatted')" = "false" ] \
  || { printf 'FAIL: formatted should be false on a bypass: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
