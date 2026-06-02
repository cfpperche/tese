#!/usr/bin/env bash
# Canonical motivating case: the consumer project's managed block carries a section
# Agent0 later removed. With the block matching the baseline (consumer project untouched), the
# next sync is STALE → block replaced wholesale → orphan section gone, no --force.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-071-22-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"

# Phase 1: SRC region == CONSUMER region {A, B, D-ORPHAN, C}. --apply seeds the baseline.
cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

placeholder.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

## D-ORPHAN

orphan body — Agent0 still has this title for now.

## C

body of C.

<!-- AGENT0:END -->
EOF

cat > "$CONSUMER/CLAUDE.md" <<'EOF'
# MyConsumer

## Overview

my overview.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

## D-ORPHAN

orphan body — Agent0 still has this title for now.

## C

body of C.

<!-- AGENT0:END -->
EOF

e=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || e=$?
if [ "$e" -ne 0 ]; then
  printf 'FAIL(1): seed --apply expected exit 0, got %d\n' "$e"
  exit 1
fi

# Phase 2: Agent0 removes ## D-ORPHAN. Consumer project region untouched → stale → replace.
cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

placeholder.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

## C

body of C.

<!-- AGENT0:END -->
EOF

err_log="$(mktemp)"
e=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>"$err_log" || e=$?
if [ "$e" -ne 0 ]; then
  printf 'FAIL(2): stale --apply expected exit 0, got %d\n' "$e"
  cat "$err_log"
  exit 1
fi

# Orphan must be gone
if grep -q '^## D-ORPHAN$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: orphan ## D-ORPHAN still present after merge\n'
  cat "$CONSUMER/CLAUDE.md"
  exit 1
fi

# Canonical sections A, B, C must all be present
for sec in A B C; do
  if ! grep -q "^## $sec\$" "$CONSUMER/CLAUDE.md"; then
    printf 'FAIL: canonical section ## %s missing after merge\n' "$sec"
    exit 1
  fi
done

# Consumer project's project section preserved
if ! grep -q 'my overview' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: consumer project project section body lost\n'
  exit 1
fi

# Markers preserved exactly
if ! grep -q '^<!-- AGENT0:BEGIN -->$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: BEGIN marker missing post-merge\n'
  exit 1
fi
if ! grep -q '^<!-- AGENT0:END -->$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: END marker missing post-merge\n'
  exit 1
fi

echo "PASS: 22-claude-md-removes-orphan-section"
