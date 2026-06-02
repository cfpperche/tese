#!/usr/bin/env bash
# .agent0/tests/delegation-verify/06-codex-shape.sh
# Scenario: Codex-shape SubagentStop payload — no CLAUDE_PROJECT_DIR, cwd-only,
# keyed by agent_id. Then delegation-verify.sh resolves runtime via the shared
# lib to "codex-cli" and the subagent-verify row carries runtime:"codex-cli".
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-06-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

cat > "$TMP/validator.sh" <<'V'
#!/usr/bin/env bash
echo '{"ok":false,"command":"stub-test","exit":1,"stdout":"x","stderr":""}'
V
chmod +x "$TMP/validator.sh"

AGENT_ID="agent-111-06"
# Codex-shape: cwd present, NO CLAUDE_PROJECT_DIR set in the environment below.
PAYLOAD="$(jq -cn --arg a "$AGENT_ID" --arg c "$TMP" \
  '{agent_id:$a,session_id:"s6",agent_type:"general-purpose",cwd:$c,stop_hook_active:false,hook_event_name:"SubagentStop"}')"

hook_exit=0
printf '%s' "$PAYLOAD" | env -u CLAUDE_PROJECT_DIR CLAUDE_DELEGATION_VALIDATOR="$TMP/validator.sh" bash "$HOOK" >/dev/null 2>&1 || hook_exit=$?

[ "$hook_exit" -eq 2 ] || { printf 'FAIL: exit=%d want 2\n' "$hook_exit"; exit 1; }
ROW="$(grep '"event":"subagent-verify"' "$AUDIT" | tail -1 || true)"
[ -n "$ROW" ] || { printf 'FAIL: no row written\n'; exit 1; }
rt="$(printf '%s' "$ROW" | jq -r '.runtime')"
[ "$rt" = "codex-cli" ] || { printf 'FAIL: runtime=%s want codex-cli\n' "$rt"; exit 1; }

printf 'PASS\n'
