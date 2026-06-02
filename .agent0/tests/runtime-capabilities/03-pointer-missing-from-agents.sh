#!/usr/bin/env bash
# Scenario: AGENTS.md managed block must point to the registry.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=fixtures.sh
. "$SCRIPT_DIR/fixtures.sh"

TMPDIR="$(mktemp -d -t runtime-capabilities-03-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

runtime_caps_write_valid_fixture "$TMPDIR"
perl -0pi -e 's#See `\.agent0/context/rules/runtime-capabilities\.md`\.\n#No registry pointer here.\n#' "$TMPDIR/AGENTS.md"

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: missing AGENTS.md pointer should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q 'AGENTS.md: managed block missing registry pointer'; then
  printf 'FAIL: expected AGENTS.md pointer diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 03-pointer-missing-from-agents"
