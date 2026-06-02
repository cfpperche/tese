#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "01-init"

TMP="$(mktemp -d -t meeting-init-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

OUT="$(make_meeting "$TMP/m")"
assert_file "$OUT" "init writes meeting.md"
assert_eq "$OUT" "$TMP/m/meeting.md" "init echoes the path"

# Header is filled, no placeholders remain
if grep -q '{{' "$OUT"; then no "no template placeholders remain"; grep -n '{{' "$OUT"; else ok "no template placeholders remain"; fi

assert_contains "$OUT" "meeting: demo" "slug substituted"
assert_contains "$OUT" 'topic: "Should we ship X: a test"' "colon-bearing topic survives quoting"
assert_contains "$OUT" "roster: claude,codex,human" "roster set"
assert_contains "$OUT" "rotation: claude,codex" "rotation set"
assert_contains "$OUT" "turn_counter: 0" "counter starts at 0"
assert_contains "$OUT" "next_speaker: claude" "next_speaker defaults to first in rotation"
assert_contains "$OUT" "synthesis: pending" "synthesis starts pending"

# init refuses to clobber
assert_exit 2 "init refuses to overwrite existing meeting.md" -- \
  "$MEETING" init --dir "$TMP/m" --slug demo --topic t --convener claude --roster a --rotation a

finish
