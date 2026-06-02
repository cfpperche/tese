#!/usr/bin/env bash
# Scenario: out-of-scope files never touched.
# Asserts:
#   (a) src/, tests/, docs/, package.json, Cargo.toml, pyproject.toml, .mcp.json all byte-identical post-apply
#   (b) nothing under those paths appears in any decision line

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-08-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude" "$CONSUMER/src" "$CONSUMER/tests" "$CONSUMER/docs"

printf '#!/usr/bin/env bash\necho new\n' > "$SRC/.claude/hooks/newhook.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/newhook.sh"

printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

# Out-of-scope content with sentinel markers
printf 'export const main = () => "PRODUCT-CODE-MARKER";\n' > "$CONSUMER/src/main.ts"
printf 'describe("integration", () => "CONSUMER-TEST-MARKER");\n' > "$CONSUMER/tests/integration.test.ts"
printf '# CONSUMER-DOC-MARKER\n' > "$CONSUMER/docs/README.md"
printf '{"name":"PRODUCT-PACKAGE","version":"1.0.0"}\n' > "$CONSUMER/package.json"
printf '[package]\nname = "PRODUCT-CARGO"\n' > "$CONSUMER/Cargo.toml"
printf '[project]\nname = "PRODUCT-PYPROJECT"\n' > "$CONSUMER/pyproject.toml"
printf '{"mcpServers":{"local":"CONSUMER-MCP-MARKER"}}\n' > "$CONSUMER/.mcp.json"

pre_shas="$(find "$CONSUMER/src" "$CONSUMER/tests" "$CONSUMER/docs" "$CONSUMER/package.json" "$CONSUMER/Cargo.toml" "$CONSUMER/pyproject.toml" "$CONSUMER/.mcp.json" -type f -exec sha256sum {} \; | sort)"

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit 0, got %d\n%s\n' "$actual_exit" "$out"
  exit 1
fi

post_shas="$(find "$CONSUMER/src" "$CONSUMER/tests" "$CONSUMER/docs" "$CONSUMER/package.json" "$CONSUMER/Cargo.toml" "$CONSUMER/pyproject.toml" "$CONSUMER/.mcp.json" -type f -exec sha256sum {} \; | sort)"

if [ "$pre_shas" != "$post_shas" ]; then
  printf 'FAIL: out-of-scope files modified\n'
  diff <(printf '%s\n' "$pre_shas") <(printf '%s\n' "$post_shas") || true
  exit 1
fi

# Decision output must NOT name out-of-scope paths
if printf '%s' "$out" | grep -qE '(main\.ts|integration\.test\.ts|package\.json|Cargo\.toml|pyproject\.toml|/\.mcp\.json[^.])'; then
  printf 'FAIL: decision output mentions out-of-scope path\n%s\n' "$out"
  exit 1
fi

echo "PASS: 08-out-of-scope-untouched"
