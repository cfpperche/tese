#!/usr/bin/env bash
# Scenario: .gitignore merge when consumer project has stack-canonical .gitignore.
# This is the core motivating case: Laravel/Node/Cargo consumer projects ship their own
# .gitignore and would lose Agent0 entries under naive overwrite logic.
# Asserts:
#   (a) Consumer project-specific entries (e.g. /vendor, /node_modules) PRESERVED untouched
#   (b) Agent0 entries consumer project was missing get APPENDED below a marker line
#   (c) Entries consumer project already had are NOT duplicated
#   (d) --check on the same setup reports drift (exit 1) and names entry count

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-14-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

# Agent0: harness entries
printf '%s\n' \
  '# Claude Code state' \
  '.agent0/.runtime-state/' \
  '.agent0/secrets-audit.jsonl' \
  '.agent0/delegation-audit.jsonl' \
  '.agent0/.session-state/' \
  > "$SRC/.gitignore"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# Consumer project: Laravel-style .gitignore with ONE overlapping entry (.agent0/.session-state/)
# plus 3 consumer-specific entries that must survive.
printf '%s\n' \
  '/vendor' \
  '/node_modules' \
  '.env' \
  '.agent0/.session-state/' \
  > "$CONSUMER/.gitignore"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

# Step 1 — assertion (d): --check reports drift before apply.
check_exit=0
check_out="$(bash "$TOOL" --check --agent0-path="$SRC" "$CONSUMER" 2>&1)" || check_exit=$?
if [ "$check_exit" -ne 1 ]; then
  printf 'FAIL(d): --check expected exit 1 (drift), got %d\n%s\n' "$check_exit" "$check_out"
  exit 1
fi
if ! printf '%s' "$check_out" | grep -qE '\.gitignore.*entries to add'; then
  printf 'FAIL(d): --check stdout missing gitignore entry-count line\n%s\n' "$check_out"
  exit 1
fi

# Step 2 — apply the merge.
actual_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || actual_exit=$?
if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit 0, got %d\n' "$actual_exit"
  exit 1
fi

# Assert (a): consumer-specific entries preserved.
for entry in '/vendor' '/node_modules' '.env'; do
  if ! grep -Fxq "$entry" "$CONSUMER/.gitignore"; then
    printf 'FAIL(a): consumer-specific entry %s missing from merged file\n' "$entry"
    cat "$CONSUMER/.gitignore"
    exit 1
  fi
done

# Assert (b): missing Agent0 entries appended.
for entry in '.agent0/.runtime-state/' '.agent0/secrets-audit.jsonl' '.agent0/delegation-audit.jsonl'; do
  if ! grep -Fxq "$entry" "$CONSUMER/.gitignore"; then
    printf 'FAIL(b): Agent0 entry %s missing from merged file\n' "$entry"
    cat "$CONSUMER/.gitignore"
    exit 1
  fi
done

# Assert (b cont.): marker present exactly once.
marker_count="$(grep -cF '# === Agent0 harness sync — additions ===' "$CONSUMER/.gitignore" || true)"
if [ "$marker_count" -ne 1 ]; then
  printf 'FAIL(b): expected exactly 1 marker line, got %s\n' "$marker_count"
  cat "$CONSUMER/.gitignore"
  exit 1
fi

# Assert (c): overlap entry (.agent0/.session-state/) appears exactly once.
session_count="$(grep -cFx '.agent0/.session-state/' "$CONSUMER/.gitignore" || true)"
if [ "$session_count" -ne 1 ]; then
  printf 'FAIL(c): overlap entry duplicated — count=%s\n' "$session_count"
  cat "$CONSUMER/.gitignore"
  exit 1
fi

printf 'PASS: customized consumer project gitignore merged additively (3 added, consumer-specific preserved, no dupes)\n'
