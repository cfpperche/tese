#!/usr/bin/env bash
# reveal (after all model speakers commit) publishes each opening as a turn and
# flips blind_phase=revealed (critique unlocked).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-02-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
printf 'OPENING_CLAUDE\n' > "$TMP/c.txt"; printf 'OPENING_CODEX\n' > "$TMP/x.txt"
bash "$SH" commit "$F" --speaker claude --text-file "$TMP/c.txt" >/dev/null
bash "$SH" commit "$F" --speaker codex  --text-file "$TMP/x.txt" >/dev/null
bash "$SH" reveal "$F" >/dev/null || { echo "FAIL: reveal errored"; exit 1; }
grep -q 'OPENING_CLAUDE' "$F" && grep -q 'OPENING_CODEX' "$F" || { echo "FAIL: openings not published"; exit 1; }
[ "$(bash "$SH" state "$F" | sed -n 's/^blind_phase: //p')" = "revealed" ] || { echo "FAIL: blind_phase not revealed"; exit 1; }
echo PASS
