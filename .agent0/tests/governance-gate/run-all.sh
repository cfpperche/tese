#!/usr/bin/env bash
# .agent0/tests/governance-gate/run-all.sh
# Runs every NN-*.sh in lex order; prints a summary table. Exit 0 if all pass.
# Usage: bash run-all.sh [-v]
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
export AGENT0_ROOT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

scripts=""
for n in 01 02 03 04 05 06 07 08; do
  match="$(ls "$SCRIPT_DIR/${n}"-*.sh 2>/dev/null | head -1 || true)"
  [ -n "$match" ] && scripts="$scripts $match"
done
[ -n "$scripts" ] || { printf 'run-all.sh: no scenario scripts found\n' >&2; exit 1; }

results=""; any_fail=0
tmpout="$(mktemp)"; trap 'rm -f "$tmpout"' EXIT

for script in $scripts; do
  name="$(basename "$script")"; ex=0
  if [ "$VERBOSE" -eq 1 ]; then bash "$script" || ex=$?
  else bash "$script" >"$tmpout" 2>&1 || ex=$?; [ "$ex" -ne 0 ] && cat "$tmpout"; fi
  if [ "$ex" -eq 0 ]; then results="$results
  $name  PASS"; else results="$results
  $name  FAIL"; any_fail=1; fi
done

printf '\n=== governance-gate scenario results ===\n%s\n========================================\n' "$results"
[ "$any_fail" -eq 0 ] && { printf 'All scenarios PASS.\n'; exit 0; } || { printf 'One or more scenarios FAILED.\n'; exit 1; }
