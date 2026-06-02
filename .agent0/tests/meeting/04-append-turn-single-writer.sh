#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "04-append-turn-single-writer"

TMP="$(mktemp -d -t meeting-append-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"

printf 'Claude opens: I think we should ship X because of A and B.\n' > "$TMP/body1.txt"
"$MEETING" append-turn "$OUT" --speaker claude --label "Claude Code" --body-file "$TMP/body1.txt" >/dev/null
assert_contains "$OUT" "### Turn 1 — Claude Code (claude)" "turn 1 header written with label+id"
assert_contains "$OUT" "Claude opens:" "turn 1 body appended"
assert_contains "$OUT" "turn_counter: 1" "append advanced the counter"
assert_eq "$("$MEETING" next "$OUT")" "codex" "append advanced next_speaker"

# research-backed turn: require Sources, body without one fails BEFORE writing
printf 'Codex: no citations here.\n' > "$TMP/body2.txt"
before="$(wc -l < "$OUT")"
assert_exit 1 "append-turn --require-sources fails when body lacks Sources:" -- \
  "$MEETING" append-turn "$OUT" --speaker codex --body-file "$TMP/body2.txt" --require-sources
after="$(wc -l < "$OUT")"
assert_eq "$after" "$before" "failed research-turn did not write anything (fail-before-write)"
assert_contains "$OUT" "turn_counter: 1" "failed research-turn did not advance the counter"

# research-backed turn WITH a Sources block succeeds
printf 'Codex: per the docs, Y holds.\nSources:\n- https://example.com/y\n' > "$TMP/body3.txt"
"$MEETING" append-turn "$OUT" --speaker codex --label "Codex CLI" --body-file "$TMP/body3.txt" --require-sources >/dev/null
assert_contains "$OUT" "### Turn 2 — Codex CLI (codex)" "research turn header written"
assert_contains "$OUT" "https://example.com/y" "research turn sources present"
assert_contains "$OUT" "turn_counter: 2" "research turn advanced the counter"

# turns are inserted UNDER ## Transcript — i.e. BEFORE ## Synthesis (synthesis stays last)
turn_line=$(grep -n "### Turn 1 —" "$OUT" | head -1 | cut -d: -f1)
synth_line=$(grep -n "^## Synthesis" "$OUT" | head -1 | cut -d: -f1)
if [ -n "$turn_line" ] && [ -n "$synth_line" ] && [ "$turn_line" -lt "$synth_line" ]; then
  ok "turns appear before the Synthesis section"
else
  no "turns appear before the Synthesis section"; echo "      turn@$turn_line synth@$synth_line"
fi

# unknown speaker refused, no write
before="$(wc -l < "$OUT")"
assert_exit 3 "append-turn rejects unknown speaker" -- \
  "$MEETING" append-turn "$OUT" --speaker llama --body-file "$TMP/body1.txt"
after="$(wc -l < "$OUT")"
assert_eq "$after" "$before" "rejected unknown-speaker append wrote nothing"

finish
