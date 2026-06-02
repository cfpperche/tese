#!/usr/bin/env bash
# Scenario 5: tracked Codex hooks.json registers session handoff hooks.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CONFIG="$AGENT0_ROOT/.codex/hooks.json"

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: jq missing\n'
  exit 0
fi

if ! jq -e . "$CONFIG" >/dev/null; then
  printf 'FAIL: .codex/hooks.json is not valid JSON\n'
  exit 1
fi

if ! jq -e '.hooks.SessionStart[]? | select((.matcher // "") == "startup|resume|clear|compact") | .hooks[]? | select((.command // "") | contains("startup-brief.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: SessionStart startup-brief.sh hook missing or matcher wrong\n'
  exit 1
fi

if jq -e '.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("session-start.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: session-start.sh should be a startup-brief helper, not a registered SessionStart hook\n'
  exit 1
fi

if ! jq -e '.hooks.Stop[]?.hooks[]? | select((.command // "") | contains("session-stop.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: Stop session-stop.sh hook missing\n'
  exit 1
fi

if ! jq -e '.hooks.PostToolUse[]? | select((.matcher // "") == "^apply_patch$") | .hooks[]? | select((.command // "") | contains("session-track-edits.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: PostToolUse apply_patch session-track-edits.sh hook missing\n'
  exit 1
fi

printf 'PASS: 05-hooks-json-parse\n'
exit 0
