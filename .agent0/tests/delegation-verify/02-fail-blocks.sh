#!/usr/bin/env bash
# .agent0/tests/delegation-verify/02-fail-blocks.sh
# Scenario: failing validator on the FIRST stop (stop_hook_active=false).
# Then delegation-verify.sh exits 2 (blocks closure → one continuation),
# increments the counter to 1, surfaces the validator's own advisory (lint-),
# and appends a subagent-verify row with decision=blocked.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-02-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

cat > "$TMP/validator.sh" <<'V'
#!/usr/bin/env bash
echo "lint-advisory: example lint note" >&2
echo '{"ok":false,"command":"stub-test","exit":1,"stdout":"FAIL: 1 failed","stderr":"assertion error"}'
V
chmod +x "$TMP/validator.sh"

AGENT_ID="agent-111-02"
PAYLOAD="$(jq -cn --arg a "$AGENT_ID" --arg c "$TMP" \
  '{agent_id:$a,session_id:"s2",agent_type:"general-purpose",cwd:$c,stop_hook_active:false,hook_event_name:"SubagentStop"}')"

err="$(mktemp)"; hook_exit=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_DELEGATION_VALIDATOR="$TMP/validator.sh" bash "$HOOK" 2>"$err" || hook_exit=$?

[ "$hook_exit" -eq 2 ] || { printf 'FAIL: exit=%d want 2\n' "$hook_exit"; cat "$err"; exit 1; }
grep -q 'lint-advisory: example lint note' "$err" || { printf 'FAIL: validator own stderr not surfaced\n'; exit 1; }
grep -q 'delegation-verify: delegated task verification FAILED' "$err" || { printf 'FAIL: block message missing\n'; exit 1; }
ctr="$(cat "$TMP/.agent0/.delegation-state/agents/$AGENT_ID/consecutive_failures" 2>/dev/null || echo MISSING)"
[ "$ctr" = "1" ] || { printf 'FAIL: counter=%s want 1\n' "$ctr"; exit 1; }
ROW="$(grep '"event":"subagent-verify"' "$AUDIT" | tail -1 || true)"
[ "$(printf '%s' "$ROW" | jq -r '.decision')" = "blocked" ] || { printf 'FAIL: decision != blocked: %s\n' "$ROW"; exit 1; }

printf 'PASS\n'
