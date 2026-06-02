#!/usr/bin/env bash
# Scenario 1: Codex-shaped SessionStart injects canonical HANDOFF.md as plain stdout.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-101-01-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.invalid"
git config user.name "test"
mkdir -p "$TMPDIR/.agent0"
cat > "$TMPDIR/.agent0/HANDOFF.md" <<'EOF'
# Handoff

Codex startup handoff content.
EOF
git add .agent0/HANDOFF.md
git commit -q -m initial

SESSION_ID="codex-start-01"
payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" '{
  hook_event_name: "SessionStart",
  source: "startup",
  session_id: $sid,
  cwd: $cwd
}')"

output="$(printf '%s' "$payload" | bash "$START_HOOK")"

if ! printf '%s' "$output" | grep -q '=== HANDOFF.md (canonical handoff) ==='; then
  printf 'FAIL: Codex SessionStart did not emit HANDOFF banner\n%s\n' "$output"
  exit 1
fi

if ! printf '%s' "$output" | grep -q 'Codex startup handoff content.'; then
  printf 'FAIL: Codex SessionStart did not include HANDOFF.md content\n%s\n' "$output"
  exit 1
fi

if printf '%s' "$output" | grep -q 'hookSpecificOutput'; then
  printf 'FAIL: Codex SessionStart emitted Claude JSON envelope\n%s\n' "$output"
  exit 1
fi

if [ ! -f "$TMPDIR/.agent0/.session-state/$SESSION_ID/started-at" ]; then
  printf 'FAIL: SessionStart did not create root session-state marker\n'
  exit 1
fi

printf 'PASS\n'
exit 0
