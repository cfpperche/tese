#!/usr/bin/env bash
# Scenario: a dispatch with an empty prompt is a no-op (exit 0, no audit).
# The gate only governs prompts with content; an empty/absent prompt is not a
# 5-field violation — it exits 0 and writes nothing.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-07-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

PAYLOAD="$(jq -cn '{tool_name:"Agent",tool_input:{prompt:""}}')"
rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?

[ "$rc" -eq 0 ] || { printf 'FAIL: exit=%d want 0 (empty prompt is a no-op)\n' "$rc"; exit 1; }
[ ! -s "$AUDIT" ] || { printf 'FAIL: empty-prompt no-op wrote an audit row\n'; cat "$AUDIT"; exit 1; }

printf 'PASS\n'
