#!/usr/bin/env bash
# Scenario 6: Claude-shaped SessionStart/Stop behavior is preserved.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"
STOP_HOOK="$AGENT0_ROOT/.agent0/hooks/session-stop.sh"
TRACK_HOOK="$AGENT0_ROOT/.agent0/hooks/session-track-edits.sh"

TMPDIR="$(mktemp -d -t spec-101-06-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.invalid"
git config user.name "test"
mkdir -p "$TMPDIR/.agent0"
printf 'Claude regression handoff.\n' > "$TMPDIR/.agent0/HANDOFF.md"
printf 'initial\n' > "$TMPDIR/tracked.txt"
git add .agent0/HANDOFF.md tracked.txt
git commit -q -m initial

export CLAUDE_PROJECT_DIR="$TMPDIR"
SESSION_ID="claude-regression-06"
start_payload="$(jq -cn --arg sid "$SESSION_ID" '{
  hook_event_name: "SessionStart",
  source: "startup",
  session_id: $sid
}')"
start_output="$(printf '%s' "$start_payload" | bash "$START_HOOK")"

if ! printf '%s' "$start_output" | jq -e '
  .hookSpecificOutput.hookEventName == "SessionStart"
  and (.hookSpecificOutput.additionalContext | contains("Claude regression handoff."))
  and (.systemMessage | contains("Claude regression handoff."))
' >/dev/null; then
  printf 'FAIL: Claude SessionStart JSON dual-channel output changed\n%s\n' "$start_output"
  exit 1
fi

printf 'edited\n' > "$TMPDIR/tracked.txt"
track_payload="$(jq -cn --arg sid "$SESSION_ID" --arg path "$TMPDIR/tracked.txt" '{
  session_id: $sid,
  tool_input: {file_path: $path}
}')"
printf '%s' "$track_payload" | bash "$TRACK_HOOK"

stop_payload="$(jq -cn --arg sid "$SESSION_ID" '{
  hook_event_name: "Stop",
  session_id: $sid
}')"
stop_output="$(printf '%s' "$stop_payload" | bash "$STOP_HOOK")"

if ! printf '%s' "$stop_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Claude Stop did not preserve dirty-WIP handoff block\n%s\n' "$stop_output"
  exit 1
fi

printf 'PASS\n'
exit 0
