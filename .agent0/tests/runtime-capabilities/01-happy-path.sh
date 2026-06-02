#!/usr/bin/env bash
# Scenario: the real repo satisfies runtime capability registry anchors.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"

out="$(bash "$TOOL" --root "$AGENT0_ROOT" --agent0-path "$AGENT0_ROOT" --skip-sync-check 2>&1)"

if ! printf '%s\n' "$out" | grep -q 'runtime capability registry anchor checks passed'; then
  printf 'FAIL: expected registry anchor checks pass diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 01-happy-path"
