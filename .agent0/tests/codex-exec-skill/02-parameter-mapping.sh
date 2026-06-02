#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "02-parameter-mapping"

TMPDIR="$(mktemp -d -t codex-exec-params-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_codex "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"
OUT="$STATE/out/custom.md"

CODEX_EXEC_STATE_DIR="$STATE" \
FAKE_CODEX_ARGS="$ARGS" \
FAKE_CODEX_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --model gpt-5-codex \
    --profile maintainer \
    --sandbox workspace-write \
    --cwd .agent0 \
    --json \
    --output "$OUT" \
    --task "Map parameters"

assert_arg_order "$ARGS" "--model" "gpt-5-codex" "passes model value"
assert_arg_order "$ARGS" "--profile" "maintainer" "passes profile value"
assert_arg_order "$ARGS" "--sandbox" "workspace-write" "passes explicit sandbox"
assert_arg_order "$ARGS" "--cd" "$AGENT0_ROOT/.agent0" "resolves repo-relative cwd under repo"
assert_arg_order "$ARGS" "exec" "--json" "places json after exec"
assert_arg_order "$ARGS" "--output-last-message" "$OUT" "passes explicit output path"
assert_file "$STATE/out/events.jsonl" "captures json events"

set +e
CODEX_EXEC_STATE_DIR="$STATE" PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --unknown --task "bad" > "$TMPDIR/unknown.out" 2> "$TMPDIR/unknown.err"
unknown_status=$?
set -e

if [ "$unknown_status" -ne 0 ]; then
  ok "rejects unknown options"
else
  no "rejects unknown options"
fi
assert_contains "$TMPDIR/unknown.err" "unknown option: --unknown" "unknown option error is explicit"

args_before_output_escape="$(wc -l < "$ARGS")"
set +e
CODEX_EXEC_STATE_DIR="$STATE" PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --output "$TMPDIR/outside.md" \
    --task "bad output" > "$TMPDIR/output-escape.out" 2> "$TMPDIR/output-escape.err"
output_escape_status=$?
set -e

if [ "$output_escape_status" -ne 0 ]; then
  ok "rejects output outside state dir"
else
  no "rejects output outside state dir"
fi
assert_contains "$TMPDIR/output-escape.err" "--output must resolve under state dir" "output escape error is explicit"
args_after_output_escape="$(wc -l < "$ARGS")"
if [ "$args_before_output_escape" = "$args_after_output_escape" ]; then
  ok "output escape blocks before invoking codex"
else
  no "output escape blocks before invoking codex"
fi
assert_no_path "$TMPDIR/outside.md" "output escape does not create outside artifact"

finish
