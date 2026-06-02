#!/usr/bin/env bash
# Scenario 8: pointer-only SESSION.md is ignored after hard cutover.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-092-08-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
cat > "$TMPDIR/.claude/SESSION.md" <<'EOF'
<!-- AGENT0_HANDOFF_POINTER -->

This file moved. Current handoff: `.agent0/HANDOFF.md`.
LEGACY_POINTER_SENTINEL_SHOULD_NOT_APPEAR
EOF

export CLAUDE_PROJECT_DIR="$TMPDIR"
output="$(printf '%s' '{"source":"startup","session_id":"test-092-08"}' | bash "$START_HOOK" 2>&1)"

if printf '%s' "$output" | grep -q 'LEGACY_POINTER_SENTINEL_SHOULD_NOT_APPEAR'; then
  printf 'FAIL: pointer-only SESSION.md was injected as legacy content\n%s\n' "$output"
  exit 1
fi
if printf '%s' "$output" | grep -q '=== SESSION.md (handoff from prior session) ==='; then
  printf 'FAIL: legacy SESSION.md banner emitted for pointer file\n%s\n' "$output"
  exit 1
fi
if ! printf '%s' "$output" | grep -q "'.agent0/HANDOFF.md' missing"; then
  printf 'FAIL: missing-handoff advisory not emitted\n%s\n' "$output"
  exit 1
fi

printf 'PASS\n'
exit 0
