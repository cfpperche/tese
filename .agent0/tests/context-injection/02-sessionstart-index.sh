#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$HOOK" <<JSON
{"hook_event_name":"SessionStart","cwd":"$ROOT","source":"startup"}
JSON
)"

for needle in \
  "AGENT0_CONTEXT_INJECTION" \
  "mode: startup-pointer" \
  "source_dir: .agent0/context/rules" \
  "normal startup context is emitted by .agent0/hooks/startup-brief.sh" \
  "END_AGENT0_CONTEXT_INJECTION"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: missing SessionStart pointer needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

if printf '%s\n' "$out" | grep -qF "source: .agent0/context/rules/spec-driven.md"; then
  printf 'FAIL: normal SessionStart should not emit full fragments\n%s\n' "$out"
  exit 1
fi

if printf '%s\n' "$out" | grep -qF "spec-driven:"; then
  printf 'FAIL: normal SessionStart should not emit the fragment index\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-sessionstart-pointer"
