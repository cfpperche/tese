#!/usr/bin/env bash
# Stop hook: block once per session if the repo has uncommitted changes but
# .agent0/HANDOFF.md was not updated during this session.
#
# State is isolated per-session_id at
# `<.session-state>/<session_id>/{started-at,nagged}`. Parallel sessions
# never reset each other's markers.
#
# Escape hatch: set CLAUDE_SKIP_SESSION_HOOKS=1 to disable.

set -euo pipefail

[[ "${CLAUDE_SKIP_SESSION_HOOKS:-0}" == "1" ]] && exit 0

# Parse session_id from stdin payload — same sanitization shape as
# session-start.sh.
INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
SESSION_STATE_ROOT="$PROJECT_DIR/.agent0/.session-state"
SESSION_FILE="$PROJECT_DIR/.agent0/HANDOFF.md"

SESSION_ID_RAW=""
STOP_HOOK_ACTIVE="false"
if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
  SESSION_ID_RAW="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r 'if .stop_hook_active == true then "true" else "false" end' 2>/dev/null || echo false)"
fi
if [[ -n "$SESSION_ID_RAW" && "$SESSION_ID_RAW" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  SESSION_ID="$SESSION_ID_RAW"
else
  SESSION_ID="unknown"
fi

STATE_DIR="$SESSION_STATE_ROOT/$SESSION_ID"
STARTED_AT="$STATE_DIR/started-at"
NAGGED="$STATE_DIR/nagged"

# No session-start marker → nothing to enforce.
[[ -f "$STARTED_AT" ]] || exit 0

# Codex Stop sets stop_hook_active=true when this turn has already been
# continued by a Stop hook. Treat it like the local nagged marker to avoid
# recursive continuation prompts.
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

# Already nagged this session → don't loop.
if [[ -f "$NAGGED" && "$NAGGED" -nt "$STARTED_AT" ]]; then
  exit 0
fi

# Not a git repo → can't detect changes, skip enforcement.
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# No uncommitted changes → no work to log.
CURRENT_PORCELAIN="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null || true)"
if [[ -z "$CURRENT_PORCELAIN" ]]; then
  exit 0
fi

# Per-session edit attribution via the PostToolUse tracker hook.
# The tracker appends each Claude Edit/Write/MultiEdit file path and each Codex
# apply_patch path to `edited-files.txt`. Reading that file is the primary
# signal — it tells us what THIS session actually touched, independent of what
# other sessions or out-of-band processes did to the worktree during our
# lifetime. Absent file → legacy session (tracker not yet deployed) or tracker
# disabled → fall through to porcelain-compare.
TRACK_FILE="$STATE_DIR/edited-files.txt"
USE_TRACKER=0
OWN_DIRTY_WIP=0
if [[ -f "$TRACK_FILE" ]]; then
  USE_TRACKER=1
  if [[ ! -s "$TRACK_FILE" ]]; then
    # Empty file → this session has tracker enabled but edited nothing.
    # Any porcelain noise is from sibling sessions or out-of-band edits.
    exit 0
  fi
  # For each tracked path, check whether it still appears as dirty in the
  # current porcelain. Porcelain lines are shaped `XY <path>` (two status
  # columns, then space, then the path); a fixed-string suffix match on
  # ` <path>` is enough to detect "still dirty" without parsing the status.
  while IFS= read -r tracked_path; do
    [[ -n "$tracked_path" ]] || continue
    if printf '%s\n' "$CURRENT_PORCELAIN" | grep -Fq -- " $tracked_path"; then
      OWN_DIRTY_WIP=1
      break
    fi
  done <"$TRACK_FILE"
  if [[ "$OWN_DIRTY_WIP" -eq 0 ]]; then
    # All tracked paths are clean (committed or reverted). Worktree may
    # still be dirty from siblings — not our concern.
    exit 0
  fi
fi

# Porcelain-compare fallback: when the tracker is absent (legacy session,
# disabled, or consumer project hasn't synced the tracker yet), discriminate carryover
# from real WIP via the SessionStart porcelain snapshot. Skipped when the
# tracker has already decided we have own WIP (OWN_DIRTY_WIP=1) — the
# porcelain-compare path would just duplicate the decision.
if [[ "$USE_TRACKER" -eq 0 ]]; then
  START_PORCELAIN="$STATE_DIR/start-porcelain.txt"
  if [[ -f "$START_PORCELAIN" ]]; then
    if [[ "$CURRENT_PORCELAIN" == "$(cat "$START_PORCELAIN")" ]]; then
      exit 0
    fi
  fi
fi

# HANDOFF.md updated during this session → all good.
if [[ -f "$SESSION_FILE" && "$SESSION_FILE" -nt "$STARTED_AT" ]]; then
  exit 0
fi

# Block once and re-prompt the model.
mkdir -p "$STATE_DIR"
touch "$NAGGED"
cat <<'JSON'
{"decision":"block","reason":"Before ending this session: the repo has uncommitted changes but .agent0/HANDOFF.md was not updated this session. Update .agent0/HANDOFF.md (Current State / Active Work / Next Actions / Decisions & Gotchas) so the next session can pick up where this one left off. Then end your turn normally — this hook will not block again this session."}
JSON
