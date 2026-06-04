#!/usr/bin/env bash
# check-anchors deterministically verifies `path:` anchors — a present path
# passes (exit 0); a missing path fails (exit 1). "Re-run the test" is v2.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-06-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
bash "$SH" ledger-add "$F" --claim ok --tag supported --anchor "path:.agent0/skills/meeting/scripts/meeting.sh" >/dev/null
rc=0; bash "$SH" check-anchors "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: present path should pass (exit $rc)"; exit 1; }
bash "$SH" ledger-add "$F" --claim bad --tag supported --anchor "path:nope/missing.xyz" >/dev/null
rc=0; bash "$SH" check-anchors "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: missing path should fail (exit $rc want 1)"; exit 1; }
echo PASS
