#!/usr/bin/env bash
# Scenario: shared routines SessionStart readout emits pending queue entries.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/routines-readout.sh"
TMPDIR="$(mktemp -d -t multi-readouts-routines-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/routines" "$TMPDIR/.agent0/.routines-state/weekly/queue"
printf '%s\n' '---' 'schedule: "0 9 * * 1"' '---' '# Weekly routine' > "$TMPDIR/.agent0/routines/weekly.md"
oldest="$(( $(date -u +%s) - 120 ))"
printf 'Run weekly fixture\n' > "$TMPDIR/.agent0/.routines-state/weekly/queue/$oldest.md"

payload="$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$TMPDIR")"
out="$(printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK")"

if ! printf '%s\n' "$out" | grep -q '^=== ROUTINES ===$'; then
  printf 'FAIL: missing routines frame\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q '^=== end ROUTINES ===$'; then
  printf 'FAIL: missing routines close frame\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q 'weekly: 1 pending'; then
  printf 'FAIL: missing weekly queue entry\n%s\n' "$out"
  exit 1
fi

echo "PASS: 02-routines-fixture"
