#!/usr/bin/env bash
# Scenario: engine present but errors (exit 127) -> status=failed, exit 0 by default.
source "$(dirname "$0")/_lib.sh"
echo "04-failed"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

# No JSON body + non-standard error exit.
export FAKE_OSV_JSON="" FAKE_OSV_EXIT=127
OUT="$(bash "$TOOL" "$WORK/proj")"; RC=$?

assert_eq "$RC" "0" "failed exits 0 by default (advisory family)"
assert_contains "$OUT" "status=failed" "status is failed"
assert_contains "$OUT" "did not produce parseable results" "failed explains itself"

# --exit-code maps failed -> 3
OUT2="$(bash "$TOOL" --exit-code "$WORK/proj")"; RC2=$?
assert_eq "$RC2" "3" "--exit-code maps failed to 3"

finish
