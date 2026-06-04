#!/usr/bin/env bash
# Scenario: an `# OVERRIDE:` token that is NOT at the start of a line (prose that
# documents the marker) must NOT bypass. Given a fieldless prompt where the
# marker appears mid-sentence, When the gate fires, Then it still exits 2 — the
# start-of-line anchor prevents accidental/embedded bypass.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-06-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"

PROMPT="remember that the # OVERRIDE: marker must start a line to count
now go and refactor things"
PAYLOAD="$(jq -cn --arg p "$PROMPT" '{tool_name:"Agent",tool_input:{prompt:$p}}')"
rc=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?

[ "$rc" -eq 2 ] || { printf 'FAIL: exit=%d want 2 (mid-prose marker must not bypass)\n' "$rc"; exit 1; }

printf 'PASS\n'
