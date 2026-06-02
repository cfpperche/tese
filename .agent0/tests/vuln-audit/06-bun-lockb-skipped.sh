#!/usr/bin/env bash
# Scenario: bun.lock covered + bun.lockb skipped w/ migrate hint (canonical mixed case).
# A partially-covered bun project must NOT be reported as clean coverage.
source "$(dirname "$0")/_lib.sh"
echo "06-bun-lockb-skipped"

mkdir -p "$WORK/proj"
: > "$WORK/proj/bun.lock"    # text, supported by osv-scanner since Bun >=1.2
: > "$WORK/proj/bun.lockb"   # binary legacy, NOT parsed

FIX="$(fixture <<JSON
{ "results": [ { "source": { "path": "$WORK/proj/bun.lock", "type": "lockfile" }, "packages": [] } ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=0
OUT="$(bash "$TOOL" --json "$WORK/proj")"; RC=$?
HUMAN="$(bash "$TOOL" "$WORK/proj")"

assert_eq "$(echo "$OUT" | jq -r '.coverage.covered[]' | grep -c 'bun.lock$')" "1" "bun.lock is covered"
assert_eq "$(echo "$OUT" | jq -r '.coverage.skipped[0].lockfile')" "bun.lockb" "bun.lockb is skipped"
assert_contains "$(echo "$OUT" | jq -r '.coverage.skipped[0].reason')" "regenerate as text bun.lock" "migrate hint present"
assert_contains "$HUMAN" "bun.lockb" "human output surfaces the skipped lockfile"
assert_contains "$HUMAN" "skipped/unsupported" "human output labels the skipped bucket"

finish
