#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$HOOK" <<JSON
{"hook_event_name":"UserPromptSubmit","cwd":"$ROOT","prompt":"precisamos alterar .agent0/tools/sync-harness.sh"}
JSON
)"

if ! printf '%s\n' "$out" | grep -qF "source: .agent0/context/rules/harness-sync.md"; then
  printf 'FAIL: sync-harness prompt should hydrate harness-sync rule\n%s\n' "$out"
  exit 1
fi

echo "PASS: 04-userprompt-selects-path-rule"
