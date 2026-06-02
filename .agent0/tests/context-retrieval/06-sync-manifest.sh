#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SYNC="$ROOT/.agent0/tools/sync-harness.sh"

for needle in \
  '".agent0/tools|*.sh"' \
  '".agent0/tools|context-retrieve-*"' \
  '".agent0/context"'; do
  if ! grep -qF "$needle" "$SYNC"; then
    printf 'FAIL: sync manifest missing context retrieval needle: %s\n' "$needle"
    exit 1
  fi
done

if ! grep -qF '.agent0/.context-index/' "$ROOT/.gitignore"; then
  printf 'FAIL: .agent0/.context-index/ is not gitignored\n'
  exit 1
fi

echo "PASS: 06-sync-manifest"
