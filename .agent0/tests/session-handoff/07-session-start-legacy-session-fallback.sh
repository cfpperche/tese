#!/usr/bin/env bash
# Scenario 7: missing HANDOFF.md ignores legacy SESSION.md and emits advisory.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-092-07-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
cat > "$TMPDIR/.claude/SESSION.md" <<'EOF'
# Legacy session

LEGACY_SESSION_SENTINEL
EOF

export CLAUDE_PROJECT_DIR="$TMPDIR"
output="$(printf '%s' '{"source":"startup","session_id":"test-092-07"}' | bash "$START_HOOK" 2>&1)"

if printf '%s' "$output" | grep -q 'LEGACY_SESSION_SENTINEL'; then
  printf 'FAIL: legacy SESSION.md content was injected\n%s\n' "$output"
  exit 1
fi
if printf '%s' "$output" | grep -q '=== SESSION.md (handoff from prior session) ==='; then
  printf 'FAIL: legacy SESSION.md banner emitted\n%s\n' "$output"
  exit 1
fi
if printf '%s' "$output" | grep -q 'migration-advisory'; then
  printf 'FAIL: migration advisory emitted after hard cutover\n%s\n' "$output"
  exit 1
fi
if ! printf '%s' "$output" | grep -q "'.agent0/HANDOFF.md' missing"; then
  printf 'FAIL: missing-handoff advisory not emitted\n%s\n' "$output"
  exit 1
fi

printf 'PASS\n'
exit 0
