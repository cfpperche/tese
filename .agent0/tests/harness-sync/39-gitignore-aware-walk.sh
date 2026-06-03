#!/usr/bin/env bash
# Spec 144 — Scenario: the git-aware recursive walk filters to tracked files.
# When the Agent0 source is a git work-tree, walk_copy_check sources the two
# find-based expansions from `git ls-files`, so:
#   - a tracked file under a recursive root is propagated
#   - a gitignored file is NOT (proves git-awareness, independent of the static
#     runtime-cache backstop — this ignored file is *.log, not extracted-*)
#   - an untracked-nonignored file is NOT (tracked-only)
#   - a tracked-but-locally-deleted file is NOT (the `-f` guard)
#   - a dirty source emits the one-line dirty advisory
#   - over-propagated runtime-cache orphans are removed but SUMMARIZED, not
#     listed per-file, on --apply.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-144-39-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/skills/foo/runtime/od-sync/extracted-abc" "$CONSUMER"

# --- Build SRC as a git work-tree ---
git -C "$SRC" init -q
cat > "$SRC/.gitignore" <<'EOF'
*.log
extracted-*/
EOF
# tracked file under a recursive root
printf '# skill\n' > "$SRC/.claude/skills/foo/SKILL.md"
# gitignored file (*.log) — git-aware walk must drop it; static exclude does NOT match it
printf 'noise\n' > "$SRC/.claude/skills/foo/debug.log"
# gitignored cache (extracted-*) — dropped by git-awareness AND the static backstop
printf 'cache\n' > "$SRC/.claude/skills/foo/runtime/od-sync/extracted-abc/cache.txt"
# a tracked file we will delete from the work-tree after commit
printf 'temp\n' > "$SRC/.claude/skills/foo/del.md"
# minimal merge inputs so the tool's settings/CLAUDE.md/.gitignore steps run cleanly
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
git -C "$SRC" add -A
git -C "$SRC" -c user.email=t@t -c user.name=t commit -q -m init
# now dirty the work-tree: delete a tracked file + add an untracked-nonignored file
rm "$SRC/.claude/skills/foo/del.md"
printf 'stray\n' > "$SRC/.claude/skills/foo/untracked.txt"

# --- Sub-test A: --check propagation set is exactly the tracked-present file ---
OUT="$(bash "$TOOL" --agent0-path="$SRC" --check "$CONSUMER" 2>"$TMPDIR/err.txt" || true)"

grep -q '\.claude/skills/foo/SKILL\.md' <<<"$OUT" \
  || { printf 'FAIL: tracked SKILL.md not in walk\n%s\n' "$OUT"; exit 1; }
printf 'ok: tracked file propagates\n'

if grep -q 'debug\.log' <<<"$OUT"; then
  printf 'FAIL: gitignored *.log leaked (git-awareness broken)\n%s\n' "$OUT"; exit 1; fi
printf 'ok: gitignored file excluded\n'

if grep -q 'extracted-abc' <<<"$OUT"; then
  printf 'FAIL: gitignored runtime cache leaked\n%s\n' "$OUT"; exit 1; fi
printf 'ok: runtime cache excluded\n'

if grep -q 'untracked\.txt' <<<"$OUT"; then
  printf 'FAIL: untracked-nonignored file leaked (not tracked-only)\n%s\n' "$OUT"; exit 1; fi
printf 'ok: untracked-nonignored file excluded\n'

if grep -q 'foo/del\.md' <<<"$OUT"; then
  printf 'FAIL: tracked-but-deleted file in manifest (the -f guard failed)\n%s\n' "$OUT"; exit 1; fi
printf 'ok: tracked-but-locally-deleted file excluded\n'

# --- Sub-test B: dirty source emits the one-line advisory (to stderr) ---
if ! grep -q 'work-tree is dirty under managed roots' "$TMPDIR/err.txt"; then
  printf 'FAIL: dirty-source advisory not emitted\n'; cat "$TMPDIR/err.txt"; exit 1; fi
printf 'ok: dirty-source advisory emitted\n'

# --- Sub-test C: cache orphan cleanup is summarized, not per-file ---
# Consumer carries a runtime-cache file + a baseline recording it; SRC has no
# such tracked path, so it is a clean orphan the deletion pass must remove and
# summarize.
ORPHAN_REL=".claude/skills/foo/runtime/od-sync/extracted-old/c.txt"
mkdir -p "$CONSUMER/$(dirname "$ORPHAN_REL")" "$CONSUMER/.claude/skills/foo" "$CONSUMER/.agent0"
printf 'cache\n' > "$CONSUMER/.claude/skills/foo/SKILL.md"   # so SKILL.md is up-to-date, not the focus
printf 'oldcache\n' > "$CONSUMER/$ORPHAN_REL"
ORPHAN_SHA="$(sha256sum "$CONSUMER/$ORPHAN_REL" | cut -d' ' -f1)"
SKILL_SHA="$(sha256sum "$SRC/.claude/skills/foo/SKILL.md" | cut -d' ' -f1)"
cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<EOF
{
  "agent0_commit": null,
  "synced_at": "2026-01-01T00:00:00Z",
  "tool_version": 1,
  "files": {
    ".claude/skills/foo/SKILL.md": "$SKILL_SHA",
    "$ORPHAN_REL": "$ORPHAN_SHA"
  }
}
EOF

OUT_APPLY="$(bash "$TOOL" --agent0-path="$SRC" --apply "$CONSUMER" 2>"$TMPDIR/err2.txt" || true)"

if [ -f "$CONSUMER/$ORPHAN_REL" ]; then
  printf 'FAIL: cache orphan not removed on --apply\n%s\n' "$OUT_APPLY"; exit 1; fi
printf 'ok: cache orphan removed\n'

if grep -qF "$ORPHAN_REL" <<<"$OUT_APPLY"; then
  printf 'FAIL: cache orphan listed per-file (should be summarized)\n%s\n' "$OUT_APPLY"; exit 1; fi
if ! grep -q 'runtime-cache orphans under runtime/od-sync/extracted-' <<<"$OUT_APPLY"; then
  printf 'FAIL: cache orphan removal not summarized\n%s\n' "$OUT_APPLY"; exit 1; fi
printf 'ok: cache orphan removal summarized, not per-file\n'

printf 'PASS: 39-gitignore-aware-walk\n'
