#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" AGENT0_CONTEXT_MAX_FRAGMENTS=4 bash "$HOOK" <<JSON
{"hook_event_name":"UserPromptSubmit","cwd":"$ROOT","prompt":"runtime context core thesis engineering"}
JSON
)"

for floor in \
  "source: .agent0/context/rules/runtime-capabilities.md" \
  "source: .agent0/context/rules/harness-sync.md" \
  "source: .agent0/context/rules/memory-placement.md"; do
  if ! printf '%s\n' "$out" | grep -qF "$floor"; then
    printf 'FAIL: deterministic floor was evicted: %s\n%s\n' "$floor" "$out"
    exit 1
  fi
done

source_count="$(printf '%s\n' "$out" | grep -c '^source: ' || true)"
if [ "$source_count" -gt 4 ]; then
  printf 'FAIL: context injection exceeded max fragments (%s)\n%s\n' "$source_count" "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -qF "source: .agent0/memory/agent0-core-thesis.md"; then
  printf 'FAIL: retrieval lane did not add expected memory evidence pointer\n%s\n' "$out"
  exit 1
fi

echo "PASS: 04-context-inject-floor"
