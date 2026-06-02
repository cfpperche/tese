#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "04-missing-dependency"

TMPDIR="$(mktemp -d -t claude-exec-missing-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

HELPER="$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh"

# Case A: claude absent from PATH (jq present via /usr/bin).
set +e
CLAUDE_EXEC_STATE_DIR="$TMPDIR/stateA" PATH="/usr/bin:/bin" \
  bash "$HELPER" --permission-mode default --task "This should not run" \
    > "$TMPDIR/a.out" 2> "$TMPDIR/a.err"
statusA=$?
set -e
[ "$statusA" -ne 0 ] && ok "missing claude exits non-zero" || no "missing claude exits non-zero"
assert_contains "$TMPDIR/a.err" "claude CLI is not on PATH" "missing claude error is actionable"
assert_no_path "$TMPDIR/stateA" "no runtime state on missing-claude failure"

# Case B: claude present (fake), jq deliberately absent from PATH.
BINB="$TMPDIR/binB"
link_utils "$BINB" bash env cat sed tr grep date realpath dirname mkdir head cut
make_fake_claude "$BINB"   # adds claude, not jq

set +e
CLAUDE_EXEC_STATE_DIR="$TMPDIR/stateB" \
FAKE_CLAUDE_ARGS="$TMPDIR/argsB.txt" FAKE_CLAUDE_STDIN="$TMPDIR/stdinB.txt" \
PATH="$BINB" \
  bash "$HELPER" --permission-mode default --task "This should not run" \
    > "$TMPDIR/b.out" 2> "$TMPDIR/b.err"
statusB=$?
set -e
[ "$statusB" -ne 0 ] && ok "missing jq exits non-zero" || no "missing jq exits non-zero"
assert_contains "$TMPDIR/b.err" "jq is required" "missing jq error is actionable"
assert_no_path "$TMPDIR/argsB.txt" "claude is never invoked when jq is missing"
assert_no_path "$TMPDIR/stateB" "no runtime state on missing-jq failure"

finish
