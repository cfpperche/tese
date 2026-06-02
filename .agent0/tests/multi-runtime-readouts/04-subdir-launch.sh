#!/usr/bin/env bash
# Scenario: SessionStart payload cwd inside a subdirectory resolves to git root.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TMPDIR="$(mktemp -d -t multi-readouts-subdir-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

git init -q "$TMPDIR"
mkdir -p \
  "$TMPDIR/apps/web" \
  "$TMPDIR/.agent0/skills/remind/scripts" \
  "$TMPDIR/.agent0/routines" \
  "$TMPDIR/.agent0/.routines-state/weekly/queue"

cp "$AGENT0_ROOT/.agent0/skills/remind/scripts/reminders-helper.py" "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"
chmod +x "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"

cat > "$TMPDIR/.agent0/reminders.yaml" <<'YAML'
reminders:
  - id: r-2026-05-27-subdir-readout
    created: '2026-05-27'
    context: Subdir reminder fixture
    status: pending
YAML

printf '%s\n' '---' 'schedule: "0 9 * * 1"' '---' '# Weekly routine' > "$TMPDIR/.agent0/routines/weekly.md"
oldest="$(( $(date -u +%s) - 120 ))"
printf 'Run weekly fixture\n' > "$TMPDIR/.agent0/.routines-state/weekly/queue/$oldest.md"

payload="$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$TMPDIR/apps/web")"

reminders_out="$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR -u AGENT0_PROJECT_DIR bash "$AGENT0_ROOT/.agent0/hooks/reminders-readout.sh")"
routines_out="$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR -u AGENT0_PROJECT_DIR bash "$AGENT0_ROOT/.agent0/hooks/routines-readout.sh")"

if ! printf '%s\n' "$reminders_out" | grep -q 'Subdir reminder fixture'; then
  printf 'FAIL: reminders did not resolve git root\n%s\n' "$reminders_out"
  exit 1
fi
if ! printf '%s\n' "$routines_out" | grep -q 'weekly: 1 pending'; then
  printf 'FAIL: routines did not resolve git root\n%s\n' "$routines_out"
  exit 1
fi

echo "PASS: 04-subdir-launch"
