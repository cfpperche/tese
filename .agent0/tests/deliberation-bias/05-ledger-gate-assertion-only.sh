#!/usr/bin/env bash
# ledger-check is the convergence GATE: any assertion-only claim → exit 1 (that
# point is UNRESOLVED regardless of agreement). A ledger with external anchors → exit 0.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMP="$(mktemp -d -t db-05-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
bash "$SH" init --dir "$TMP/m" --slug demo --topic t --convener claude \
  --roster "claude,codex,human" --rotation "claude,codex" --tier decision-grade >/dev/null
F="$TMP/m/meeting.md"
bash "$SH" ledger-add "$F" --claim "supported one" --tag supported --anchor "path:README.md" >/dev/null
rc=0; bash "$SH" ledger-check "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: clean ledger should pass (exit $rc)"; exit 1; }
bash "$SH" ledger-add "$F" --claim "echo agreement" --tag assertion-only --anchor "(none)" >/dev/null
rc=0; bash "$SH" ledger-check "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: assertion-only should gate (exit $rc want 1)"; exit 1; }
echo PASS
