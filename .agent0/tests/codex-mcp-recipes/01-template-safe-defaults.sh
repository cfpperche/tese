#!/usr/bin/env bash
# Scenario: Codex MCP template is present, inert by default, and secret-safe.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TEMPLATE="$AGENT0_ROOT/.codex/config.toml.example"

if [ ! -f "$TEMPLATE" ]; then
  printf 'FAIL: missing %s\n' "$TEMPLATE"
  exit 1
fi

if ! grep -Fxq '.codex/.env.local' "$AGENT0_ROOT/.gitignore"; then
  printf 'FAIL: .codex/.env.local is not gitignored\n'
  exit 1
fi

ids=(playwright chrome-devtools dbhub laravel-boost next-devtools fal-ai)
for id in "${ids[@]}"; do
  count="$(grep -Fxc "[mcp_servers.$id]" "$TEMPLATE" || true)"
  if [ "$count" -ne 1 ]; then
    printf 'FAIL: expected one [mcp_servers.%s] block, got %s\n' "$id" "$count"
    exit 1
  fi
done

enabled_false_count="$(grep -c '^enabled = false$' "$TEMPLATE" || true)"
if [ "$enabled_false_count" -ne "${#ids[@]}" ]; then
  printf 'FAIL: expected %d disabled recipe blocks, got %s\n' "${#ids[@]}" "$enabled_false_count"
  exit 1
fi

if grep -Eq 'Authorization|postgres://|mysql://|password|sk-[A-Za-z0-9]' "$TEMPLATE"; then
  printf 'FAIL: template contains a credential-like literal or static auth header\n'
  exit 1
fi

if ! grep -Fxq 'env_vars = ["DATABASE_URL"]' "$TEMPLATE"; then
  printf 'FAIL: DBHub does not use DATABASE_URL env_vars indirection\n'
  exit 1
fi

if ! grep -Fxq 'bearer_token_env_var = "FAL_KEY"' "$TEMPLATE"; then
  printf 'FAIL: fal-ai does not use bearer_token_env_var indirection\n'
  exit 1
fi

echo "PASS: 01-template-safe-defaults"
