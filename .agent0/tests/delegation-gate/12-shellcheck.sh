#!/usr/bin/env bash
# Static check: delegation-gate.sh passes `bash -n` always, and shellcheck
# (when available) with no errors. Skips the shellcheck leg gracefully if the
# binary is absent (matches the delegation-verify + 061 suite convention).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-gate.sh"

bash -n "$HOOK" || { printf 'FAIL: bash -n\n'; exit 1; }

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$HOOK" || { printf 'FAIL: shellcheck -S error\n'; exit 1; }
  printf 'PASS (bash -n + shellcheck)\n'
else
  printf 'PASS (bash -n; shellcheck absent, leg skipped)\n'
fi
