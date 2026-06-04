#!/usr/bin/env bash
# Scenario: an under-specified Agent dispatch is BLOCKED.
# Given a prompt with none of the 5 handoff fields, When delegation-gate.sh
# fires, Then it exits 2, names the missing fields on stderr, and writes NO
# audit row (the block path does not audit).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-01-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PAYLOAD="$(jq -cn '{tool_name:"Agent",tool_input:{prompt:"go fix the login thing"}}')"
err="$(mktemp)"; rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>"$err" >/dev/null || rc=$?

[ "$rc" -eq 2 ] || { printf 'FAIL: exit=%d want 2\n' "$rc"; cat "$err"; exit 1; }
grep -q 'blocked \[missing-fields\]' "$err" || { printf 'FAIL: no missing-fields banner\n'; cat "$err"; exit 1; }
for f in TASK CONTEXT CONSTRAINTS DELIVERABLE-or-DONE_WHEN; do
  grep -q "$f" "$err" || { printf 'FAIL: missing field %s not listed\n' "$f"; exit 1; }
done
[ ! -s "$AUDIT" ] || { printf 'FAIL: block path wrote an audit row\n'; cat "$AUDIT"; exit 1; }

printf 'PASS\n'
