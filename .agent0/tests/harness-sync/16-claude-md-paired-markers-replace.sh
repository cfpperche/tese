#!/usr/bin/env bash
# Scenario: paired markers, consumer project's managed block matches the recorded
# baseline (consumer project untouched), Agent0 added a section → STALE → block replaced
# wholesale with no --force. Project sections outside the markers preserved.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-071-16-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"

# Phase 1: SRC region == CONSUMER region {A,B}. --apply records the baseline.
cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

agent0 overview.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

<!-- AGENT0:END -->
EOF

cat > "$CONSUMER/CLAUDE.md" <<'EOF'
# MyConsumer

## Overview

my consumer project overview.

## ProjectStuff

consumer-authored.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

<!-- AGENT0:END -->
EOF

e=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || e=$?
if [ "$e" -ne 0 ]; then
  printf 'FAIL(1): seed --apply expected exit 0, got %d\n' "$e"
  exit 1
fi
if [ ! -f "$CONSUMER/.agent0/harness-sync-baseline.json" ]; then
  printf 'FAIL(1): baseline not recorded by seed --apply\n'
  exit 1
fi

# Phase 2: Agent0 adds ## C to its region. Consumer project region untouched.
cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

agent0 overview.

<!-- AGENT0:BEGIN -->

## A

body of A.

## B

body of B.

## C

body of C.

<!-- AGENT0:END -->
EOF

out="$(mktemp)"
e=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >"$out" 2>&1 || e=$?
if [ "$e" -ne 0 ]; then
  printf 'FAIL(2): stale --apply expected exit 0, got %d\n' "$e"
  cat "$out"
  exit 1
fi
if ! grep -q 'stale CLAUDE.md (managed block' "$out"; then
  printf 'FAIL(2): expected stale managed-block update\n'
  cat "$out"
  exit 1
fi

# Consumer project's region must now contain section C
if ! grep -q '^## C$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: section C not propagated into consumer project region\n'
  cat "$CONSUMER/CLAUDE.md"
  exit 1
fi

# Project-narrative section ProjectStuff preserved (above BEGIN)
if ! grep -q '^## ProjectStuff$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: project section ## ProjectStuff lost\n'
  exit 1
fi

# Consumer project's Overview body preserved verbatim
if ! grep -q '^my consumer project overview\.$' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL: consumer project Overview body overwritten\n'
  exit 1
fi

# Verify ProjectStuff is ABOVE BEGIN marker
begin_line="$(grep -nE '^<!-- AGENT0:BEGIN -->$' "$CONSUMER/CLAUDE.md" | head -1 | cut -d: -f1)"
end_line="$(grep -nE '^<!-- AGENT0:END -->$' "$CONSUMER/CLAUDE.md" | head -1 | cut -d: -f1)"
projectstuff_line="$(grep -n '^## ProjectStuff$' "$CONSUMER/CLAUDE.md" | head -1 | cut -d: -f1)"
if [ "$projectstuff_line" -ge "$begin_line" ]; then
  printf 'FAIL: ## ProjectStuff (line %s) should be above BEGIN (line %s)\n' "$projectstuff_line" "$begin_line"
  exit 1
fi

# Verify A,B,C all inside region (between markers)
for sec in A B C; do
  sec_line="$(grep -n "^## $sec\$" "$CONSUMER/CLAUDE.md" | head -1 | cut -d: -f1)"
  if [ "$sec_line" -le "$begin_line" ] || [ "$sec_line" -ge "$end_line" ]; then
    printf 'FAIL: ## %s (line %s) not inside region [BEGIN=%s, END=%s]\n' "$sec" "$sec_line" "$begin_line" "$end_line"
    exit 1
  fi
done

echo "PASS: 16-claude-md-paired-markers-replace"
