#!/usr/bin/env bash
# Scenario: non-identical managed blocks are reported.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"

TMPDIR="$(mktemp -d -t instruction-drift-03-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/CLAUDE.md" <<'EOF'
# Claude

<!-- AGENT0:BEGIN -->
shared-a
<!-- AGENT0:END -->
EOF

cat > "$TMPDIR/AGENTS.md" <<'EOF'
# Agents

native-now
manual/read-only-now
Claude-only-until-follow-up

<!-- AGENT0:BEGIN -->
shared-b
<!-- AGENT0:END -->
EOF

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: differing managed blocks should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q 'managed blocks differ'; then
  printf 'FAIL: expected managed blocks differ diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 03-managed-blocks-byte-equal"
