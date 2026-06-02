#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "06-synthesis-status"

TMP="$(mktemp -d -t meeting-synth-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"

assert_eq "$("$MEETING" state "$OUT" | sed -n 's/^synthesis: //p')" "pending" "starts pending"

"$MEETING" advance "$OUT" --synthesis written >/dev/null
assert_eq "$("$MEETING" state "$OUT" | sed -n 's/^synthesis: //p')" "written" "transitions to written"

"$MEETING" advance "$OUT" --synthesis accepted >/dev/null
assert_eq "$("$MEETING" state "$OUT" | sed -n 's/^synthesis: //p')" "accepted" "transitions to accepted"

# invalid status refused
assert_exit 2 "rejects an invalid synthesis status" -- "$MEETING" advance "$OUT" --synthesis maybe

# setting synthesis alone does not bump the turn counter
assert_contains "$OUT" "turn_counter: 0" "synthesis-only advance leaves counter untouched"

finish
