#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"

if find "$ROOT/.claude/rules" -type f -name '*.md' 2>/dev/null | grep -q .; then
  printf 'FAIL: .claude/rules still contains markdown files\n'
  find "$ROOT/.claude/rules" -type f -name '*.md' 2>/dev/null
  exit 1
fi

for f in spec-driven.md runtime-capabilities.md harness-sync.md; do
  if [ ! -f "$ROOT/.agent0/context/rules/$f" ]; then
    printf 'FAIL: missing context rule %s\n' "$f"
    exit 1
  fi
done

echo "PASS: 01-no-claude-rules"
