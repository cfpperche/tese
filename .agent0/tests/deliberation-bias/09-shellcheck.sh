#!/usr/bin/env bash
# meeting.sh passes `bash -n` always, and shellcheck -S error when available.
set -euo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
bash -n "$H" || { echo "FAIL: bash -n"; exit 1; }
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$H" || { echo "FAIL: shellcheck -S error"; exit 1; }
  echo "PASS (bash -n + shellcheck)"
else
  echo "PASS (bash -n; shellcheck absent)"
fi
