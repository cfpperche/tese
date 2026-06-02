#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "03-resume"

TMPDIR="$(mktemp -d -t claude-exec-resume-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_claude "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"
SESSION_ID="123e4567-e89b-12d3-a456-426614174000"

CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" \
FAKE_CLAUDE_STDIN="$STDIN_FILE" \
FAKE_CLAUDE_SESSION="$SESSION_ID" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default \
    --resume "$SESSION_ID" \
    --json \
    --task "Continue prior critique" > "$TMPDIR/summary.txt"

assert_arg_order "$ARGS" "--resume" "$SESSION_ID" "passes resume session id"
assert_contains "$STDIN_FILE" "Continue prior critique" "passes resume task through stdin"
assert_contains "$STATE/runs.jsonl" "$SESSION_ID" "records session id in aggregate log"
assert_contains "$TMPDIR/summary.txt" "last_message=" "reports generated last-message path"
assert_contains "$TMPDIR/summary.txt" "session_id=$SESSION_ID" "reports captured session id"

finish
