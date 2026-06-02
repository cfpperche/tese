#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "08-addressing-marker"

# Spec 140: context-driven speaker selection via an explicit trailing
# `Next: <roster-id>` directive (exact match only, never NLP), plus the
# `resolve-speaker` precedence contract.

TMP="$(mktemp -d -t meeting-marker-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ── marker happy path ────────────────────────────────────────────────────────
OUT="$(make_meeting "$TMP/m")"   # roster claude,codex,human ; rotation claude,codex ; next claude
printf 'Claude opens. @codex is mentioned in prose and must NOT steer.\n\nNext: codex\n' > "$TMP/b1.txt"
"$MEETING" append-turn "$OUT" --speaker claude --label "Claude Code" --body-file "$TMP/b1.txt" >/dev/null
assert_eq "$("$MEETING" next "$OUT")" "codex" "trailing 'Next: codex' sets next_speaker=codex"
assert_eq "$("$MEETING" resolve-speaker "$OUT")" "codex" "resolve-speaker (no --speaker) returns the addressed id"
assert_contains "$OUT" "Next: codex" "marker line left VISIBLE in the transcript"
# the prose '@codex' mention is present but did not drive state (codex came from the marker, not the @)
assert_contains "$OUT" "@codex is mentioned" "prose body preserved verbatim"

# ── no marker: next_speaker unchanged ────────────────────────────────────────
OUT2="$(make_meeting "$TMP/m2")"   # next claude
printf 'Claude speaks with no trailing directive at all.\n' > "$TMP/b2.txt"
"$MEETING" append-turn "$OUT2" --speaker claude --body-file "$TMP/b2.txt" >/dev/null
assert_eq "$("$MEETING" next "$OUT2")" "claude" "no marker → next_speaker unchanged"

# ── malformed final line is treated as no marker ─────────────────────────────
OUT3="$(make_meeting "$TMP/m3")"   # next claude
printf 'A turn whose last line mentions Next but is not the directive shape.\nNextSteps: think about it\n' > "$TMP/b3.txt"
"$MEETING" append-turn "$OUT3" --speaker claude --body-file "$TMP/b3.txt" >/dev/null
assert_eq "$("$MEETING" next "$OUT3")" "claude" "malformed final line (not 'Next:') → no marker, unchanged"

# ── invalid marker (non-roster id) fails BEFORE write ────────────────────────
OUT4="$(make_meeting "$TMP/m4")"
printf 'Claude tries to hand off to a non-participant.\n\nNext: gemini\n' > "$TMP/b4.txt"
before_lines="$(wc -l < "$OUT4")"
before_state="$("$MEETING" state "$OUT4")"
assert_exit 3 "append-turn with non-roster 'Next: gemini' is refused" -- \
  "$MEETING" append-turn "$OUT4" --speaker claude --body-file "$TMP/b4.txt"
after_lines="$(wc -l < "$OUT4")"
after_state="$("$MEETING" state "$OUT4")"
assert_eq "$after_lines" "$before_lines" "refused bad-marker append wrote nothing (fail-before-write)"
assert_eq "$after_state" "$before_state" "refused bad-marker append did not mutate the header"

# ── empty marker ('Next:' with no id) is also a bad directive ────────────────
OUT5="$(make_meeting "$TMP/m5")"
printf 'Empty directive.\n\nNext:\n' > "$TMP/b5.txt"
before_lines="$(wc -l < "$OUT5")"
assert_exit 3 "append-turn with empty 'Next:' is refused" -- \
  "$MEETING" append-turn "$OUT5" --speaker claude --body-file "$TMP/b5.txt"
assert_eq "$(wc -l < "$OUT5")" "$before_lines" "refused empty-marker append wrote nothing"

# ── resolve-speaker precedence ───────────────────────────────────────────────
OUT6="$(make_meeting "$TMP/m6")"   # next_speaker = claude (first rotation model) ; convener claude
assert_eq "$("$MEETING" resolve-speaker "$OUT6" --speaker codex)" "codex" "precedence: --speaker wins"
assert_eq "$("$MEETING" resolve-speaker "$OUT6")" "claude" "precedence: falls back to next_speaker header"
assert_exit 3 "resolve-speaker --speaker rejects a non-roster id" -- "$MEETING" resolve-speaker "$OUT6" --speaker gemini

# stale/non-roster next_speaker is skipped → first rotation model
"$MEETING" advance "$OUT6" --synthesis pending >/dev/null  # no-op touch to ensure file mutable
# hand-corrupt next_speaker to a non-roster value, then confirm resolve-speaker skips it
sed -i 's/^next_speaker:.*/next_speaker: gemini/' "$OUT6"
resolved="$("$MEETING" resolve-speaker "$OUT6")"
case "$resolved" in
  claude) ok "stale non-roster next_speaker skipped → first rotation model (claude)";;
  *) no "stale non-roster next_speaker skipped → first rotation model (claude)"; echo "      got: $resolved";;
esac

finish
