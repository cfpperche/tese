#!/usr/bin/env bash
# .agent0/tests/delegation-verify/05-fail-open.sh
# Scenario: fail-open posture. (a) validator emits unparseable output → exit 0,
# no block. (b) no validator resolvable at all → exit 0. A broken verifier must
# NEVER permanently block sub-agent termination.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

TMP="$(mktemp -d -t spec-111-05-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agent0"

PAYLOAD="$(jq -cn --arg c "$TMP" '{agent_id:"agent-111-05",session_id:"s5",agent_type:"gp",cwd:$c,stop_hook_active:false,hook_event_name:"SubagentStop"}')"

# (a) unparseable validator output
cat > "$TMP/broken.sh" <<'V'
#!/usr/bin/env bash
echo 'not json at all'
V
chmod +x "$TMP/broken.sh"
e=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_DELEGATION_VALIDATOR="$TMP/broken.sh" bash "$HOOK" >/dev/null 2>&1 || e=$?
[ "$e" -eq 0 ] || { printf 'FAIL(a): broken validator exit=%d want 0\n' "$e"; exit 1; }

# (b) no validator resolvable (no CLAUDE_DELEGATION_VALIDATOR, no .agent0/validators/run.sh in TMP)
e=0
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 || e=$?
[ "$e" -eq 0 ] || { printf 'FAIL(b): no-validator exit=%d want 0\n' "$e"; exit 1; }

printf 'PASS\n'
