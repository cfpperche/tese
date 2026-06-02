#!/usr/bin/env bash
# .agent0/tests/delegation-verify/03-exhausted-partial.sh
# Scenario: failing validator AFTER a continuation (stop_hook_active=true).
# Then delegation-verify.sh does NOT block again — exits 0 (accepts closure as
# a partial result), surfaces the partial-result message, and appends a
# subagent-verify row with decision=exhausted. Guards the infinite-loop case.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-03-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

cat > "$TMP/validator.sh" <<'V'
#!/usr/bin/env bash
echo '{"ok":false,"command":"stub-test","exit":1,"stdout":"still failing","stderr":""}'
V
chmod +x "$TMP/validator.sh"

AGENT_ID="agent-111-03"
PAYLOAD="$(jq -cn --arg a "$AGENT_ID" --arg c "$TMP" \
  '{agent_id:$a,session_id:"s3",agent_type:"general-purpose",cwd:$c,stop_hook_active:true,hook_event_name:"SubagentStop"}')"

err="$(mktemp)"; hook_exit=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_DELEGATION_VALIDATOR="$TMP/validator.sh" bash "$HOOK" 2>"$err" || hook_exit=$?

[ "$hook_exit" -eq 0 ] || { printf 'FAIL: exit=%d want 0 (partial-result accept)\n' "$hook_exit"; cat "$err"; exit 1; }
grep -q 'PARTIAL RESULT' "$err" || { printf 'FAIL: partial-result message missing\n'; cat "$err"; exit 1; }
ROW="$(grep '"event":"subagent-verify"' "$AUDIT" | tail -1 || true)"
[ "$(printf '%s' "$ROW" | jq -r '.decision')" = "exhausted" ] || { printf 'FAIL: decision != exhausted: %s\n' "$ROW"; exit 1; }
[ "$(printf '%s' "$ROW" | jq -r '.stop_hook_active')" = "true" ] || { printf 'FAIL: stop_hook_active not recorded true\n'; exit 1; }

printf 'PASS\n'
