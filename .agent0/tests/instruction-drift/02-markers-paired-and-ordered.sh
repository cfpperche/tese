#!/usr/bin/env bash
# Scenario: invalid AGENT0 marker state is reported.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/check-instruction-drift.sh"

TMPDIR="$(mktemp -d -t instruction-drift-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/CLAUDE.md" <<'EOF'
# Claude

<!-- AGENT0:BEGIN -->
shared
<!-- AGENT0:END -->
EOF

cat > "$TMPDIR/AGENTS.md" <<'EOF'
# Agents

native-now
manual/read-only-now
Claude-only-until-follow-up

<!-- AGENT0:BEGIN -->
shared
EOF

actual_exit=0
out="$(bash "$TOOL" --root "$TMPDIR" --skip-sync-check 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: mismatched markers should fail\n%s\n' "$out"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q 'AGENTS.md marker state is mismatched'; then
  printf 'FAIL: expected AGENTS.md mismatched marker diagnostic\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-markers-paired-and-ordered"
