#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "01-required-permission-mode"

TMPDIR="$(mktemp -d -t claude-exec-reqmode-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_claude "$TMPDIR/bin"
STATE="$TMPDIR/state"

# No --permission-mode → fail-closed before invoking Claude.
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$TMPDIR/args.txt" \
FAKE_CLAUDE_STDIN="$TMPDIR/stdin.txt" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --task "Should not run" > "$TMPDIR/out.txt" 2> "$TMPDIR/err.txt"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  ok "missing --permission-mode exits non-zero"
else
  no "missing --permission-mode exits non-zero"
fi
assert_contains "$TMPDIR/err.txt" "--permission-mode is required" "fail-closed error is explicit"
assert_no_path "$TMPDIR/args.txt" "claude is never invoked without a permission mode"
assert_no_path "$STATE" "no runtime state created on fail-closed refusal"

# An invalid permission mode is also refused.
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$TMPDIR/args2.txt" \
FAKE_CLAUDE_STDIN="$TMPDIR/stdin2.txt" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode bogus --task "Should not run" > /dev/null 2> "$TMPDIR/err2.txt"
status2=$?
set -e

if [ "$status2" -ne 0 ]; then
  ok "invalid --permission-mode exits non-zero"
else
  no "invalid --permission-mode exits non-zero"
fi
assert_contains "$TMPDIR/err2.txt" "invalid --permission-mode" "invalid mode error is explicit"

# Floor gate: a write-capable mode without --allow-writes is refused fail-closed.
for wmode in acceptEdits bypassPermissions dontAsk auto; do
  set +e
  CLAUDE_EXEC_STATE_DIR="$TMPDIR/state-$wmode" \
  FAKE_CLAUDE_ARGS="$TMPDIR/args-$wmode.txt" \
  FAKE_CLAUDE_STDIN="$TMPDIR/stdin-$wmode.txt" \
  PATH="$TMPDIR/bin:$PATH" \
    bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
      --permission-mode "$wmode" --task "Should not run" > /dev/null 2> "$TMPDIR/err-$wmode.txt"
  wstatus=$?
  set -e
  [ "$wstatus" -ne 0 ] && ok "write-capable '$wmode' refused without --allow-writes" || no "write-capable '$wmode' refused without --allow-writes"
  assert_no_path "$TMPDIR/args-$wmode.txt" "claude not invoked for '$wmode' without --allow-writes"
done
assert_contains "$TMPDIR/err-auto.txt" "is write-capable; pass --allow-writes" "floor gate error is explicit"

# With --allow-writes, a write-capable mode runs.
CLAUDE_EXEC_STATE_DIR="$TMPDIR/state-write" \
FAKE_CLAUDE_ARGS="$TMPDIR/args-write.txt" \
FAKE_CLAUDE_STDIN="$TMPDIR/stdin-write.txt" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode acceptEdits --allow-writes --task "Edit something" > "$TMPDIR/write.out"
assert_contains "$TMPDIR/args-write.txt" "<acceptEdits>" "write-capable mode runs with --allow-writes"
RUN_W="$(ls -d "$TMPDIR"/state-write/*/ 2>/dev/null | head -1)"
assert_contains "$RUN_W/metadata.json" '"allow_writes": true' "records allow_writes in metadata"

# The read-only floor (default) runs without --allow-writes.
CLAUDE_EXEC_STATE_DIR="$TMPDIR/state-floor" \
FAKE_CLAUDE_ARGS="$TMPDIR/args-floor.txt" \
FAKE_CLAUDE_STDIN="$TMPDIR/stdin-floor.txt" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --task "Review" > /dev/null
assert_contains "$TMPDIR/args-floor.txt" "<default>" "read-only floor (default) runs without --allow-writes"

finish
