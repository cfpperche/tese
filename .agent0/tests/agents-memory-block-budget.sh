#!/usr/bin/env bash
# Enforce the Agent0 entrypoint Memory block budget.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
FILE="$AGENT0_ROOT/AGENTS.md"
MAX_LINES=12

if [ ! -f "$FILE" ]; then
  printf 'agents-memory-block-budget: missing AGENTS.md at %s\n' "$FILE" >&2
  exit 1
fi

count="$(awk '
  /^## Memory$/ { in_block=1; found=1; next }
  in_block && /^## / { in_block=0 }
  in_block && NF { count++ }
  END {
    if (!found) {
      print "MISSING"
    } else {
      print count + 0
    }
  }
' "$FILE")"

if [ "$count" = "MISSING" ]; then
  printf 'agents-memory-block-budget: AGENTS.md missing ## Memory block\n' >&2
  exit 1
fi

if [ "$count" -gt "$MAX_LINES" ]; then
  printf 'agents-memory-block-budget: AGENTS.md ## Memory block has %s non-blank lines (max %s). Move detail to .agent0/context/rules/memory-placement.md § Multi-runtime usage.\n' "$count" "$MAX_LINES" >&2
  exit 1
fi

exit 0
