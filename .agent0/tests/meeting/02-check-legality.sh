#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
echo "02-check-membership"

# Spec 140: `check` is demoted from "is this the legal next speaker?" to
# roster-membership-only. There is no longer a round-robin "out of turn"
# rejection — directed speaking is the normal path (the human/marker decides).

TMP="$(mktemp -d -t meeting-check-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(make_meeting "$TMP/m")"   # roster claude,codex,human

assert_exit 0 "check accepts any roster model (claude)"        -- "$MEETING" check "$OUT" claude
assert_exit 0 "check accepts any roster model (codex)"         -- "$MEETING" check "$OUT" codex
assert_exit 0 "check accepts the human"                        -- "$MEETING" check "$OUT" human
assert_exit 3 "check rejects an unknown participant"           -- "$MEETING" check "$OUT" gemini

# in-roster acceptance no longer references a "legal next speaker"
msg="$("$MEETING" check "$OUT" codex 2>&1 || true)"
case "$msg" in
  *"next legal speaker"*) no "membership check dropped the 'next legal speaker' language"; echo "      got: $msg";;
  *) ok "membership check dropped the 'next legal speaker' language";;
esac

finish
