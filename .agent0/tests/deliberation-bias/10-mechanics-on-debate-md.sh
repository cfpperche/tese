#!/usr/bin/env bash
# 149.1 fast-follow: the spec-149 mechanics run on a scaffolded /sdd `debate.md`
# (which now carries a meeting.sh-compatible YAML front-matter), not only on a
# /meeting transcript. Proves `meeting.sh commit/reveal/ledger` work end-to-end
# on a debate.md.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SH="$AGENT0_ROOT/.agent0/skills/meeting/scripts/meeting.sh"
TMPL="$AGENT0_ROOT/.agent0/skills/sdd/templates/debate.md.tmpl"
TMP="$(mktemp -d -t db-10-XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
# simulate the /sdd debate scaffold substitution
sed -e 's/{{NNN}}/199/g' -e 's/{{SLUG}}/demo/g' -e 's/{{DATE}}/2026-01-01/g' \
    -e 's/{{initiating agent name}}/Claude Code/' \
    -e 's/{{runtime or session label}}/Claude Code session/' \
    "$TMPL" > "$TMP/debate.md"
F="$TMP/debate.md"
[ "$(bash "$SH" state "$F" | sed -n 's/^roster: //p')" = "claude,codex,human" ] || { echo "FAIL: meeting.sh cannot read debate.md roster (no front-matter)"; exit 1; }
printf 'A\n' > "$TMP/c.txt"; printf 'B\n' > "$TMP/x.txt"
bash "$SH" commit "$F" --speaker claude --text-file "$TMP/c.txt" >/dev/null || { echo "FAIL: commit on debate.md"; exit 1; }
bash "$SH" commit "$F" --speaker codex  --text-file "$TMP/x.txt" >/dev/null || { echo "FAIL: commit on debate.md"; exit 1; }
bash "$SH" reveal "$F" >/dev/null || { echo "FAIL: reveal on debate.md"; exit 1; }
[ "$(bash "$SH" state "$F" | sed -n 's/^blind_phase: //p')" = "revealed" ] || { echo "FAIL: blind_phase not revealed on debate.md"; exit 1; }
bash "$SH" ledger-add "$F" --claim c --tag supported --anchor "path:README.md" >/dev/null || { echo "FAIL: ledger-add on debate.md"; exit 1; }
bash "$SH" ledger-check "$F" >/dev/null || { echo "FAIL: ledger-check on debate.md"; exit 1; }
echo PASS
