#!/usr/bin/env bash
# Scenario: engine returns packages, no vulns -> status=clean with explicit line.
source "$(dirname "$0")/_lib.sh"
echo "02-clean-status"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

FIX="$(fixture <<JSON
{ "results": [ { "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" }, "packages": [] } ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=0
OUT="$(bash "$TOOL" "$WORK/proj")"; RC=$?

assert_eq "$RC" "0" "clean exits 0"
assert_contains "$OUT" "status=clean" "status is clean"
assert_contains "$OUT" "no known-vulnerable dependencies" "explicit clean line, not silence"
assert_contains "$OUT" "npm" "names the ecosystem scanned"

finish
