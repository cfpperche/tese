#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "03-resume"

TMPDIR="$(mktemp -d -t codex-exec-resume-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_codex "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"
SESSION_ID="123e4567-e89b-12d3-a456-426614174000"

CODEX_EXEC_STATE_DIR="$STATE" \
FAKE_CODEX_ARGS="$ARGS" \
FAKE_CODEX_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --resume "$SESSION_ID" \
    --task "Continue prior critique" > "$TMPDIR/summary.txt"

assert_arg_order "$ARGS" "exec" "resume" "uses exec resume subcommand"
assert_arg_order "$ARGS" "resume" "--output-last-message" "places resume options after resume"
assert_arg_order "$ARGS" "$SESSION_ID" "-" "passes stdin marker after session id"
assert_contains "$STDIN_FILE" "Continue prior critique" "passes resume task through stdin"
assert_contains "$STATE/runs.jsonl" "$SESSION_ID" "records resume id in aggregate log"
assert_contains "$TMPDIR/summary.txt" "last_message=" "reports generated last-message path"

finish
