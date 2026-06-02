#!/usr/bin/env bash
# Scenario 2: Codex-shaped Stop blocks once, then honors stop_hook_active.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"
STOP_HOOK="$AGENT0_ROOT/.agent0/hooks/session-stop.sh"
TRACK_HOOK="$AGENT0_ROOT/.agent0/hooks/session-track-edits.sh"

TMPDIR="$(mktemp -d -t spec-101-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.invalid"
git config user.name "test"
mkdir -p "$TMPDIR/.agent0"
printf 'Initial handoff\n' > "$TMPDIR/.agent0/HANDOFF.md"
printf 'initial\n' > "$TMPDIR/tracked.txt"
git add .agent0/HANDOFF.md tracked.txt
git commit -q -m initial

SESSION_ID="codex-stop-02"
start_payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" '{
  hook_event_name: "SessionStart",
  source: "startup",
  session_id: $sid,
  cwd: $cwd
}')"
printf '%s' "$start_payload" | bash "$START_HOOK" >/dev/null

printf 'edited\n' > "$TMPDIR/tracked.txt"
patch_body=$'*** Begin Patch\n*** Update File: tracked.txt\n@@\n-initial\n+edited\n*** End Patch\n'
track_payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" --arg patch "$patch_body" '{
  tool_name: "apply_patch",
  session_id: $sid,
  cwd: $cwd,
  tool_input: {command: $patch}
}')"
printf '%s' "$track_payload" | bash "$TRACK_HOOK"

stop_payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" '{
  hook_event_name: "Stop",
  session_id: $sid,
  cwd: $cwd,
  stop_hook_active: false
}')"
stop_output="$(printf '%s' "$stop_payload" | bash "$STOP_HOOK")"

if ! printf '%s' "$stop_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop did not block on Codex-attributed dirty WIP\n%s\n' "$stop_output"
  exit 1
fi

if [ ! -f "$TMPDIR/.agent0/.session-state/$SESSION_ID/nagged" ]; then
  printf 'FAIL: Stop did not write nagged marker\n'
  exit 1
fi

continued_payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" '{
  hook_event_name: "Stop",
  session_id: $sid,
  cwd: $cwd,
  stop_hook_active: true
}')"
continued_output="$(printf '%s' "$continued_payload" | bash "$STOP_HOOK")"

if [ -n "$continued_output" ]; then
  printf 'FAIL: Stop emitted output while stop_hook_active=true\n%s\n' "$continued_output"
  exit 1
fi

printf 'PASS\n'
exit 0
