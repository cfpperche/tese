#!/usr/bin/env bash
# Scenario: mixed tree -> found/covered/skipped buckets are correct & honest.
source "$(dirname "$0")/_lib.sh"
echo "05-three-bucket-coverage"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"   # supported, will be covered
: > "$WORK/proj/composer.lock"       # supported, will be covered
: > "$WORK/proj/bun.lockb"           # unsupported -> skipped

# Engine only reports the two it parsed.
FIX="$(fixture <<JSON
{ "results": [
  { "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" }, "packages": [] },
  { "source": { "path": "$WORK/proj/composer.lock", "type": "lockfile" }, "packages": [] }
] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=0
OUT="$(bash "$TOOL" --json "$WORK/proj")"; RC=$?

assert_eq "$RC" "0" "exit 0"
assert_eq "$(echo "$OUT" | jq -r '.coverage.found | length')" "3" "found = 3 lockfiles"
assert_eq "$(echo "$OUT" | jq -r '.coverage.covered | length')" "2" "covered = 2 lockfiles"
assert_eq "$(echo "$OUT" | jq -r '.coverage.skipped | length')" "1" "skipped = 1 lockfile"
assert_eq "$(echo "$OUT" | jq -r '.coverage.skipped[0].lockfile')" "bun.lockb" "bun.lockb is the skipped one"

finish
