#!/usr/bin/env bash
# PostToolUse edit tracker that appends each Claude Edit/Write/MultiEdit path
# and Codex apply_patch path to
# `.agent0/.session-state/<session_id>/edited-files.txt`. The Stop hook reads
# this as the primary signal for "did THIS session edit anything?", replacing
# the worktree-delta-compare on the primary path (the porcelain compare stays
# live as fallback for legacy sessions; Bash-driven edits in tracker-enabled
# sessions become a documented silent miss).
#
# Escape hatch: `CLAUDE_SKIP_SESSION_HOOKS=1` short-circuits like the rest of
# the session-state machinery. Fails OPEN on every error path — a broken
# tracker must never block a tool call.
#
# Measured latency (2026-05-16, Linux/WSL2): ~30-50ms per invocation; bash
# startup + jq dominate. Acceptable — the multi-second validator suite now runs
# once at SubagentStop (delegation-verify.sh), not per-edit (spec 111).

set -euo pipefail

[[ "${CLAUDE_SKIP_SESSION_HOOKS:-0}" == "1" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
SESSION_STATE_ROOT="$PROJECT_DIR/.agent0/.session-state"

SESSION_ID_RAW="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -n "$SESSION_ID_RAW" && "$SESSION_ID_RAW" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  SESSION_ID="$SESSION_ID_RAW"
else
  SESSION_ID="unknown"
fi

EDITED_PATHS="$(memory_extract_paths "$INPUT" "$PROJECT_DIR" 2>/dev/null || true)"
[[ -n "$EDITED_PATHS" ]] || exit 0

STATE_DIR="$SESSION_STATE_ROOT/$SESSION_ID"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
TRACK_FILE="$STATE_DIR/edited-files.txt"

# Dedup-and-append under flock. The lock guards against parallel sub-agent
# tool calls in the same session writing interleaved lines.
(
  flock 9
  while IFS= read -r norm_path; do
    [[ -n "$norm_path" ]] || continue
    if [[ ! -f "$TRACK_FILE" ]] || ! grep -Fxq -- "$norm_path" "$TRACK_FILE" 2>/dev/null; then
      printf '%s\n' "$norm_path" >>"$TRACK_FILE"
    fi
  done <<<"$EDITED_PATHS"
) 9>"$TRACK_FILE.lock" 2>/dev/null || true

exit 0
