#!/usr/bin/env bash
# Scenario: factual project memory is git-tracked.
# Asserts:
#   (a) .agent0/memory/ exists as a directory
#   (b) at least 1 entry .md (excluding MEMORY.md) is git-tracked there
#
# Property is intentionally generic — hardcoded entry names would only
# pass in the upstream Agent0 repo (where those specific entries exist)
# and would always fail in consumer projects regardless of migration
# state. The "≥1 entry tracked" shape signals both that the bucket has
# been adopted AND that consumer content has landed under .agent0/memory/.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"

if [ ! -d "$AGENT0_ROOT/.agent0/memory" ]; then
  printf 'FAIL: .agent0/memory/ does not exist at %s\n' "$AGENT0_ROOT/.agent0/memory"
  exit 1
fi

tracked="$(git -C "$AGENT0_ROOT" ls-files .agent0/memory/ 2>/dev/null || true)"
entry_count="$(printf '%s\n' "$tracked" \
  | grep -E '^\.agent0/memory/[^/]+\.md$' \
  | grep -vE '^\.agent0/memory/MEMORY\.md$' \
  | grep -c . || true)"

if [ "$entry_count" -lt 1 ]; then
  printf 'FAIL: expected ≥1 entry .md (excluding MEMORY.md) git-tracked under .agent0/memory/, found %d\n' "$entry_count"
  printf 'git ls-files output:\n%s\n' "$tracked"
  exit 1
fi

echo "PASS: 01-files-are-git-tracked"
