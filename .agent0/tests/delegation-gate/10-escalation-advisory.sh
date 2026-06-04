#!/usr/bin/env bash
# Scenario: the allow-path advisory fires per the documented branches.
#   (a) model NOT specified + >=1 signal           -> advisory_kind="model-discipline"
#   (b) model="sonnet" + >=2 signals (cross-domain + security) -> advisory_kind="escalation"
# Both are advisory only (exit 0); the audit records the kind.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"
TMP="$(mktemp -d -t dg-10-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

# (a) model unspecified + a single security signal ("auth")
PROMPT_A="TASK: wire auth
CONTEXT: src/auth.ts
CONSTRAINTS: none
DONE_WHEN: login works"
P_A="$(jq -cn --arg p "$PROMPT_A" '{tool_name:"Agent",tool_input:{prompt:$p}}')"
printf '%s' "$P_A" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || true
ROW="$(tail -1 "$AUDIT")"
[ "$(printf '%s' "$ROW" | jq -r '.advisory_kind')" = "model-discipline" ] \
  || { printf 'FAIL(a): advisory_kind != model-discipline: %s\n' "$ROW"; exit 1; }

# (b) model=sonnet + cross-domain (frontend+backend) + security (auth) => score>=2
PROMPT_B="TASK: build the frontend and backend auth flow
CONTEXT: ui/ and server/
CONSTRAINTS: none
DONE_WHEN: e2e passes"
P_B="$(jq -cn --arg p "$PROMPT_B" '{tool_name:"Agent",tool_input:{prompt:$p,model:"sonnet"}}')"
printf '%s' "$P_B" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || true
ROW="$(tail -1 "$AUDIT")"
[ "$(printf '%s' "$ROW" | jq -r '.advisory_kind')" = "escalation" ] \
  || { printf 'FAIL(b): advisory_kind != escalation: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
