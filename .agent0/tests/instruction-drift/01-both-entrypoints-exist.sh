#!/usr/bin/env bash
# Scenario: missing AGENTS.md is reported as instruction drift.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"

TMPDIR="$(mktemp -d -t instruction-drift-01-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/CLAUDE.md" <<'EOF'
# Claude

<!-- AGENT0:BEGIN -->
shared
<!-- AGENT0:END -->
EOF

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: missing AGENTS.md should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q 'missing AGENTS.md'; then
  printf 'FAIL: expected missing AGENTS.md diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 01-both-entrypoints-exist"
