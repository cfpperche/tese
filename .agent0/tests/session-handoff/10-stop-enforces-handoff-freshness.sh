#!/usr/bin/env bash
# Scenario 10: Stop freshness targets .agent0/HANDOFF.md.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"
STOP_HOOK="$AGENT0_ROOT/.agent0/hooks/session-stop.sh"
TRACK_HOOK="$AGENT0_ROOT/.agent0/hooks/session-track-edits.sh"

make_repo() {
  local dir="$1"
  mkdir -p "$dir/.claude" "$dir/.agent0"
  cd "$dir"
  git init -q
  git config user.email "test@example.invalid"
  git config user.name "test"
  echo "initial" > tracked.txt
  cat > .agent0/HANDOFF.md <<'EOF'
# Session handoff

initial
EOF
  git add tracked.txt .agent0/HANDOFF.md
  git commit -q -m initial
}

TMP_BLOCK="$(mktemp -d -t spec-092-10-block-XXXXXX)"
TMP_PASS="$(mktemp -d -t spec-092-10-pass-XXXXXX)"
trap 'rm -rf "$TMP_BLOCK" "$TMP_PASS"' EXIT

make_repo "$TMP_BLOCK"
export CLAUDE_PROJECT_DIR="$TMP_BLOCK"
SESSION_ID="test-092-10-block"
stdin_json="{\"source\":\"startup\",\"session_id\":\"$SESSION_ID\"}"
printf '%s' "$stdin_json" | bash "$START_HOOK" >/dev/null 2>&1
sleep 1
echo "dirty" > "$TMP_BLOCK/tracked.txt"
printf '%s' "{\"session_id\":\"$SESSION_ID\",\"tool_input\":{\"file_path\":\"tracked.txt\"}}" | bash "$TRACK_HOOK"
block_output="$(printf '%s' "$stdin_json" | bash "$STOP_HOOK" 2>&1 || true)"

if ! printf '%s' "$block_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop did not block when HANDOFF.md was stale\n%s\n' "$block_output"
  exit 1
fi
if ! printf '%s' "$block_output" | grep -q '.agent0/HANDOFF.md'; then
  printf 'FAIL: Stop block reason did not name .agent0/HANDOFF.md\n%s\n' "$block_output"
  exit 1
fi

make_repo "$TMP_PASS"
export CLAUDE_PROJECT_DIR="$TMP_PASS"
SESSION_ID="test-092-10-pass"
stdin_json="{\"source\":\"startup\",\"session_id\":\"$SESSION_ID\"}"
printf '%s' "$stdin_json" | bash "$START_HOOK" >/dev/null 2>&1
sleep 1
echo "dirty" > "$TMP_PASS/tracked.txt"
printf '%s' "{\"session_id\":\"$SESSION_ID\",\"tool_input\":{\"file_path\":\"tracked.txt\"}}" | bash "$TRACK_HOOK"
cat > "$TMP_PASS/.agent0/HANDOFF.md" <<'EOF'
# Session handoff

updated during session
EOF
pass_output="$(printf '%s' "$stdin_json" | bash "$STOP_HOOK" 2>&1 || true)"

if printf '%s' "$pass_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop blocked even though HANDOFF.md was updated\n%s\n' "$pass_output"
  exit 1
fi

printf 'PASS\n'
exit 0
