#!/usr/bin/env bash
# Scenario: malformed PreToolUse JSON fails CLOSED (exit 2).
# Given non-empty input that is not valid JSON, When the gate tries to parse it,
# Then it refuses (exit 2) rather than silently allowing — a parse failure must
# never become an open door.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-08-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"

err="$(mktemp)"; rc=0
printf '%s' '{not valid json' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>"$err" >/dev/null || rc=$?

[ "$rc" -eq 2 ] || { printf 'FAIL: exit=%d want 2 (bad JSON must fail closed)\n' "$rc"; cat "$err"; exit 1; }

printf 'PASS\n'
