#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$HOOK" <<JSON
{"hook_event_name":"UserPromptSubmit","cwd":"$ROOT","prompt":"vamos mexer em docs/specs e seguir SDD"}
JSON
)"

for needle in \
  "mode: prompt-capsules" \
  "source: .agent0/context/rules/spec-driven.md" \
  "title: Spec-driven development" \
  "capsule: Read this file before acting"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: missing prompt-selected spec needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

if printf '%s\n' "$out" | grep -qF "# Spec-driven development"; then
  printf 'FAIL: prompt-selected output should not include full spec-driven body\n%s\n' "$out"
  exit 1
fi

echo "PASS: 03-userprompt-selects-spec"
