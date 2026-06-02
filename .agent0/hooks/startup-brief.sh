#!/usr/bin/env bash
# SessionStart hook: emit one bounded Agent0 startup brief.
#
# This is the only model-visible SessionStart hook registered by Agent0. Older
# readout scripts stay callable as helpers/tests, but the live runtime receives
# one summary-first block instead of several separate hook-context blocks.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"
# Composition functions (handoff/reminders/routines/decay/githooks/context)
# live in the shared lib so the on-demand `status` tool reuses them verbatim
# (spec 137). This hook keeps emit/truncation/session-state local.
# shellcheck source=_brief-compose.sh
. "$SCRIPT_DIR/_brief-compose.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
SESSION_STATE_ROOT="$PROJECT_DIR/.agent0/.session-state"
SESSION_FILE="$PROJECT_DIR/.agent0/HANDOFF.md"
MAX_BYTES="${AGENT0_STARTUP_BRIEF_MAX_BYTES:-6000}"
MAX_LINES="${AGENT0_STARTUP_BRIEF_MAX_LINES:-80}"
REMINDER_LIMIT="${AGENT0_STARTUP_REMINDER_LIMIT:-5}"
REMINDER_TEXT_MAX="${AGENT0_STARTUP_REMINDER_TEXT_MAX:-220}"
HANDOFF_SECTION_LINES="${AGENT0_STARTUP_HANDOFF_SECTION_LINES:-2}"
TODAY="$(date -u +%Y-%m-%d)"

hook_event() {
  if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    printf '%s' "$INPUT" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null || printf 'SessionStart'
  else
    printf 'SessionStart'
  fi
}

init_session_state() {
  local session_id_raw="" session_id state_dir
  if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
    session_id_raw="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  fi

  if [[ -n "$session_id_raw" && "$session_id_raw" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    session_id="$session_id_raw"
  else
    session_id="unknown"
  fi

  state_dir="$SESSION_STATE_ROOT/$session_id"
  mkdir -p "$state_dir"
  touch "$state_dir/started-at"
  rm -f "$state_dir/nagged"
  touch "$state_dir/edited-files.txt"

  if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$PROJECT_DIR" status --porcelain >"$state_dir/start-porcelain.txt" 2>/dev/null || true
  fi

  find "$SESSION_STATE_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
}

trim_lines() {
  awk -v max="$MAX_LINES" 'NR <= max { print } NR == max + 1 { print "... output truncated by AGENT0_STARTUP_BRIEF_MAX_LINES" }'
}

trim_bytes() {
  if [ "${#1}" -le "$MAX_BYTES" ]; then
    printf '%s' "$1"
    return 0
  fi
  printf '%s\n... output truncated by AGENT0_STARTUP_BRIEF_MAX_BYTES\n' "${1:0:MAX_BYTES}"
}

emit_context() {
  local msg="$1" event="$2"
  [ -n "$msg" ] || exit 0
  if [ "$(memory_runtime "$INPUT")" = "codex-cli" ]; then
    printf '%s' "$msg"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg event "$event" --arg msg "$msg" '{
      hookSpecificOutput: { hookEventName: $event, additionalContext: $msg }
    }' 2>/dev/null || printf '%s' "$msg"
  else
    printf '%s' "$msg"
  fi
}

build_brief() {
  local out trimmed
  out=$'AGENT0_STARTUP_BRIEF\n'
  out+="event: $(hook_event)"$'\n'
  out+=$'mode: summary\n'
  out+=$'budget: 6000 bytes / 80 lines by default\n\n'
  out+="$(summarize_handoff)"$'\n'
  out+="$(githooks_advisory)"$'\n'
  out+="$(summarize_reminders)"$'\n'
  out+="$(summarize_routines)"$'\n'
  out+="$(summarize_memory_decay)"$'\n'
  out+="$(context_pointer)"$'\n'
  out+=$'END_AGENT0_STARTUP_BRIEF\n'

  trimmed="$(printf '%s' "$out" | trim_lines)"
  trim_bytes "$trimmed"
}

init_session_state
emit_context "$(build_brief)" "$(hook_event)"
