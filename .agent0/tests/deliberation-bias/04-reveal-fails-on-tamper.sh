#!/usr/bin/env bash
# If a sealed opening is altered after commit, reveal detects the hash mismatch
# and refuses (the commitment is tamper-evidence).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-04-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
printf 'c\n' > "$TMP/c.txt"; printf 'x\n' > "$TMP/x.txt"
bash "$SH" commit "$F" --speaker claude --text-file "$TMP/c.txt" >/dev/null
bash "$SH" commit "$F" --speaker codex  --text-file "$TMP/x.txt" >/dev/null
key="$(printf '%s' "$(cd "$TMP/m" && pwd)/meeting.md" | sha256sum | cut -c1-16)"
printf 'TAMPERED\n' > "$TMP/.agent0/.runtime-state/deliberation/$key/openings/codex.txt"
rc=0; bash "$SH" reveal "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: tampered reveal exit=$rc want 1"; exit 1; }
echo PASS
