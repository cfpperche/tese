#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$ROOT/.agent0/tools/context-retrieve.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$TOOL" search \
    --query "Agent0 core thesis context engineering" \
    --format text \
    --limit 5
)"

for needle in \
  "context-retrieve: query=" \
  ".agent0/memory/agent0-core-thesis.md [memory; evidence-pointer" \
  "freshness: last_accessed=" \
  "read_before_acting: Read the memory entry before acting"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: explicit search missing needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

echo "PASS: 01-explicit-search-contract"
