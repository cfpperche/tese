#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "07-friction (near-term demand-test measurement)"

TMP="$(mktemp -d -t meeting-friction-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"   # rotation claude,codex

b() { printf 'turn body\n' > "$TMP/b.txt"; "$MEETING" append-turn "$OUT" --speaker "$1" --body-file "$TMP/b.txt" >/dev/null; }
# fval <meeting> <field> → the friction value for that field
fval() { "$MEETING" friction "$1" | sed -n "s/^$2: //p"; }

# fresh meeting: no turns → all zero
assert_eq "$(fval "$OUT" max_consecutive_model_turns)" "0" "no turns → max_consecutive 0"

# 3 model turns in a row (claude, codex, claude), no human between
b claude; b codex; b claude
assert_eq "$(fval "$OUT" model_turns)" "3" "3 model turns counted"
assert_eq "$(fval "$OUT" max_consecutive_model_turns)" "3" "max consecutive model turns = 3"
assert_eq "$(fval "$OUT" current_model_streak)" "3" "current streak = 3"

# a human turn resets the current streak but not the max
b human
assert_eq "$(fval "$OUT" max_consecutive_model_turns)" "3" "human turn leaves max at 3"
assert_eq "$(fval "$OUT" current_model_streak)" "0" "human turn resets current streak to 0"

# two more model turns: streak 2, max still 3
b codex; b claude
assert_eq "$(fval "$OUT" max_consecutive_model_turns)" "3" "max stays 3 after shorter later streak"
assert_eq "$(fval "$OUT" current_model_streak)" "2" "trailing streak = 2"

# state subcommand surfaces the same signal
"$MEETING" state "$OUT" | grep -q '^max_consecutive_model_turns: 3$' && ok "state surfaces max_consecutive_model_turns" || no "state surfaces max_consecutive_model_turns"

# demand-test mechanical threshold (>=4)
OUT2="$(make_meeting "$TMP/m2")"
b2() { printf 'x\n' > "$TMP/b2.txt"; "$MEETING" append-turn "$OUT2" --speaker "$1" --body-file "$TMP/b2.txt" >/dev/null; }
b2 claude; b2 codex; b2 claude; b2 codex
"$MEETING" friction "$OUT2" | grep -q "demand-test (mechanical half): MET" && ok "4 consecutive model turns meets mechanical demand-test" || no "4 consecutive model turns meets mechanical demand-test"
"$MEETING" friction "$OUT" | grep -q "not met" && ok "3 consecutive does not meet mechanical demand-test" || no "3 consecutive does not meet mechanical demand-test"

finish
