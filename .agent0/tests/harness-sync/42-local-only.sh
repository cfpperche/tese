#!/usr/bin/env bash
# Scenario (spec 151): local-only mode — a consumer that gitignores the whole
# .agent0/ harness tree gets its gitignored harness refreshed by --apply, but NO
# tracked file is written/merged (so there is nothing harness-related to commit).
# A consumer that does NOT ignore .agent0/ is unaffected (mode strictly opt-in).
#
# Auto-detected via git's ignore engine (git check-ignore). Motivating case:
# tmux-sentinel (public repo consuming the harness as local dev tooling only).

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-151-42-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- synthetic Agent0 source: one ignored-in-consumer harness file + one tracked managed file ---
SRC="$TMPDIR/agent0"
mkdir -p "$SRC/.agent0/skills/demo" "$SRC/.claude"
printf 'name: demo\n' > "$SRC/.agent0/skills/demo/SKILL.md"
printf 'title = "from-agent0"\n' > "$SRC/.gitleaks.toml"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# --- consumer A: LOCAL-ONLY (gitignores the whole .agent0/ tree) ---
A="$TMPDIR/local-only"
mkdir -p "$A/.claude"
git -C "$A" init -q
printf '.agent0/\n' > "$A/.gitignore"
printf 'title = "consumer-original"\n' > "$A/.gitleaks.toml"        # tracked; must NOT change
printf '{"hooks":{}}\n' > "$A/.claude/settings.json"
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$A/CLAUDE.md"
git -C "$A" add -A && git -C "$A" -c user.email=t@t -c user.name=t commit -qm baseline

out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$A" 2>&1 || true)"

# (a) the gitignored harness content WAS refreshed
[ -f "$A/.agent0/skills/demo/SKILL.md" ] || { echo "FAIL: local-only did not refresh the gitignored harness (.agent0/skills/demo/SKILL.md missing)"; exit 1; }
# (b) NO tracked file changed (git status ignores .agent0/; tracked files must be untouched)
dirty="$(git -C "$A" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: local-only wrote tracked files (working tree dirty):"; printf '%s\n' "$dirty"; exit 1; }
# (b') the tracked .gitleaks.toml kept the consumer's content (not overwritten from SRC)
grep -q 'consumer-original' "$A/.gitleaks.toml" || { echo "FAIL: local-only overwrote tracked .gitleaks.toml"; exit 1; }
# (c) the mode was reported, not silent
printf '%s' "$out" | grep -qi 'local-only' || { echo "FAIL: local-only mode not reported in output"; exit 1; }

# --- consumer B: NORMAL (does NOT ignore .agent0/) — mode must stay OFF ---
# No pre-existing .gitleaks.toml: the sync copies it fresh (the missing-file copy
# path), proving tracked-file writes still happen for a normal consumer. (We do
# NOT pre-commit a divergent .gitleaks.toml — that would be a customized file the
# sync correctly refuses, which is unrelated to local-only.)
B="$TMPDIR/normal"
mkdir -p "$B/.claude"
git -C "$B" init -q
printf 'node_modules/\n' > "$B/.gitignore"
printf '{"hooks":{}}\n' > "$B/.claude/settings.json"
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$B/CLAUDE.md"
git -C "$B" add -A && git -C "$B" -c user.email=t@t -c user.name=t commit -qm baseline

bash "$TOOL" --apply --agent0-path="$SRC" "$B" >/dev/null 2>&1 || true
[ -f "$B/.gitleaks.toml" ] && grep -q 'from-agent0' "$B/.gitleaks.toml" || { echo "FAIL: normal consumer did not receive the tracked .gitleaks.toml (local-only wrongly triggered, or copy skipped)"; exit 1; }

echo "PASS: 42-local-only"
