#!/usr/bin/env bash
# Scenario 4: Codex-shaped hooks resolve cwd subdirectories to the git root.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-101-04-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.invalid"
git config user.name "test"
mkdir -p "$TMPDIR/.agent0" "$TMPDIR/apps/web"
printf 'Root handoff from subdir.\n' > "$TMPDIR/.agent0/HANDOFF.md"
git add .agent0/HANDOFF.md
git commit -q -m initial

SESSION_ID="codex-subdir-04"
payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR/apps/web" '{
  hook_event_name: "SessionStart",
  source: "startup",
  session_id: $sid,
  cwd: $cwd
}')"

output="$(printf '%s' "$payload" | bash "$START_HOOK")"

if ! printf '%s' "$output" | grep -q 'Root handoff from subdir.'; then
  printf 'FAIL: SessionStart from subdir did not read root HANDOFF.md\n%s\n' "$output"
  exit 1
fi

if [ ! -f "$TMPDIR/.agent0/.session-state/$SESSION_ID/started-at" ]; then
  printf 'FAIL: root session-state marker missing\n'
  exit 1
fi

if [ -e "$TMPDIR/apps/web/.agent0/.session-state/$SESSION_ID/started-at" ]; then
  printf 'FAIL: SessionStart wrote session state under cwd subdirectory\n'
  exit 1
fi

printf 'PASS\n'
exit 0
