#!/usr/bin/env bash
# .agent0/tests/delegation-verify/04-no-agent-id.sh
# Scenario: SubagentStop payload without agent_id (e.g. a main-thread Stop, or
# a malformed payload). Then delegation-verify.sh exits 0 silently and writes
# NO audit row — agent_id is the delegated-actor gate.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-04-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

cat > "$TMP/validator.sh" <<'V'
#!/usr/bin/env bash
echo '{"ok":false,"command":"should-not-run","exit":1,"stdout":"","stderr":""}'
V
chmod +x "$TMP/validator.sh"

PAYLOAD="$(jq -cn --arg c "$TMP" '{session_id:"s4",cwd:$c,stop_hook_active:false,hook_event_name:"SubagentStop"}')"

hook_exit=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_DELEGATION_VALIDATOR="$TMP/validator.sh" bash "$HOOK" >/dev/null 2>&1 || hook_exit=$?

[ "$hook_exit" -eq 0 ] || { printf 'FAIL: exit=%d want 0\n' "$hook_exit"; exit 1; }
[ ! -f "$AUDIT" ] || [ ! -s "$AUDIT" ] || { printf 'FAIL: audit row written for a no-agent_id stop\n'; cat "$AUDIT"; exit 1; }

printf 'PASS\n'
