#!/usr/bin/env bash
# Scenario: SessionStart decay hook emits the framed readout from .agent0/memory.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/memory-decay-readout.sh"
TMPDIR="$(mktemp -d -t memory-mr-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/memory" "$TMPDIR/.agent0/tools"
cp "$AGENT0_ROOT"/.agent0/tools/memory-* "$TMPDIR/.agent0/tools/"
chmod +x "$TMPDIR"/.agent0/tools/memory-*
cp "$AGENT0_ROOT/.agent0/memory.config.json" "$TMPDIR/.agent0/memory.config.json"

cat > "$TMPDIR/.agent0/memory/stale.md" <<'EOF'
---
name: Stale
description: Old entry for decay test.
metadata:
  type: project
  created_at: '2020-01-01T00:00:00Z'
  last_accessed: '2020-01-01'
  confirmed_count: 0
---
# Stale
EOF

payload="$(jq -n --arg cwd "$TMPDIR" '{hook_event_name:"SessionStart", source:"startup", cwd:$cwd, session_id:"memory-mr-02"}')"
out="$(printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK")"

if ! printf '%s\n' "$out" | grep -q '^=== MEMORY DECAY ===$'; then
  printf 'FAIL: missing decay frame\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q 'stale'; then
  printf 'FAIL: missing stale entry in readout\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-decay-readout"
