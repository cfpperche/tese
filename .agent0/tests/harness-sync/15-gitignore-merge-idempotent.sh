#!/usr/bin/env bash
# Scenario: .gitignore merge is idempotent on re-sync.
# Asserts:
#   (a) First --apply merges; file changes.
#   (b) Second --apply with no source changes reports "up to date"; file unchanged.
#   (c) Subsequent --check exits 0 (no drift).

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-15-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

printf '%s\n' \
  '# Claude Code state' \
  '.agent0/.runtime-state/' \
  '.agent0/secrets-audit.jsonl' \
  > "$SRC/.gitignore"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

printf '%s\n' \
  '/vendor' \
  '/node_modules' \
  > "$CONSUMER/.gitignore"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

# First apply — should merge.
first_out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || true
sha_after_first="$(sha256sum "$CONSUMER/.gitignore" | awk '{print $1}')"

if ! printf '%s' "$first_out" | grep -qE 'merged \.gitignore'; then
  printf 'FAIL(a): first apply did not log "merged .gitignore"\n%s\n' "$first_out"
  exit 1
fi

# Second apply — should be no-op.
second_out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || true
sha_after_second="$(sha256sum "$CONSUMER/.gitignore" | awk '{print $1}')"

if [ "$sha_after_first" != "$sha_after_second" ]; then
  printf 'FAIL(b): second apply changed file (hash drift on idempotent re-run)\n'
  diff <(printf '%s\n' "$sha_after_first") <(printf '%s\n' "$sha_after_second")
  cat "$CONSUMER/.gitignore"
  exit 1
fi

if ! printf '%s' "$second_out" | grep -qE 'up to date \.gitignore'; then
  printf 'FAIL(b): second apply did not log "up to date .gitignore"\n%s\n' "$second_out"
  exit 1
fi

# Third --check — should exit 0 (no drift).
check_exit=0
bash "$TOOL" --check --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || check_exit=$?
if [ "$check_exit" -ne 0 ]; then
  printf 'FAIL(c): --check after idempotent merge expected exit 0, got %d\n' "$check_exit"
  exit 1
fi

printf 'PASS: gitignore merge idempotent (first merges, second up-to-date, check exits 0)\n'
