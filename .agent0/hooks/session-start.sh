#!/usr/bin/env bash
# SessionStart hook: inject canonical handoff and start-source context.
#
# - all sources → .agent0/HANDOFF.md (canonical cross-runtime handoff)
#
# State is isolated per-session_id: markers live at
# `<.session-state>/<session_id>/{started-at,nagged}`. Parallel runtime
# sessions in the same project don't interfere with each other's nag state.
# Sanitization (regex `^[a-zA-Z0-9_-]+$`) defends against path traversal in
# malformed/malicious payloads; failures fall to the literal `unknown` subdir.

set -euo pipefail

# Read stdin payload FIRST so we can extract session_id before any state ops.
INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
SESSION_STATE_ROOT="$PROJECT_DIR/.agent0/.session-state"
SESSION_FILE="$PROJECT_DIR/.agent0/HANDOFF.md"

SESSION_ID_RAW=""
if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
  SESSION_ID_RAW="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

# Sanitize session_id: only [a-zA-Z0-9_-]+; anything else falls to "unknown".
if [[ -n "$SESSION_ID_RAW" && "$SESSION_ID_RAW" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  SESSION_ID="$SESSION_ID_RAW"
else
  SESSION_ID="unknown"
fi

STATE_DIR="$SESSION_STATE_ROOT/$SESSION_ID"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/started-at"
rm -f "$STATE_DIR/nagged"

# Edit attribution: create an empty edited-files.txt marker so Stop can distinguish
# "tracker is installed and this session edited nothing" (bystander → exit 0)
# from "tracker is not installed at all" (legacy session → fall to porcelain-compare).
# The tracker hook fires on Claude Edit/Write/MultiEdit and Codex apply_patch,
# so without this seed a real bystander session would have no file and fall to
# the legacy path.
touch "$STATE_DIR/edited-files.txt"

# Porcelain snapshot: snapshot `git status --porcelain` so Stop can discriminate
# "this session changed nothing" (carryover or no-op) from "this session
# has uncommitted WIP that needs a HANDOFF.md update". Best-effort —
# absence triggers Stop's fallback to today's mtime-only logic.
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$PROJECT_DIR" status --porcelain >"$STATE_DIR/start-porcelain.txt" 2>/dev/null || true
fi

# Accumulate all banner blocks into BANNER, then emit at the end. Claude gets a
# dual-channel JSON object; Codex gets plain framed stdout.
BANNER=""

if [[ -f "$SESSION_FILE" ]]; then
  BANNER+=$'=== HANDOFF.md (canonical handoff) ===\n'
  BANNER+="$(cat "$SESSION_FILE" 2>/dev/null || true)"
  BANNER+=$'\n=== end HANDOFF.md ===\n'
else
  BANNER+=$'=== handoff-advisory ===\n'
  BANNER+="'.agent0/HANDOFF.md' missing — create it to enable handoff"
  BANNER+=$'\n'
  BANNER+=$'=== end handoff-advisory ===\n'
fi

# githooks-activation: surface the manual core.hooksPath activation
# command when .githooks/ is present but config doesn't point at it.
# Auto-activation is refused on purpose (Lazarus vector — see
# .agent0/context/rules/secrets-scan.md § Gotchas); the passive advisory closes the
# discoverability gap without crossing into automation.
if [[ -d "$PROJECT_DIR/.githooks" && "${CLAUDE_SKIP_GITHOOKS_HINT:-0}" != "1" ]]; then
  current_hookspath="$(git -C "$PROJECT_DIR" config --get core.hooksPath 2>/dev/null || true)"
  if [[ "$current_hookspath" != ".githooks" ]]; then
    BANNER+=$'\n=== githooks-activation ===\nNative git hooks NOT activated (gitleaks pre-commit inert).\nRun once: git config core.hooksPath .githooks\n=== end githooks-activation ===\n'
  fi
fi

# Cleanup: best-effort removal of session-state subdirs older than
# 7 days. Failure NEVER blocks the hook — silenced with 2>/dev/null || true.
find "$SESSION_STATE_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true

# Emit runtime-specific output. Claude keeps the dual-channel JSON so the
# banner remains visible in the UI; Codex SessionStart accepts plain stdout as
# developer context and existing Agent0 Codex readout hooks already use that
# shape.
if [[ -n "$BANNER" ]]; then
  if [[ "$(memory_runtime "$INPUT")" == "codex-cli" ]]; then
    printf '%s' "$BANNER"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$BANNER" '{
      hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $msg },
      systemMessage: $msg
    }' 2>/dev/null || true
  else
    printf '%s' "$BANNER"
  fi
fi
