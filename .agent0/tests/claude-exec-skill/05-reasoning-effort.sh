#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "05-reasoning-effort"

TMPDIR="$(mktemp -d -t claude-exec-effort-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_claude "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"

# A valid effort maps to claude --effort.
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" \
FAKE_CLAUDE_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default \
    --reasoning-effort high \
    --slug effort-probe \
    --task "Effort mapping"

assert_arg_order "$ARGS" "--effort" "high" "maps --reasoning-effort to claude --effort"
RUN_META=$(ls "$STATE"/*/metadata.json | head -1)
assert_contains "$RUN_META" '"reasoning_effort": "high"' "records reasoning_effort in metadata"

# The --effort alias is accepted and mapped identically.
ARGS2="$TMPDIR/args2.txt"
CLAUDE_EXEC_STATE_DIR="$STATE/alias" \
FAKE_CLAUDE_ARGS="$ARGS2" \
FAKE_CLAUDE_STDIN="$TMPDIR/stdin2.txt" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --effort xhigh --slug alias-probe --task "alias"
assert_arg_order "$ARGS2" "--effort" "xhigh" "accepts --effort alias"

# 'minimal' is a Codex level, NOT a Claude level — must be rejected here,
# before claude is invoked (proves the per-runtime value set is enforced).
args_before="$(wc -l < "$ARGS")"
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" FAKE_CLAUDE_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --reasoning-effort minimal --task "bad" \
    > "$TMPDIR/bad.out" 2> "$TMPDIR/bad.err"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] && ok "rejects invalid reasoning effort" || no "rejects invalid reasoning effort"
assert_contains "$TMPDIR/bad.err" "invalid --reasoning-effort" "invalid effort error is explicit"
args_after="$(wc -l < "$ARGS")"
[ "$args_before" = "$args_after" ] && ok "invalid effort blocks before invoking claude" || no "invalid effort blocks before invoking claude"

finish
