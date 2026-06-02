#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$ROOT/.agent0/tools/context-retrieve.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$TOOL" search \
    --query "context retrieval memory adapter" \
    --format debug \
    --limit 2
)"

for needle in \
  "CONTEXT_RETRIEVE_DEBUG" \
  "query: context retrieval memory adapter" \
  "corpus:" \
  "cache: none" \
  "returned:" \
  "omitted:" \
  "END_CONTEXT_RETRIEVE_DEBUG"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: debug output missing needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

echo "PASS: 03-debug-output"
