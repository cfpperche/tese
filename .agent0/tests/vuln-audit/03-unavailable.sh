#!/usr/bin/env bash
# Scenario: engine binary absent -> status=unavailable, install advisory, exit 0.
source "$(dirname "$0")/_lib.sh"
echo "03-unavailable"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

# Point the engine at a name that does not exist on PATH.
export VULN_AUDIT_ENGINE="osv-scanner-does-not-exist-xyz"
OUT="$(bash "$TOOL" "$WORK/proj")"; RC=$?

assert_eq "$RC" "0" "unavailable exits 0 (advisory family)"
assert_contains "$OUT" "status=unavailable" "status is unavailable"
assert_contains "$OUT" "not installed" "advisory names the missing binary"
assert_contains "$OUT" "Would have scanned" "names ecosystems it would have scanned"
assert_contains "$OUT" "npm" "ecosystem listed in would-have-scanned"

# --exit-code maps unavailable -> 2
OUT2="$(bash "$TOOL" --exit-code "$WORK/proj")"; RC2=$?
assert_eq "$RC2" "2" "--exit-code maps unavailable to 2"

finish
