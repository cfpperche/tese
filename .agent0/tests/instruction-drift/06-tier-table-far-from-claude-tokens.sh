#!/usr/bin/env bash
# Scenario: registry pointer covers Claude-only tokens far from the managed block.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../runtime-capabilities/fixtures.sh
. "$SCRIPT_DIR/../runtime-capabilities/fixtures.sh"

TMPDIR="$(mktemp -d -t instruction-drift-06-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

runtime_caps_write_valid_fixture "$TMPDIR"
cat >> "$TMPDIR/AGENTS.md" <<'EOF'

## Later Section

Line 01.
Line 02.
Line 03.
Line 04.
Line 05.
Line 06.
Line 07.
Line 08.
Line 09.
Line 10.
Line 11.
Line 12.

Run /sdd for spec-driven work.
EOF

out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)"

if ! printf '%s\n' "$out" | grep -q 'runtime capability registry anchor checks passed'; then
  printf 'FAIL: expected runtime capability registry anchor pass diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 06-registry-pointer-far-from-claude-tokens"
