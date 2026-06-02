#!/usr/bin/env bash
# .agent0/tests/delegation-verify/07-shellcheck.sh
# Static check: delegation-verify.sh passes `bash -n` always, and shellcheck
# (when available) with no errors. Skips the shellcheck leg gracefully if the
# binary is absent (matches the 061 suite convention).
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/delegation-verify.sh"

bash -n "$HOOK" || { printf 'FAIL: bash -n\n'; exit 1; }

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$HOOK" || { printf 'FAIL: shellcheck -S error\n'; exit 1; }
  printf 'PASS (bash -n + shellcheck)\n'
else
  printf 'PASS (bash -n; shellcheck absent, leg skipped)\n'
fi
