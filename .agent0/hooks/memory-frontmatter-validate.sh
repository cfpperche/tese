#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit|apply_patch) advisory hook for project-memory
# entry frontmatter. Always exits 0.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
MAINTAIN="$PROJECT_DIR/.agent0/tools/memory-maintain.sh"
[ -x "$MAINTAIN" ] || exit 0

memory_extract_paths "$INPUT" "$PROJECT_DIR" | while IFS= read -r rel; do
  memory_is_entry_path "$rel" || continue
  abs="$(memory_abspath "$PROJECT_DIR" "$rel")"
  [ -r "$abs" ] || continue
  AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$MAINTAIN" validate "$abs" || true
done

exit 0
