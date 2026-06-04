#!/usr/bin/env bash
# reveal refuses (exit 1) until every model speaker has committed — the
# mechanical blindness guard (prevents revealing A before B has committed).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-03-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
printf 'only-claude\n' > "$TMP/c.txt"
bash "$SH" commit "$F" --speaker claude --text-file "$TMP/c.txt" >/dev/null
rc=0; bash "$SH" reveal "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: reveal exit=$rc want 1"; exit 1; }
[ "$(bash "$SH" state "$F" | sed -n 's/^blind_phase: //p')" = "open" ] || { echo "FAIL: phase advanced despite refusal"; exit 1; }
echo PASS
