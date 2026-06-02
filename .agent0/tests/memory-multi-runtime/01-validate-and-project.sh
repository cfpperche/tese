#!/usr/bin/env bash
# Scenario: shared validation primitive emits advisories and projection is deterministic.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TMPDIR="$(mktemp -d -t memory-mr-01-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/memory" "$TMPDIR/.agent0/tools"
cp "$AGENT0_ROOT"/.agent0/tools/memory-* "$TMPDIR/.agent0/tools/"
chmod +x "$TMPDIR"/.agent0/tools/memory-*
cp "$AGENT0_ROOT/.agent0/memory.config.json" "$TMPDIR/.agent0/memory.config.json"

cat > "$TMPDIR/.agent0/memory/foo.md" <<'EOF'
---
name: foo
metadata:
  type: project
---
# Foo
EOF

stderr_capture="$(mktemp -t memory-mr-validate-XXXXXX)"
AGENT0_PROJECT_DIR="$TMPDIR" bash "$TMPDIR/.agent0/tools/memory-maintain.sh" validate "$TMPDIR/.agent0/memory/foo.md" 2>"$stderr_capture"
if ! grep -q "memory-frontmatter-advisory: .agent0/memory/foo.md: missing required field 'description'" "$stderr_capture"; then
  printf 'FAIL: missing expected validation advisory\n'
  cat "$stderr_capture"
  exit 1
fi

cat > "$TMPDIR/.agent0/memory/foo.md" <<'EOF'
---
name: Foo
description: Stable projection test entry.
metadata:
  type: project
---
# Foo
EOF

AGENT0_PROJECT_DIR="$TMPDIR" bash "$TMPDIR/.agent0/tools/memory-project.sh" >/dev/null
expected='- [Foo](foo.md) — Stable projection test entry.'
actual="$(cat "$TMPDIR/.agent0/memory/MEMORY.md")"
if [ "$actual" != "$expected" ]; then
  printf 'FAIL: projection mismatch\nexpected: %s\nactual:   %s\n' "$expected" "$actual"
  exit 1
fi

echo "PASS: 01-validate-and-project"
