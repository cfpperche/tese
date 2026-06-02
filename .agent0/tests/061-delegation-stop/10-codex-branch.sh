#!/usr/bin/env bash
# .agent0/tests/061-delegation-stop/10-codex-branch.sh
# Scenario: Codex multi-runtime branch (spec 106).
#
# Codex has no CLAUDE_PROJECT_DIR, no transcript sidecar, no edit attribution,
# and no loop-budget counter. Two steps:
#   (start) delegation-start-audit.sh on a Codex SubagentStart payload (which
#           carries NO brief text) appends a subagent-start row with
#           runtime=codex-cli, brief_observable=false, formatted=null.
#   (stop)  the shared delegation-stop.sh pairs the close row to that start row
#           by agent_id → correlation=agent_id-direct, exit=null, edit_count=null,
#           numeric duration_ms.
#
# Runtime is forced to codex-cli by unsetting CLAUDE_PROJECT_DIR; the project
# dir is supplied via AGENT0_PROJECT_DIR (the documented Codex override).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-start-audit.sh"
STOP_HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-stop.sh"

TMP="$(mktemp -d -t spec-061-10-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.agent0"
AUDIT="$TMP/.agent0/delegation-audit.jsonl"

AGENT_ID="codex-agent-0010"
SESSION="sess-061-10"
ATYPE="default"

run_codex() { env -u CLAUDE_PROJECT_DIR AGENT0_PROJECT_DIR="$TMP" bash "$1"; }

# --- SubagentStart: Codex payload (verified 0.134.0 field set; NO brief) ---
START_PAYLOAD="$(jq -cn --arg s "$SESSION" --arg a "$AGENT_ID" --arg t "$ATYPE" --arg c "$TMP" \
  '{session_id:$s,turn_id:"turn-xyz",transcript_path:"/dev/null",cwd:$c,hook_event_name:"SubagentStart",model:"gpt-5.5",permission_mode:"bypassPermissions",agent_id:$a,agent_type:$t}')"

start_exit=0
printf '%s' "$START_PAYLOAD" | run_codex "$START_HOOK" || start_exit=$?
[ "$start_exit" -eq 0 ] || { printf 'FAIL: start hook exit=%d, want 0\n' "$start_exit"; exit 1; }

START_ROW="$(grep '"event":"subagent-start"' "$AUDIT" 2>/dev/null | tail -1 || true)"
[ -n "$START_ROW" ] || { printf 'FAIL: no subagent-start row appended\n'; cat "$AUDIT" 2>/dev/null || true; exit 1; }

assert_start() {
  got="$(printf '%s' "$START_ROW" | jq -r ".$1")"
  [ "$got" = "$2" ] || { printf 'FAIL(start): .%s=%q want %q\n' "$1" "$got" "$2"; exit 1; }
}
assert_start runtime "codex-cli"
assert_start event "subagent-start"
assert_start agent_id "$AGENT_ID"
assert_start brief_observable "false"
printf '%s' "$START_ROW" | jq -e '.formatted == null' >/dev/null || { printf 'FAIL(start): formatted not null\n'; exit 1; }

# Sleep so the close row's duration is a positive integer.
sleep 1

# --- SubagentStop: close row pairs to the start row by agent_id ---
STOP_PAYLOAD="$(jq -cn --arg s "$SESSION" --arg a "$AGENT_ID" --arg t "$ATYPE" --arg c "$TMP" \
  '{session_id:$s,cwd:$c,hook_event_name:"SubagentStop",agent_id:$a,agent_type:$t,last_assistant_message:"codex done",stop_hook_active:false}')"

stop_exit=0
printf '%s' "$STOP_PAYLOAD" | run_codex "$STOP_HOOK" || stop_exit=$?
[ "$stop_exit" -eq 0 ] || { printf 'FAIL: stop hook exit=%d, want 0\n' "$stop_exit"; exit 1; }

STOP_ROW="$(grep '"event":"subagent-stop"' "$AUDIT" | tail -1 || true)"
[ -n "$STOP_ROW" ] || { printf 'FAIL: no subagent-stop row appended\n'; cat "$AUDIT"; exit 1; }

assert_stop() {
  got="$(printf '%s' "$STOP_ROW" | jq -r ".$1")"
  [ "$got" = "$2" ] || { printf 'FAIL(stop): .%s=%q want %q\n' "$1" "$got" "$2"; exit 1; }
}
assert_stop runtime "codex-cli"
assert_stop event "subagent-stop"
assert_stop correlation "agent_id-direct"
printf '%s' "$STOP_ROW" | jq -e '.exit == null' >/dev/null || { printf 'FAIL(stop): exit not null (got %s)\n' "$(printf '%s' "$STOP_ROW" | jq -c '.exit')"; exit 1; }
printf '%s' "$STOP_ROW" | jq -e '.edit_count == null' >/dev/null || { printf 'FAIL(stop): edit_count not null\n'; exit 1; }
printf '%s' "$STOP_ROW" | jq -e '.duration_ms | type == "number"' >/dev/null || { printf 'FAIL(stop): duration_ms not numeric (got %s)\n' "$(printf '%s' "$STOP_ROW" | jq -c '.duration_ms')"; exit 1; }

printf 'PASS: %s\n' "$(basename "$0")"
