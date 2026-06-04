#!/usr/bin/env bash
# Scenario: a complete 5-field handoff is ALLOWED.
# Given a prompt with TASK/CONTEXT/CONSTRAINTS/DELIVERABLE+DONE_WHEN, When the
# gate fires, Then it exits 0 and appends a dispatch row with formatted=true.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-02-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PROMPT="TASK: refactor the parser
CONTEXT: src/parse.ts and its test
CONSTRAINTS: no public API change
DELIVERABLE: edited src/parse.ts
DONE_WHEN: bun test passes"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p,subagent_type:"general-purpose"}}')"
rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?

[ "$rc" -eq 0 ] || { printf 'FAIL: exit=%d want 0\n' "$rc"; exit 1; }
ROW="$(tail -1 "$AUDIT" 2>/dev/null || true)"
[ -n "$ROW" ] || { printf 'FAIL: no audit row appended\n'; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.formatted')" = "true" ] || { printf 'FAIL: formatted!=true: %s\n' "$ROW"; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.event')" = "dispatch" ] || { printf 'FAIL: event!=dispatch\n'; exit 1; }

printf 'PASS\n'
