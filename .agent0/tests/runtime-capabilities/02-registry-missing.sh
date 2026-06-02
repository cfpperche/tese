#!/usr/bin/env bash
# Scenario: missing registry file is reported.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=fixtures.sh
. "$SCRIPT_DIR/fixtures.sh"

TMPDIR="$(mktemp -d -t runtime-capabilities-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

runtime_caps_write_valid_fixture "$TMPDIR"
rm -f "$TMPDIR/.agent0/context/rules/runtime-capabilities.md"

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: missing registry should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q 'registry file missing: .agent0/context/rules/runtime-capabilities.md'; then
  printf 'FAIL: expected missing registry diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-registry-missing"
