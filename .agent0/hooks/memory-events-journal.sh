#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit|apply_patch) hook: append one best-effort
# JSONL event per project-memory entry edit, then regenerate MEMORY.md.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
JOURNAL="$PROJECT_DIR/.agent0/.memory-events.jsonl"
PROJECTOR="$PROJECT_DIR/.agent0/tools/memory-project.sh"
PATHS="$(memory_extract_paths "$INPUT" "$PROJECT_DIR")"
[ -n "$PATHS" ] || exit 0

entry_paths="$(printf '%s\n' "$PATHS" | while IFS= read -r rel; do
  memory_is_entry_path "$rel" && printf '%s\n' "$rel"
done)"
[ -n "$entry_paths" ] || exit 0

if [ ! -e "$JOURNAL" ]; then
  printf 'memory-journal-advisory: journal empty; run `bash .agent0/tools/memory-backfill.sh` once to seed history for the existing entries (otherwise first edits will misrecord as add)\n' >&2
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
tool_use_id="$(printf '%s' "$INPUT" | jq -r '.tool_use_id // ""' 2>/dev/null || true)"
tool_name="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)"
actor="$(memory_actor "$INPUT")"
runtime="$(memory_runtime "$INPUT")"

mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || true

printf '%s\n' "$entry_paths" | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  abs="$(memory_abspath "$PROJECT_DIR" "$rel")"

  # `delete` events remain reserved in v1. A deleted entry still causes the
  # projection refresh below, but no journal line is appended for the delete.
  # Frontmatter validation is owned by memory-frontmatter-validate.sh (separate
  # PostToolUse hook) so this script does not double-emit advisories.
  [ -e "$abs" ] || continue

  base="$(basename "$rel")"
  entry_id="${base%.md}"
  event_type="add"
  if [ -e "$JOURNAL" ]; then
    prior="$(jq -c --arg id "$entry_id" 'select(.entry_id == $id and .event_type == "add")' "$JOURNAL" 2>/dev/null | head -1 || true)"
    [ -n "$prior" ] && event_type="update"
  fi

  audit_line="$(jq -c -n \
    --arg ts "$ts" \
    --arg event_type "$event_type" \
    --arg entry_id "$entry_id" \
    --arg actor "$actor" \
    --arg session_id "$session_id" \
    --arg tool_use_id "$tool_use_id" \
    --arg tool "$tool_name" \
    --arg path "$rel" \
    --arg runtime "$runtime" \
    '{ts:$ts, event_type:$event_type, entry_id:$entry_id, actor:$actor, runtime:$runtime, session_id:$session_id, tool_use_id:$tool_use_id, tool:$tool, path:$path}' 2>/dev/null || true)"

  if [ -z "$audit_line" ]; then
    printf 'memory-journal-advisory: failed to build event line (jq error)\n' >&2
    continue
  fi
  if ! { printf '%s\n' "$audit_line" >> "$JOURNAL"; } 2>/dev/null; then
    printf 'memory-journal-advisory: journal append failed (unwritable: %s)\n' "$JOURNAL" >&2
  fi
done

if [ -x "$PROJECTOR" ]; then
  if ! AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECTOR" >/dev/null 2>&1; then
    printf 'memory-journal-advisory: projection failed (memory-project.sh exit non-zero); MEMORY.md may be stale\n' >&2
  fi
else
  printf 'memory-journal-advisory: projector %s not found or not executable; MEMORY.md may be stale\n' "$PROJECTOR" >&2
fi

exit 0
