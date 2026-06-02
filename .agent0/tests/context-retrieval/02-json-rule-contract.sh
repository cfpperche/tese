#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$ROOT/.agent0/tools/context-retrieve.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: 02-json-rule-contract (jq missing)"
  exit 0
fi

out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$TOOL" search \
    --query "runtime capabilities codex hooks" \
    --format json \
    --limit 8
)"

if ! printf '%s\n' "$out" | jq -e '
  .cache == "none"
  and any(.candidates[]; .path == ".agent0/context/rules/runtime-capabilities.md"
    and .source_class == "rule"
    and .authority == "authoritative-capsule"
    and (.read_before_acting | contains("Read this rule")))
' >/dev/null; then
  printf 'FAIL: json rule contract missing runtime-capabilities candidate\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-json-rule-contract"
