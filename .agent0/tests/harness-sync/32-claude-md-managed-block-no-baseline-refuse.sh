#!/usr/bin/env bash
# Scenario: paired markers, managed block differs from Agent0, but the
# consumer project has NO recorded baseline (a pre-071 consumer project's first sync). stale-vs-customized
# is unknowable with no history → refuse as `customized (no baseline)`; --force
# overrides. The one-time first-sync friction, mirroring the plain-file path.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-071-32-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"

cat > "$SRC/CLAUDE.md" <<'EOF'
# Agent0

## Overview

placeholder.

<!-- AGENT0:BEGIN -->

## A

agent0 body of A.

<!-- AGENT0:END -->
EOF

cat > "$CONSUMER/CLAUDE.md" <<'EOF'
# MyConsumer

## Overview

consumer project overview.

<!-- AGENT0:BEGIN -->

## A

stale consumer project body of A.

<!-- AGENT0:END -->
EOF

# Deliberately NO .agent0/harness-sync-baseline.json — consumer project never synced under
# the baseline mechanism.

# Phase 1: --apply (no --force) → refuse, customized (no baseline).
err1="$(mktemp)"
exit1=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>"$err1" || exit1=$?
if [ "$exit1" -eq 0 ]; then
  printf 'FAIL(1): no-baseline managed block should refuse without --force\n'
  exit 1
fi
if ! grep -q 'managed block customized (no baseline)' "$err1"; then
  printf 'FAIL(1): stderr missing "managed block customized (no baseline)"\n'
  cat "$err1"
  exit 1
fi
if ! grep -q 'stale consumer project body of A' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL(1): consumer project block changed despite refuse\n'
  exit 1
fi

# Phase 2: --apply --force → block replaced wholesale.
err2="$(mktemp)"
exit2=0
bash "$TOOL" --apply --force --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>"$err2" || exit2=$?
if [ "$exit2" -ne 0 ]; then
  printf 'FAIL(2): --force expected exit 0, got %d\n' "$exit2"
  cat "$err2"
  exit 1
fi
if ! grep -q 'agent0 body of A' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL(2): Agent0 block not propagated under --force\n'
  exit 1
fi
if grep -q 'stale consumer project body of A' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL(2): stale consumer project body should be overwritten under --force\n'
  exit 1
fi
if ! grep -q 'consumer project overview' "$CONSUMER/CLAUDE.md"; then
  printf 'FAIL(2): consumer project Overview lost\n'
  exit 1
fi

echo "PASS: 32-claude-md-managed-block-no-baseline-refuse"
