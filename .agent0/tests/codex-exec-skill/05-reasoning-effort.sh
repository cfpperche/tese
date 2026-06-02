#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "05-reasoning-effort"

TMPDIR="$(mktemp -d -t codex-exec-effort-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_codex "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"

# A valid effort maps to a `-c model_reasoning_effort=<lvl>` override placed
# before the `exec` subcommand (it is a top-level Codex config flag).
CODEX_EXEC_STATE_DIR="$STATE" \
FAKE_CODEX_ARGS="$ARGS" \
FAKE_CODEX_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --reasoning-effort xhigh \
    --slug effort-probe \
    --task "Effort mapping"

assert_contains "$ARGS" "<-c>" "passes -c config override"
assert_contains "$ARGS" "<model_reasoning_effort=xhigh>" "maps --reasoning-effort to model_reasoning_effort"
assert_arg_order "$ARGS" "model_reasoning_effort=xhigh" "exec" "config override precedes exec subcommand"

RUN_META=$(ls "$STATE"/*/metadata.json | head -1)
assert_contains "$RUN_META" '"reasoning_effort": "xhigh"' "records reasoning_effort in metadata"

# An invalid effort is rejected before Codex is ever invoked.
args_before="$(wc -l < "$ARGS")"
set +e
CODEX_EXEC_STATE_DIR="$STATE" \
FAKE_CODEX_ARGS="$ARGS" FAKE_CODEX_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --reasoning-effort bogus --task "bad" \
    > "$TMPDIR/bad.out" 2> "$TMPDIR/bad.err"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] && ok "rejects invalid reasoning effort" || no "rejects invalid reasoning effort"
assert_contains "$TMPDIR/bad.err" "invalid --reasoning-effort" "invalid effort error is explicit"
args_after="$(wc -l < "$ARGS")"
[ "$args_before" = "$args_after" ] && ok "invalid effort blocks before invoking codex" || no "invalid effort blocks before invoking codex"

finish
