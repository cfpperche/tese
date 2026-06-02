#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "03-advance-roundrobin"

TMP="$(mktemp -d -t meeting-advance-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"   # rotation claude,codex ; next claude ; counter 0

"$MEETING" advance "$OUT" --speaker claude >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "codex" "after claude, next is codex"
assert_contains "$OUT" "turn_counter: 1" "counter incremented to 1"

"$MEETING" advance "$OUT" --speaker codex >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "claude" "rotation wraps back to claude"
assert_contains "$OUT" "turn_counter: 2" "counter incremented to 2"

# a human turn bumps the counter but does NOT consume the model rotation slot
"$MEETING" advance "$OUT" --speaker human >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "claude" "human interjection leaves next_speaker unchanged"
assert_contains "$OUT" "turn_counter: 3" "human turn still increments counter"

# unknown speaker refused, no mutation
before="$("$MEETING" state "$OUT")"
assert_exit 3 "advance rejects unknown speaker" -- "$MEETING" advance "$OUT" --speaker mistral
after="$("$MEETING" state "$OUT")"
assert_eq "$after" "$before" "rejected advance left state unchanged"

finish
