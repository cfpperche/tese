#!/usr/bin/env bash
# Scenario: native pre-commit hook blocks staged MEMORY.md projection drift.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TMPDIR="$(mktemp -d -t memory-mr-05-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/memory" "$TMPDIR/.agent0/tools" "$TMPDIR/.githooks" "$TMPDIR/.claude"
cp "$AGENT0_ROOT"/.agent0/tools/memory-* "$TMPDIR/.agent0/tools/"
chmod +x "$TMPDIR"/.agent0/tools/memory-*
cp "$AGENT0_ROOT/.agent0/memory.config.json" "$TMPDIR/.agent0/memory.config.json"
cp "$AGENT0_ROOT/.githooks/pre-commit" "$TMPDIR/.githooks/pre-commit"
chmod +x "$TMPDIR/.githooks/pre-commit"

cat > "$TMPDIR/.agent0/memory/foo.md" <<'EOF'
---
name: Foo
description: Initial entry.
metadata:
  type: project
---
# Foo
EOF

( cd "$TMPDIR" && AGENT0_PROJECT_DIR="$TMPDIR" bash .agent0/tools/memory-project.sh >/dev/null )

( cd "$TMPDIR" && git init -q && git config user.email test@example.com && git config user.name Test && git add . && git commit --no-verify -m initial >/dev/null )

perl -0pi -e 's/Initial entry/Changed entry/' "$TMPDIR/.agent0/memory/foo.md"
( cd "$TMPDIR" && git add .agent0/memory/foo.md )

exit_code=0
out="$(cd "$TMPDIR" && bash .githooks/pre-commit 2>&1)" || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  printf 'FAIL: pre-commit should block stale MEMORY.md\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q 'pre-commit-blocked: MEMORY.md drift detected'; then
  printf 'FAIL: missing drift diagnostic\n%s\n' "$out"
  exit 1
fi

( cd "$TMPDIR" && AGENT0_PROJECT_DIR="$TMPDIR" bash .agent0/tools/memory-maintain.sh finalize .agent0/memory/foo.md >/dev/null 2>&1 && git add .agent0/memory/MEMORY.md )
exit_code=0
out="$(cd "$TMPDIR" && bash .githooks/pre-commit 2>&1)" || exit_code=$?
if [ "$exit_code" -ne 0 ]; then
  printf 'FAIL: pre-commit should pass after projection\n%s\n' "$out"
  exit 1
fi

echo "PASS: 05-precommit-drift-check"
