#!/usr/bin/env bash
# .agent0/tests/governance-gate/lib.sh
# Shared helpers for spec-107 governance-gate scenarios.
#
# HOOK path is overridable via $GOVERNANCE_HOOK so the same suite runs against
# the in-place .claude/hooks/ copy AND the moved .agent0/hooks/ copy. Default
# resolves to whichever exists (.agent0/ preferred — the post-move home).

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

if [ -z "${GOVERNANCE_HOOK:-}" ]; then
  if [ -f "$AGENT0_ROOT/.agent0/hooks/governance-gate.sh" ]; then
    GOVERNANCE_HOOK="$AGENT0_ROOT/.agent0/hooks/governance-gate.sh"
  else
    GOVERNANCE_HOOK="$AGENT0_ROOT/.claude/hooks/governance-gate.sh"
  fi
fi

# run_gate "<command>" -> echoes "BLOCKED" (exit 2) or "allowed" (exit 0/other)
run_gate() {
  local cmd="$1" payload r tmp
  tmp="$(mktemp -d)"
  payload="$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$tmp" bash "$GOVERNANCE_HOOK" >/dev/null 2>&1
  r=$?
  rm -rf "$tmp" 2>/dev/null
  [ "$r" -eq 2 ] && printf 'BLOCKED' || printf 'allowed'
}

# assert_blocked "<command>"
assert_blocked() {
  local got; got="$(run_gate "$1")"
  if [ "$got" != "BLOCKED" ]; then
    printf 'FAIL: expected BLOCKED, got %s for: %s\n' "$got" "$1"
    exit 1
  fi
}

# assert_allowed "<command>"
assert_allowed() {
  local got; got="$(run_gate "$1")"
  if [ "$got" != "allowed" ]; then
    printf 'FAIL: expected allowed, got %s for: %s\n' "$got" "$1"
    exit 1
  fi
}

pass() { printf 'PASS: %s\n' "$(basename "$1")"; }
