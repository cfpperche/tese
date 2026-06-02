#!/usr/bin/env bash
# .agent0/tools/memory-backfill.sh
# One-shot idempotent seed for .agent0/.memory-events.jsonl: for each entry in
# .agent0/memory/*.md (excluding MEMORY.md) that has no `add` event yet,
# append one with `ts` from `git log --reverse --format=%aI <file> | head -1`
# (filesystem mtime fallback if untracked), `actor: "backfill"`, `tool: null`.
#
# Second invocation is a no-op (journal already populated for each entry).
#
# Rule: .agent0/context/rules/memory-placement.md § Event journal

set -uo pipefail
LC_ALL=C

PROJECT_DIR="${AGENT0_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
MEMORY_DIR="$PROJECT_DIR/.agent0/memory"
JOURNAL="$PROJECT_DIR/.agent0/.memory-events.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  printf 'memory-backfill: jq not found; install jq to run\n' >&2
  exit 1
fi

if [ ! -d "$MEMORY_DIR" ]; then
  printf 'memory-backfill: %s does not exist\n' "$MEMORY_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || true
touch "$JOURNAL" 2>/dev/null || true

backfilled=0
skipped=0

for file in "$MEMORY_DIR"/*.md; do
  [ -e "$file" ] || continue
  base="$(basename "$file")"
  [ "$base" = "MEMORY.md" ] && continue

  entry_id="${base%.md}"

  # Skip if journal already has an `add` event for this entry_id.
  prior="$(jq -c --arg id "$entry_id" 'select(.entry_id == $id and .event_type == "add")' "$JOURNAL" 2>/dev/null | head -1 || true)"
  if [ -n "$prior" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # ts: git-introduction time if tracked, else filesystem mtime.
  ts="$(git log --reverse --format=%aI -- "$file" 2>/dev/null | head -1 || true)"
  if [ -z "$ts" ]; then
    # Filesystem mtime fallback. Try GNU then BSD stat.
    mtime_epoch="$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || true)"
    if [ -n "$mtime_epoch" ]; then
      ts="$(date -u -d "@$mtime_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$mtime_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    fi
  fi
  [ -z "$ts" ] && ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  audit_line="$(jq -c -n \
    --arg ts "$ts" \
    --arg event_type "add" \
    --arg entry_id "$entry_id" \
    --arg actor "backfill" \
    --arg runtime "backfill" \
    --arg session_id "" \
    --arg tool_use_id "" \
    --argjson tool null \
    --arg path ".agent0/memory/$base" \
    '{ts:$ts, event_type:$event_type, entry_id:$entry_id, actor:$actor, runtime:$runtime, session_id:$session_id, tool_use_id:$tool_use_id, tool:$tool, path:$path}' 2>/dev/null || true)"

  if [ -n "$audit_line" ]; then
    printf '%s\n' "$audit_line" >> "$JOURNAL"
    backfilled=$((backfilled + 1))
  fi
done

printf 'memory-backfill: backfilled %s entries (%s already present)\n' "$backfilled" "$skipped" >&2
