#!/usr/bin/env bash
# Spec 144 — Scenario: a non-git Agent0 source falls back to a GUARDED find,
# never blind. When the source is not a git work-tree (a tarball/archive export
# with no .git), walk_copy_check cannot use `git ls-files`, so it falls back to
# find — but the always-applied static runtime-cache exclusion still drops the
# known cache, and a one-line degraded-mode advisory is emitted. A normal
# tracked-shaped file still propagates.
#
# Note: a standard `git archive` export is already cache-free (the cache is
# gitignored, never in the archive), so the static exclude is defense-in-depth
# for a non-standard raw-copy export of a dirty work-tree.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-144-40-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
# SRC is a PLAIN directory — deliberately NO `git init`.
mkdir -p "$SRC/.claude/skills/foo/runtime/od-sync/extracted-x" "$CONSUMER"

printf '# skill\n' > "$SRC/.claude/skills/foo/SKILL.md"
printf 'cache\n' > "$SRC/.claude/skills/foo/runtime/od-sync/extracted-x/cache.txt"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

OUT="$(bash "$TOOL" --agent0-path="$SRC" --check "$CONSUMER" 2>"$TMPDIR/err.txt" || true)"

# A normal tracked-shaped file still propagates under the degraded walk.
grep -q '\.claude/skills/foo/SKILL\.md' <<<"$OUT" \
  || { printf 'FAIL: normal file not propagated under non-git fallback\n%s\n' "$OUT"; exit 1; }
printf 'ok: normal file still propagates\n'

# The runtime cache is excluded by the static backstop even without git.
if grep -q 'extracted-x' <<<"$OUT"; then
  printf 'FAIL: runtime cache leaked under non-git fallback (static exclude failed)\n%s\n' "$OUT"; exit 1; fi
printf 'ok: runtime cache excluded by static backstop\n'

# The degraded-mode advisory is emitted (to stderr).
if ! grep -q 'not a git work-tree' "$TMPDIR/err.txt"; then
  printf 'FAIL: non-git degraded-mode advisory not emitted\n'; cat "$TMPDIR/err.txt"; exit 1; fi
printf 'ok: non-git advisory emitted\n'

printf 'PASS: 40-non-git-source-fallback\n'
