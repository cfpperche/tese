#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "02-parameter-mapping"

TMPDIR="$(mktemp -d -t claude-exec-params-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_fake_claude "$TMPDIR/bin"
ARGS="$TMPDIR/args.txt"
STDIN_FILE="$TMPDIR/stdin.txt"
STATE="$TMPDIR/state"
OUT="$STATE/out/custom.md"

CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" \
FAKE_CLAUDE_STDIN="$STDIN_FILE" \
FAKE_CLAUDE_SESSION="sess-abc-123" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default \
    --allowedTools "Read Grep Glob" \
    --disallowedTools "Bash" \
    --model claude-opus-4-8 \
    --add-dir .agent0 \
    --json \
    --output "$OUT" \
    --task "Map parameters"

assert_arg_order "$ARGS" "-p" "--permission-mode" "runs in print mode"
assert_arg_order "$ARGS" "--permission-mode" "default" "passes permission mode verbatim (pass-through)"
assert_arg_order "$ARGS" "--output-format" "stream-json" "uses stream-json under --json"
assert_contains "$ARGS" "<--verbose>" "adds --verbose for stream-json"
assert_arg_order "$ARGS" "--model" "claude-opus-4-8" "passes model value"
assert_arg_order "$ARGS" "--allowedTools" "Read Grep Glob" "passes allowlist as one arg"
assert_arg_order "$ARGS" "--disallowedTools" "Bash" "passes disallowlist"
assert_arg_order "$ARGS" "--add-dir" "$AGENT0_ROOT/.agent0" "resolves repo-relative add-dir under repo"
assert_contains "$STDIN_FILE" "Map parameters" "passes prompt through stdin, not positional"
assert_file "$STATE/out/events.jsonl" "captures json events"
assert_contains "$OUT" "fake claude review" "extracts last message via jq"
assert_contains "$STATE/out/metadata.json" "sess-abc-123" "records session_id in metadata"

# Unknown flag rejected.
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" FAKE_CLAUDE_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --frobnicate --task "bad" \
    > "$TMPDIR/unknown.out" 2> "$TMPDIR/unknown.err"
unknown_status=$?
set -e
[ "$unknown_status" -ne 0 ] && ok "rejects unknown options" || no "rejects unknown options"
assert_contains "$TMPDIR/unknown.err" "unknown option: --frobnicate" "unknown option error is explicit"

# --output outside the state dir is refused before invoking claude.
args_before="$(wc -l < "$ARGS")"
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" FAKE_CLAUDE_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --output "$TMPDIR/outside.md" --task "bad output" \
    > "$TMPDIR/escape.out" 2> "$TMPDIR/escape.err"
escape_status=$?
set -e
[ "$escape_status" -ne 0 ] && ok "rejects output outside state dir" || no "rejects output outside state dir"
assert_contains "$TMPDIR/escape.err" "--output must resolve under state dir" "output escape error is explicit"
args_after="$(wc -l < "$ARGS")"
[ "$args_before" = "$args_after" ] && ok "output escape blocks before invoking claude" || no "output escape blocks before invoking claude"
assert_no_path "$TMPDIR/outside.md" "output escape does not create outside artifact"

# --add-dir outside the repo root is refused.
set +e
CLAUDE_EXEC_STATE_DIR="$STATE" \
FAKE_CLAUDE_ARGS="$ARGS" FAKE_CLAUDE_STDIN="$STDIN_FILE" \
PATH="$TMPDIR/bin:$PATH" \
  bash "$AGENT0_ROOT/.agent0/skills/claude-exec/scripts/claude-exec.sh" \
    --permission-mode default --add-dir /tmp --task "bad dir" \
    > "$TMPDIR/adddir.out" 2> "$TMPDIR/adddir.err"
adddir_status=$?
set -e
[ "$adddir_status" -ne 0 ] && ok "rejects add-dir outside repo root" || no "rejects add-dir outside repo root"
assert_contains "$TMPDIR/adddir.err" "--add-dir must resolve under repo root" "add-dir escape error is explicit"

finish
