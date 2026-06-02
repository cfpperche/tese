#!/usr/bin/env bash
# Scenario: CLAUDE.md capacity-section append before Compact Instructions.
# Asserts:
#   (a) missing capacity sections appended
#   (b) consumer-authored sections preserved
#   (c) `## Compact Instructions` remains LAST

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-06-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

# Agent0 CLAUDE.md: Overview, Spec-driven development, Delegation, Runtime introspect, Compact Instructions
cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

base.

## Spec-driven development

sdd.

## Delegation

delegation content.

## Runtime introspect

runtime-introspect content.

## Compact Instructions

compact.
EOF

# Consumer project CLAUDE.md: Overview, CONSUMER-CUSTOM (consumer-authored), Spec-driven development, Compact Instructions
cat > "$CONSUMER/CLAUDE.md" <<'EOF'
# Consumer project

## Overview

consumer project overview.

## CONSUMER-CUSTOM

consumer-authored section.

## Spec-driven development

sdd.

## Compact Instructions

compact.
EOF

printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"

actual_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit 0, got %d\n' "$actual_exit"
  exit 1
fi

# Delegation section must now exist
if ! grep -q '^## Delegation' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: ## Delegation not appended\n'
  cat "$CONSUMER/CLAUDE.md"
  exit 1
fi

# Runtime introspect section must now exist
if ! grep -q '^## Runtime introspect' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: ## Runtime introspect not appended\n'
  exit 1
fi

# CONSUMER-CUSTOM preserved
if ! grep -q '^## CONSUMER-CUSTOM' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: consumer-authored ## CONSUMER-CUSTOM dropped\n'
  exit 1
fi

# Compact Instructions still last
last_h2="$(grep '^## ' "$CONSUMER/CLAUDE.md" | tail -1)"
if [ "$last_h2" != "## Compact Instructions" ]; then
  printf 'FAIL: ## Compact Instructions not last (got: %s)\n' "$last_h2"
  exit 1
fi

echo "PASS: 06-claude-md-section-append"
