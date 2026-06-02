#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SYNC="$ROOT/.agent0/tools/sync-harness.sh"

if ! grep -qF '".agent0/context"' "$SYNC"; then
  printf 'FAIL: sync manifest does not include .agent0/context\n'
  exit 1
fi

if ! grep -qF '".codex/hooks.json"' "$SYNC"; then
  printf 'FAIL: sync manifest does not include .codex/hooks.json\n'
  exit 1
fi

if grep -qF '".claude/rules|*.md"' "$SYNC"; then
  printf 'FAIL: sync manifest still ships .claude/rules markdown\n'
  exit 1
fi

echo "PASS: 07-sync-manifest"
