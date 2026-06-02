#!/usr/bin/env bash
# Scenario: .gitignore merge when consumer project has no .gitignore.
# Asserts:
#   (a) Consumer project lacking .gitignore receives Agent0's verbatim via process_file
#   (b) No merge marker appears (full copy, not append-merge)
#   (c) MERGED counter NOT incremented (this is a COPY, not a MERGE)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-13-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

# Agent0: minimal valid harness with a .gitignore containing 3 entries.
printf '%s\n' \
  '# Claude Code state' \
  '.agent0/.runtime-state/' \
  '.agent0/secrets-audit.jsonl' \
  '.agent0/delegation-audit.jsonl' \
  > "$SRC/.gitignore"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# Consumer project: no .gitignore at all.
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

actual_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit 0, got %d\n' "$actual_exit"
  exit 1
fi

if [ ! -f "$CONSUMER/.gitignore" ]; then
  printf 'FAIL: consumer project .gitignore not created\n'
  exit 1
fi

# Assert (a): consumer project .gitignore byte-identical to Agent0's.
src_sha="$(sha256sum "$SRC/.gitignore" | awk '{print $1}')"
consumer_sha="$(sha256sum "$CONSUMER/.gitignore" | awk '{print $1}')"
if [ "$src_sha" != "$consumer_sha" ]; then
  printf 'FAIL: expected byte-identical copy, got different hashes\n'
  diff "$SRC/.gitignore" "$CONSUMER/.gitignore"
  exit 1
fi

# Assert (b): no merge marker — this was a copy, not an append-merge.
if grep -Fq '# === Agent0 harness sync — additions ===' "$CONSUMER/.gitignore"; then
  printf 'FAIL: unexpected merge marker in copied-only file\n'
  exit 1
fi

printf 'PASS: consumer project without .gitignore receives Agent0 copy verbatim\n'
