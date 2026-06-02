#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|apply_patch) hook: blocks raw edits to
# .agent0/memory/MEMORY.md unless the edit carries an explicit override.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<'EOF'
memory-index-gate: jq not found.
Failing closed (exit 2) — install jq to restore MEMORY.md edit capability.
EOF
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
JOURNAL="$PROJECT_DIR/.agent0/.memory-events.jsonl"
PATHS="$(memory_extract_paths "$INPUT" "$PROJECT_DIR")"
[ -n "$PATHS" ] || exit 0

index_hit=0
printf '%s\n' "$PATHS" | while IFS= read -r rel; do
  if memory_is_index_path "$rel"; then
    exit 7
  fi
done
[ "$?" -eq 7 ] && index_hit=1

[ "$index_hit" -eq 1 ] || exit 0

TOOL_INPUT_BLOB="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || true)"
PATCH_BODY="$(memory_patch_body "$INPUT")"
SEARCH_BLOB="$(printf '%s\n%s\n' "$TOOL_INPUT_BLOB" "$PATCH_BODY")"

override_present=0
override_reason=""
override_too_short=0

raw_match="$(printf '%s' "$SEARCH_BLOB" | grep -oE '(# OVERRIDE: memory-index-edit: |<!-- OVERRIDE: memory-index-edit: )[^"\\]+' | head -1 || true)"
if [ -n "$raw_match" ]; then
  override_present=1
  reason="${raw_match#'# OVERRIDE: memory-index-edit: '}"
  reason="${reason#'<!-- OVERRIDE: memory-index-edit: '}"
  reason="$(printf '%s' "$reason" | sed -e 's/[[:space:]]*-->[[:space:]]*$//' -e 's/[[:space:]]*$//')"
  if [ ${#reason} -ge 10 ]; then
    override_reason="$reason"
  else
    override_too_short=1
  fi
fi

if [ "$override_present" -eq 0 ]; then
  cat >&2 <<'EOF'
memory-index-gate: blocked [raw-edit-without-override]

Direct edits to .agent0/memory/MEMORY.md are gated — the index is a derived
view, regenerated from the entries' frontmatter.

To update MEMORY.md, do one of:

  1. Edit the underlying entry file (.agent0/memory/<slug>.md), then run:
     bash .agent0/tools/memory-project.sh
     (hook-covered entry edits auto-regenerate too)

  2. If a manual MEMORY.md edit is genuinely needed (cleanup, migration),
     include this marker in the edit content (inline or HTML comment):

       # OVERRIDE: memory-index-edit: <reason ≥10 chars>

     or

       <!-- OVERRIDE: memory-index-edit: <reason ≥10 chars> -->

     The bypass is recorded in .agent0/.memory-events.jsonl as a
     `manual-edit` event with the reason as a field.

Rule: .agent0/context/rules/memory-placement.md § Event journal
EOF
  exit 2
fi

if [ "$override_too_short" -eq 1 ]; then
  cat >&2 <<'EOF'
memory-index-gate: blocked [override-reason-too-short]

An `# OVERRIDE: memory-index-edit:` marker was found, but the reason was
shorter than 10 characters after trimming. Lengthen the reason to a
greppable justification a future maintainer can audit.

Rule: .agent0/context/rules/memory-placement.md § Event journal
EOF
  exit 2
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
tool_use_id="$(printf '%s' "$INPUT" | jq -r '.tool_use_id // ""' 2>/dev/null || true)"
tool_name="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)"
actor="$(memory_actor "$INPUT")"
runtime="$(memory_runtime "$INPUT")"

mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || true
audit_line="$(jq -c -n \
  --arg ts "$ts" \
  --arg event_type "manual-edit" \
  --arg entry_id "MEMORY.md" \
  --arg actor "$actor" \
  --arg session_id "$session_id" \
  --arg tool_use_id "$tool_use_id" \
  --arg tool "$tool_name" \
  --arg reason "$override_reason" \
  --arg path ".agent0/memory/MEMORY.md" \
  --arg runtime "$runtime" \
  '{ts:$ts, event_type:$event_type, entry_id:$entry_id, actor:$actor, runtime:$runtime, session_id:$session_id, tool_use_id:$tool_use_id, tool:$tool, reason:$reason, path:$path}' 2>/dev/null || true)"

if [ -n "$audit_line" ]; then
  printf '%s\n' "$audit_line" >> "$JOURNAL" 2>/dev/null || true
fi

exit 0
