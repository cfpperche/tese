#!/usr/bin/env bash
# Scenario: a valid `# SKILL-DIRECTED: <slug>` marker suppresses the escalation
# advisory (a skill that intentionally dispatches a non-opus sub-agent should not
# be nagged), and is recorded in the audit. Given the same >=2-signal + sonnet
# prompt as 10(b) but with the marker, When the gate fires, Then advisory_kind is
# null, skill_directed is the slug, and it still exits 0.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-11-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PROMPT="# SKILL-DIRECTED: product
TASK: build the frontend and backend auth flow
CONTEXT: ui/ and server/
CONSTRAINTS: none
DONE_WHEN: e2e passes"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p,model:"sonnet"}}')"
rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?

[ "$rc" -eq 0 ] || { printf 'FAIL: exit=%d want 0\n' "$rc"; exit 1; }
ROW="$(tail -1 "$AUDIT")"
[ "$(printf '%s' "$ROW" | jq -r '.skill_directed')" = "product" ] \
  || { printf 'FAIL: skill_directed != product: %s\n' "$ROW"; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.advisory_kind')" = "null" ] \
  || { printf 'FAIL: escalation not suppressed by SKILL-DIRECTED: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
