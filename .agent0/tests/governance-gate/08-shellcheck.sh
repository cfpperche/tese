#!/usr/bin/env bash
# Static analysis of the gate. shellcheck when available, else bash -n.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ -f "$GOVERNANCE_HOOK" ] || { printf 'FAIL: hook not found: %s\n' "$GOVERNANCE_HOOK"; exit 1; }

if command -v shellcheck >/dev/null 2>&1; then
  sc=0; shellcheck -S warning "$GOVERNANCE_HOOK" || sc=$?
  [ "$sc" -eq 0 ] || { printf 'FAIL: shellcheck warnings/errors (exit %d)\n' "$sc"; exit 1; }
  printf 'PASS: %s (shellcheck clean)\n' "$(basename "$0")"
else
  bash -n "$GOVERNANCE_HOOK" || { printf 'FAIL: bash -n syntax error\n'; exit 1; }
  printf 'PASS: %s (bash -n clean)\n' "$(basename "$0")"
fi
