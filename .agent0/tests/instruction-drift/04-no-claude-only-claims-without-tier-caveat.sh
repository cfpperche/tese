#!/usr/bin/env bash
# Scenario: legacy Codex tier table in AGENTS.md is reported as drift.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../runtime-capabilities/fixtures.sh
. "$SCRIPT_DIR/../runtime-capabilities/fixtures.sh"

TMPDIR="$(mktemp -d -t instruction-drift-04-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

runtime_caps_write_valid_fixture "$TMPDIR"
cat >> "$TMPDIR/AGENTS.md" <<'EOF'

## Codex Capability Tiers

legacy table
EOF

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: legacy Codex tier table should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q "AGENTS.md: legacy '## Codex Capability Tiers' table still present"; then
  printf 'FAIL: expected legacy tier table diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 04-no-legacy-codex-tier-table"
