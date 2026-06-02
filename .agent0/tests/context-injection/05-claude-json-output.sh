#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/context-inject.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

out="$(
  CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" <<JSON
{"hook_event_name":"UserPromptSubmit","cwd":"$ROOT","prompt":"spec work"}
JSON
)"

if ! printf '%s\n' "$out" | jq -e '
  .hookSpecificOutput.hookEventName == "UserPromptSubmit"
  and (.hookSpecificOutput.additionalContext | contains("source: .agent0/context/rules/spec-driven.md"))
  and (.hookSpecificOutput.additionalContext | contains("mode: prompt-capsules"))
' >/dev/null; then
  printf 'FAIL: Claude output should be JSON additionalContext\n%s\n' "$out"
  exit 1
fi

echo "PASS: 05-claude-json-output"
