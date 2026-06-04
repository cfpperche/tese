#!/usr/bin/env bash
# Scenario: an `# OVERRIDE:` whose reason is <10 chars does NOT bypass.
# Given a fieldless prompt with `# OVERRIDE: skip`, When the gate fires, Then it
# still exits 2 (block) and notes the too-short reason on stderr.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-05-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"

PROMPT="# OVERRIDE: skip
do the thing"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p}}')"
err="$(mktemp)"; rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>"$err" >/dev/null || rc=$?

[ "$rc" -eq 2 ] || { printf 'FAIL: exit=%d want 2 (short reason must not bypass)\n' "$rc"; cat "$err"; exit 1; }
grep -qi 'shorter than' "$err" || { printf 'FAIL: no too-short note on stderr\n'; cat "$err"; exit 1; }

printf 'PASS\n'
