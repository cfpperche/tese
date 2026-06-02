#!/usr/bin/env bash
# Scenario 6: canonical HANDOFF.md is injected for startup and compact sources.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"

TMPDIR="$(mktemp -d -t spec-092-06-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0" "$TMPDIR/.claude"
cat > "$TMPDIR/.agent0/HANDOFF.md" <<'EOF'
# Session handoff

CANONICAL_HANDOFF_SENTINEL
EOF

export CLAUDE_PROJECT_DIR="$TMPDIR"

startup_output="$(printf '%s' '{"source":"startup","session_id":"test-092-06a"}' | bash "$START_HOOK" 2>&1)"
compact_output="$(printf '%s' '{"source":"compact","session_id":"test-092-06b"}' | bash "$START_HOOK" 2>&1)"

for output_name in startup_output compact_output; do
  output="${!output_name}"
  if ! printf '%s' "$output" | grep -q '=== HANDOFF.md (canonical handoff) ==='; then
    printf 'FAIL: %s missing HANDOFF.md opening banner\n%s\n' "$output_name" "$output"
    exit 1
  fi
  if ! printf '%s' "$output" | grep -q 'CANONICAL_HANDOFF_SENTINEL'; then
    printf 'FAIL: %s missing handoff content\n%s\n' "$output_name" "$output"
    exit 1
  fi
  if printf '%s' "$output" | grep -q 'SESSION.md (handoff from prior session)'; then
    printf 'FAIL: %s injected legacy SESSION.md despite hard cutover\n%s\n' "$output_name" "$output"
    exit 1
  fi
done

printf 'PASS\n'
exit 0
