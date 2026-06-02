#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "05-state-readout (fresh-runtime reads header alone)"

TMP="$(mktemp -d -t meeting-state-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"

# A "fresh runtime" parses ONLY the header output to learn whose turn is legal.
st="$("$MEETING" state "$OUT")"
echo "$st" | grep -q '^next_speaker: claude$' && ok "state exposes next_speaker" || no "state exposes next_speaker"
echo "$st" | grep -q '^mode: human-orchestrated$' && ok "state exposes mode" || no "state exposes mode"
echo "$st" | grep -q '^synthesis: pending$' && ok "state exposes synthesis status" || no "state exposes synthesis status"
echo "$st" | grep -q '^roster: claude,codex,human$' && ok "state exposes roster" || no "state exposes roster"

# The readout is line-oriented key: value (machine-parseable)
nfields="$(echo "$st" | grep -c ': ')"
[ "$nfields" -ge 8 ] && ok "state emits >=8 parseable fields ($nfields)" || no "state emits >=8 parseable fields ($nfields)"

# next subcommand agrees with the header
assert_eq "$("$MEETING" next "$OUT")" "claude" "next agrees with header"

finish
