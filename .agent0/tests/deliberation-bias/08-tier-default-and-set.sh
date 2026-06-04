#!/usr/bin/env bash
# init defaults to tier=light; --tier decision-grade is honored; a bogus tier is
# a usage error. (Light-tier orchestration skips the blind phase by convention;
# the field is the signal the SKILL reads.)
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-08-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/lite" --slug l --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" >/dev/null
[ "$(bash "$SH" state "$TMP/lite/meeting.md" | sed -n 's/^tier: //p')" = "light" ] || { echo "FAIL: default tier not light"; exit 1; }
bash "$SH" init --dir "$TMP/dg" --slug d --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
[ "$(bash "$SH" state "$TMP/dg/meeting.md" | sed -n 's/^tier: //p')" = "decision-grade" ] || { echo "FAIL: --tier not honored"; exit 1; }
rc=0; bash "$SH" init --dir "$TMP/bad" --slug b --topic t --convener claude \
  --roster "claude,human" --rotation "claude" --tier bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: bad tier should be usage error (exit $rc want 2)"; exit 1; }
echo PASS
