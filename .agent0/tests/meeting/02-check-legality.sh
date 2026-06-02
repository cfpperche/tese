#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "02-check-legality"

TMP="$(mktemp -d -t meeting-check-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"   # next_speaker = claude

assert_exit 0 "check accepts the next speaker (claude)"        -- "$MEETING" check "$OUT" claude
assert_exit 1 "check rejects a model out of turn (codex)"      -- "$MEETING" check "$OUT" codex
assert_exit 0 "check always allows the human to interject"     -- "$MEETING" check "$OUT" human
assert_exit 3 "check rejects an unknown participant"           -- "$MEETING" check "$OUT" gemini

# the rejection message names the legal next speaker
msg="$("$MEETING" check "$OUT" codex 2>&1 || true)"
case "$msg" in *"next legal speaker is 'claude'"*) ok "rejection names the legal next speaker";; *) no "rejection names the legal next speaker"; echo "      got: $msg";; esac

finish
