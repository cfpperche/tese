#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
echo "04-missing-codex"

TMPDIR="$(mktemp -d -t codex-exec-missing-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

set +e
CODEX_EXEC_STATE_DIR="$TMPDIR/state" PATH="/usr/bin:/bin" \
  bash "$AGENT0_ROOT/.agent0/skills/codex-exec/scripts/codex-exec.sh" \
    --task "This should not run" > "$TMPDIR/out.txt" 2> "$TMPDIR/err.txt"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  ok "missing codex exits non-zero"
else
  no "missing codex exits non-zero"
fi
assert_contains "$TMPDIR/err.txt" "codex CLI is not on PATH" "missing codex error is actionable"
assert_no_path "$TMPDIR/state" "does not create runtime state on dependency failure"

finish
