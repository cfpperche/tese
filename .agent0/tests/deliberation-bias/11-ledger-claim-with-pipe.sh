#!/usr/bin/env bash
# 149.1 fast-follow: a ledger claim containing a literal '|' must NOT corrupt the
# markdown-table column parse used by ledger-check / check-anchors. ledger-add
# sanitizes '|' → '/', so the row keeps exactly 3 columns and the anchor in col 4
# is read correctly.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-11-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
# claim with literal pipes (e.g. a terminal-state enumeration)
bash "$SH" ledger-add "$F" --claim "states: budget|repairs|conflict" --tag supported --anchor "path:README.md" >/dev/null
bash "$SH" ledger-check "$F" >/dev/null || { echo "FAIL: ledger-check choked on a piped claim"; exit 1; }
# check-anchors must still verify the path: anchor (not see a split fragment as an anchor)
out="$(bash "$SH" check-anchors "$F" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: check-anchors exit=$rc on piped claim"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -q '^ok   path README.md' || { echo "FAIL: anchor not verified through a piped claim"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -qiE 'unverified (budget|repairs|conflict)' && { echo "FAIL: a pipe fragment leaked as an anchor"; exit 1; }
echo PASS
