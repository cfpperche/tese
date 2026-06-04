#!/usr/bin/env bash
# Scenario: the outcome slot accepts EITHER DELIVERABLE or DONE_WHEN.
# Given two handoffs each carrying only one of the outcome fields (plus
# TASK/CONTEXT/CONSTRAINTS), When the gate fires, Then both are ALLOWED (exit 0).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-03-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"

run() { # $1 = prompt; echoes exit code
  local p="$1" rc=0
  local payload; payload="$(jq -cn --arg p "$p" '{tool_name:"Agent",tool_input:{prompt:$p}}')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

DELIV="TASK: x
CONTEXT: y
CONSTRAINTS: z
DELIVERABLE: a file"
DONEW="TASK: x
CONTEXT: y
CONSTRAINTS: z
DONE_WHEN: tests pass"

a="$(run "$DELIV")"; [ "$a" = "0" ] || { printf 'FAIL: DELIVERABLE-only blocked (exit %s)\n' "$a"; exit 1; }
b="$(run "$DONEW")"; [ "$b" = "0" ] || { printf 'FAIL: DONE_WHEN-only blocked (exit %s)\n' "$b"; exit 1; }

printf 'PASS\n'
