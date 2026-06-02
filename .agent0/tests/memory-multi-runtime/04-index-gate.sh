#!/usr/bin/env bash
# Scenario: synthetic Codex apply_patch raw MEMORY.md edit is blocked unless overridden.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/memory-index-gate.sh"
TMPDIR="$(mktemp -d -t memory-mr-04-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/memory"

blocked_patch='*** Begin Patch
*** Update File: .agent0/memory/MEMORY.md
@@
+manual edit
*** End Patch'

payload="$(jq -n \
  --arg cwd "$TMPDIR" \
  --arg command "$blocked_patch" \
  '{hook_event_name:"PreToolUse", tool_name:"apply_patch", cwd:$cwd, session_id:"codex-session", tool_use_id:"tool-block", tool_input:{command:$command}}')"

stderr_capture="$(mktemp -t memory-mr-04-stderr-XXXXXX)"
exit_code=0
printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK" 2>"$stderr_capture" || exit_code=$?
if [ "$exit_code" -ne 2 ]; then
  printf 'FAIL: expected gate exit 2, got %s\n' "$exit_code"
  cat "$stderr_capture"
  exit 1
fi
if ! grep -q 'memory-index-gate: blocked \[raw-edit-without-override\]' "$stderr_capture"; then
  printf 'FAIL: missing block message\n'
  cat "$stderr_capture"
  exit 1
fi

override_patch='*** Begin Patch
*** Update File: .agent0/memory/MEMORY.md
@@
+# OVERRIDE: memory-index-edit: migration cleanup
*** End Patch'

payload="$(jq -n \
  --arg cwd "$TMPDIR" \
  --arg command "$override_patch" \
  '{hook_event_name:"PreToolUse", tool_name:"apply_patch", cwd:$cwd, session_id:"codex-session", tool_use_id:"tool-allow", tool_input:{command:$command}}')"

printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK" 2>"$stderr_capture"
if ! jq -e 'select(.event_type == "manual-edit" and .reason == "migration cleanup" and .actor == "Codex CLI")' "$TMPDIR/.agent0/.memory-events.jsonl" >/dev/null; then
  printf 'FAIL: override did not append manual-edit event\n'
  cat "$TMPDIR/.agent0/.memory-events.jsonl"
  exit 1
fi

echo "PASS: 04-index-gate"
