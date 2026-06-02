#!/usr/bin/env bash
# .agent0/tests/delegation-verify/01-pass.sh
# Scenario: delegated sub-agent closes with a PASSING validator.
# Given a SubagentStop payload with agent_id + a validator that returns ok=true
# with a warnings[] entry, When delegation-verify.sh fires, Then it exits 0,
# resets the consecutive_failures counter to 0, surfaces a `tdd-advisory:` line,
# and appends a subagent-verify row with decision=pass.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-01-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

cat > "$TMP/validator.sh" <<'V'
#!/usr/bin/env bash
echo '{"ok":true,"command":"stub-pass","exit":0,"stdout":"","stderr":"","warnings":[{"message":"prod changed without test"}]}'
V
chmod +x "$TMP/validator.sh"

AGENT_ID="agent-111-01"
PAYLOAD="$(jq -cn --arg a "$AGENT_ID" --arg c "$TMP" \
  '{agent_id:$a,session_id:"s1",agent_type:"general-purpose",cwd:$c,stop_hook_active:false,hook_event_name:"SubagentStop"}')"

err="$(mktemp)"; hook_exit=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_DELEGATION_VALIDATOR="$TMP/validator.sh" bash "$HOOK" 2>"$err" || hook_exit=$?

[ "$hook_exit" -eq 0 ] || { printf 'FAIL: exit=%d want 0\n' "$hook_exit"; exit 1; }
grep -q 'tdd-advisory: prod changed without test' "$err" || { printf 'FAIL: tdd-advisory not surfaced\n'; cat "$err"; exit 1; }
ctr="$(cat "$TMP/.agent0/.delegation-state/agents/$AGENT_ID/consecutive_failures" 2>/dev/null || echo MISSING)"
[ "$ctr" = "0" ] || { printf 'FAIL: counter=%s want 0\n' "$ctr"; exit 1; }
ROW="$(grep '"event":"subagent-verify"' "$AUDIT" | tail -1 || true)"
[ -n "$ROW" ] || { printf 'FAIL: no subagent-verify row\n'; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.decision')" = "pass" ] || { printf 'FAIL: decision != pass: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
