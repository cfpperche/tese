#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"

out="$(
  AGENT0_CONTEXT_DIAGNOSTIC=1 AGENT0_PROJECT_DIR="$ROOT" bash "$HOOK" <<JSON
{"hook_event_name":"SessionStart","cwd":"$ROOT","source":"startup"}
JSON
)"

for needle in \
  "mode: diagnostic-index" \
  "Available fragments:" \
  "spec-driven:" \
  "runtime-capabilities:" \
  "END_AGENT0_CONTEXT_INJECTION"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: diagnostic index missing needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

if printf '%s\n' "$out" | grep -qF "source: .agent0/context/rules/spec-driven.md"; then
  printf 'FAIL: diagnostic index should list inventory, not emit full fragments\n%s\n' "$out"
  exit 1
fi

echo "PASS: 11-diagnostic-index-mode"
