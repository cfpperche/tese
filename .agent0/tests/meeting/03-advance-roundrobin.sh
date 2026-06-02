#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "03-advance-next"

# Spec 140: advance no longer round-robins. `next_speaker` is a derived default,
# set only by an explicit `--next <id>` (the addressing marker flows through
# append-turn as --next). With no --next, advance leaves next_speaker unchanged.

TMP="$(mktemp -d -t meeting-advance-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"   # rotation claude,codex ; next claude ; counter 0

# advance with no --next: counter bumps, next_speaker is NOT auto-rotated
"$MEETING" advance "$OUT" --speaker claude >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "claude" "no --next: next_speaker unchanged (no auto-rotate)"
assert_contains "$OUT" "turn_counter: 1" "counter incremented to 1"

# advance with --next: next_speaker becomes the directed id
"$MEETING" advance "$OUT" --speaker claude --next codex >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "codex" "--next codex sets next_speaker to codex"
assert_contains "$OUT" "turn_counter: 2" "counter incremented to 2"

# a human turn carrying --next can also direct the floor
"$MEETING" advance "$OUT" --speaker human --next claude >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "claude" "human turn with --next claude directs the floor"
assert_contains "$OUT" "turn_counter: 3" "human turn still increments counter"

# --next to an unknown id is refused with no mutation
before="$("$MEETING" state "$OUT")"
assert_exit 3 "advance rejects unknown --next id" -- "$MEETING" advance "$OUT" --speaker codex --next gemini
after="$("$MEETING" state "$OUT")"
assert_eq "$after" "$before" "rejected --next left state unchanged"

# unknown speaker refused, no mutation
before="$("$MEETING" state "$OUT")"
assert_exit 3 "advance rejects unknown speaker" -- "$MEETING" advance "$OUT" --speaker mistral
after="$("$MEETING" state "$OUT")"
assert_eq "$after" "$before" "rejected advance left state unchanged"

finish
