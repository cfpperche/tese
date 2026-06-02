#!/usr/bin/env bash
# Run every vuln-audit scenario; aggregate pass/fail.
set -uo pipefail
cd "$(dirname "$0")"

TOTAL_FAIL=0
for t in [0-9][0-9]-*.sh; do
  [ -f "$t" ] || continue
  if bash "$t"; then :; else TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
  echo
done

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "=== vuln-audit: ALL SCENARIOS PASS ==="
else
  echo "=== vuln-audit: $TOTAL_FAIL scenario file(s) FAILED ==="
  exit 1
fi
