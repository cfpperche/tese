#!/usr/bin/env bash
# ab-map emits Proposal A/B labels for both model speakers and records an
# attributed audit line (the critique VIEW is anonymized; the durable transcript
# stays attributed to the runtimes).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-07-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
out="$(bash "$SH" ab-map "$F")"
printf '%s' "$out" | grep -q 'Proposal A=' && printf '%s' "$out" | grep -q 'Proposal B=' || { echo "FAIL: A/B labels missing: $out"; exit 1; }
printf '%s' "$out" | grep -q 'claude' && printf '%s' "$out" | grep -q 'codex' || { echo "FAIL: mapping not attributed to runtimes"; exit 1; }
grep -q '^- ab-map:' "$F" || { echo "FAIL: no ab-map audit row in transcript"; exit 1; }
echo PASS
