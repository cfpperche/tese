#!/usr/bin/env bash
# commit seals the opening (gitignored) and records a hash row; the opening TEXT
# is NOT written to the transcript, so a peer prompt built from it stays blind.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-01-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
printf 'CLAUDE_SECRET_OPENING\n' > "$TMP/c.txt"
bash "$SH" commit "$F" --speaker claude --text-file "$TMP/c.txt" >/dev/null
grep -q 'CLAUDE_SECRET_OPENING' "$F" && { echo "FAIL: opening text leaked into transcript"; exit 1; }
grep -q '^## Blind submissions' "$F" || { echo "FAIL: no blind-submissions section"; exit 1; }
grep -q 'commit claude' "$F" || { echo "FAIL: no commitment audit row"; exit 1; }
echo PASS
