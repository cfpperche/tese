#!/usr/bin/env bash
# Scenario: shared reminders SessionStart readout emits the framed block.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/reminders-readout.sh"
TMPDIR="$(mktemp -d -t multi-readouts-reminders-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/skills/remind/scripts"
cp "$AGENT0_ROOT/.agent0/skills/remind/scripts/reminders-helper.py" "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"
chmod +x "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"

mkdir -p "$TMPDIR/.agent0"
cat > "$TMPDIR/.agent0/reminders.yaml" <<'YAML'
reminders:
  - id: r-2026-05-27-check-session-readout
    created: '2026-05-27'
    context: Check session readout fixture
    status: pending
YAML

payload="$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$TMPDIR")"
stderr_capture="$TMPDIR/stderr.txt"
out="$(printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK" 2>"$stderr_capture")"

if ! printf '%s\n' "$out" | grep -q '^=== REMINDERS ===$'; then
  printf 'FAIL: missing reminders frame\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q '^=== end REMINDERS ===$'; then
  printf 'FAIL: missing reminders close frame\n%s\n' "$out"
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q 'Check session readout fixture'; then
  printf 'FAIL: missing pending reminder content\n%s\n' "$out"
  exit 1
fi

minimal_bin="$TMPDIR/minimal-bin"
mkdir -p "$minimal_bin"
ln -s "$(command -v date)" "$minimal_bin/date"
ln -s "$(command -v cat)" "$minimal_bin/cat"
ln -s "$(command -v dirname)" "$minimal_bin/dirname"
ln -s "$(command -v bash)" "$minimal_bin/bash"
cat > "$minimal_bin/python3" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$minimal_bin/python3"

degraded_stderr="$TMPDIR/degraded-stderr.txt"
degraded_out="$(printf '%s' "$payload" | PATH="$minimal_bin" AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK" 2>"$degraded_stderr")"

if ! grep -q '^reminders-degraded-advisory:' "$degraded_stderr"; then
  printf 'FAIL: degraded fallback missing advisory\nstderr:\n'
  cat "$degraded_stderr"
  printf '\nstdout:\n%s\n' "$degraded_out"
  exit 1
fi
if ! printf '%s\n' "$degraded_out" | grep -q '^reminders:$'; then
  printf 'FAIL: degraded fallback did not emit raw YAML\n%s\n' "$degraded_out"
  exit 1
fi

echo "PASS: 01-reminders-fixture"
