#!/usr/bin/env bash
# Scenario: tracked Codex hooks.json registers one aggregate SessionStart readout.

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

if ! jq -e '.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains(".agent0/hooks/startup-brief.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: missing aggregate SessionStart startup-brief.sh command\n'
  exit 1
fi

if jq -e '.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("memory-decay-readout.sh") or contains("reminders-readout.sh") or contains("routines-readout.sh"))' "$CONFIG" >/dev/null; then
  printf 'FAIL: separate SessionStart readout hooks should not be model-visible\n'
  exit 1
fi

echo "PASS: 05-hooks-json-parse"
