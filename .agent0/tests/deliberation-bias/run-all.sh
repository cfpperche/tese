#!/usr/bin/env bash
# .agent0/tests/deliberation-bias/run-all.sh
# Orchestrator for spec-149 (deliberation anti-confirmation-bias) scenarios.
# Runs every NN-*.sh in lex order, prints a summary, exits 0 iff all pass.
#   bash run-all.sh        # quiet — summary + failing output only
#   bash run-all.sh -v     # verbose
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
export AGENT0_ROOT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

any_fail=0
results=""
tmpout="$(mktemp -t db-run-all-XXXXXX)"
trap 'rm -f "$tmpout"' EXIT

for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
  [ -e "$script" ] || continue
  name="$(basename "$script")"
  rc=0
  if [ "$VERBOSE" -eq 1 ]; then
    bash "$script" || rc=$?
  else
    bash "$script" >"$tmpout" 2>&1 || rc=$?
    [ "$rc" -ne 0 ] && cat "$tmpout"
  fi
  if [ "$rc" -eq 0 ]; then results="$results
  $name  PASS"; else results="$results
  $name  FAIL"; any_fail=1; fi
done

printf '\n=== deliberation-bias scenario results ===\n'
printf '%s\n' "$results"
printf '==========================================\n'
if [ "$any_fail" -eq 0 ]; then printf 'All scenarios PASS.\n'; exit 0
else printf 'One or more scenarios FAILED.\n'; exit 1; fi
