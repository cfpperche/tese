#!/usr/bin/env bash
# Orchestrator for spec-099 memory multi-runtime scenarios.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
export AGENT0_ROOT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

scripts=""
for n in 01 02 03 04 05; do
  match="$(ls "$SCRIPT_DIR/${n}"-*.sh 2>/dev/null | head -1 || true)"
  [ -n "$match" ] && scripts="$scripts $match"
done

if [ -z "$scripts" ]; then
  printf 'run-all.sh: no scenario scripts found in %s\n' "$SCRIPT_DIR" >&2
  exit 1
fi

results=""
any_fail=0
tmpout="$(mktemp -t memory-mr-run-all-XXXXXX)"
trap 'rm -f "$tmpout"' EXIT

for script in $scripts; do
  name="$(basename "$script")"
  script_exit=0
  bash "$script" >"$tmpout" 2>&1 || script_exit=$?
  if [ "$script_exit" -ne 0 ]; then
    cat "$tmpout"
    results="$results
  $name  FAIL"
    any_fail=1
  else
    results="$results
  $name  PASS"
  fi
done

printf '\n=== memory-multi-runtime scenario results ===\n'
printf '%s\n' "$results"
printf '============================================\n'

if [ "$any_fail" -eq 0 ]; then
  printf 'All scenarios PASS.\n'
  exit 0
fi

printf 'One or more scenarios FAILED.\n'
exit 1
