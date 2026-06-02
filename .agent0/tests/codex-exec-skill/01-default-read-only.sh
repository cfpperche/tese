#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "01-default-read-only"

TMPDIR="$(mktemp -d -t codex-exec-default-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_codex "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"
OUT="$STATE/out/last-message.md"

CODEX_EXEC_STATE_DIR="$STATE" \
FAKE_CODEX_ARGS="$ARGS" \
FAKE_CODEX_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --task "Inspect only" \
    --output "$OUT" > "$TMPDIR/summary.txt"

assert_contains "$ARGS" "<--sandbox>" "passes sandbox flag"
assert_arg_order "$ARGS" "--sandbox" "read-only" "defaults to read-only sandbox"
assert_contains "$ARGS" "<exec>" "runs codex exec"
assert_contains "$ARGS" "<->" "uses stdin prompt marker"
assert_file "$OUT" "captures last message"
assert_contains "$STDIN_FILE" "Inspect only" "passes task through stdin"
assert_file "$STATE/out/metadata.json" "writes metadata beside explicit output"
assert_file "$STATE/runs.jsonl" "appends aggregate runs log"
assert_contains "$TMPDIR/summary.txt" "exit_code=0" "reports exit code"

finish
