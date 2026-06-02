#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TMPDIR="$(mktemp -d -t context-retrieve-memory-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/tools" "$TMPDIR/.agent0/memory"
ln -s "$ROOT/.agent0/tools/context-retrieve.sh" "$TMPDIR/.agent0/tools/context-retrieve.sh"
ln -s "$ROOT/.agent0/tools/context-retrieve-helper.py" "$TMPDIR/.agent0/tools/context-retrieve-helper.py"

cat > "$TMPDIR/.agent0/memory/MEMORY.md" <<'EOF'
- [Projected memory](projected-memory.md) — projected adapter visible phrase
EOF

cat > "$TMPDIR/.agent0/memory/projected-memory.md" <<'EOF'
---
name: projected-memory
description: projected adapter visible phrase
metadata:
  type: project
  created_at: '2026-05-31'
  last_accessed: '2026-05-31'
  confirmed_count: 0
---
# Projected memory

body-only-secret-token-should-not-rank
EOF

visible="$(
  AGENT0_PROJECT_DIR="$TMPDIR" bash "$TMPDIR/.agent0/tools/context-retrieve.sh" search \
    --query "projected adapter visible" \
    --format text
)"

if ! printf '%s\n' "$visible" | grep -qF ".agent0/memory/projected-memory.md [memory; evidence-pointer"; then
  printf 'FAIL: projected MEMORY.md text did not produce memory candidate\n%s\n' "$visible"
  exit 1
fi

hidden="$(
  AGENT0_PROJECT_DIR="$TMPDIR" bash "$TMPDIR/.agent0/tools/context-retrieve.sh" search \
    --query "body-only-secret-token-should-not-rank" \
    --format text
)"

if printf '%s\n' "$hidden" | grep -qF ".agent0/memory/projected-memory.md"; then
  printf 'FAIL: memory body-only token was indexed; memory must stay adapter-backed\n%s\n' "$hidden"
  exit 1
fi

echo "PASS: 05-memory-adapter-no-body-index"
