#!/usr/bin/env bash
# Scenario: the allow-path audit row carries the documented schema.
# Given an allowed dispatch, When the gate audits it, Then the JSONL row has
# schema_version=1, runtime="claude-code", event="dispatch", the subagent_type,
# and a task_summary derived from the TASK: value.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-09-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PROMPT="TASK: summarize the changelog
CONTEXT: CHANGELOG.md
CONSTRAINTS: read-only
DONE_WHEN: a 3-bullet summary is returned"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p,subagent_type:"Explore"},session_id:"sess-9",tool_use_id:"tu-9"}')"
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || true

ROW="$(tail -1 "$AUDIT" 2>/dev/null || true)"
[ -n "$ROW" ] || { printf 'FAIL: no audit row\n'; exit 1; }
chk() { local got; got="$(printf '%s' "$ROW" | jq -r "$1")"; [ "$got" = "$2" ] || { printf 'FAIL: %s = %s want %s\n' "$1" "$got" "$2"; exit 1; }; }
chk '.schema_version' '1'
chk '.runtime' 'claude-code'
chk '.event' 'dispatch'
chk '.subagent_type' 'Explore'
chk '.session_id' 'sess-9'
printf '%s' "$ROW" | jq -e '.task_summary | test("summarize the changelog")' >/dev/null \
  || { printf 'FAIL: task_summary not derived from TASK: value: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
