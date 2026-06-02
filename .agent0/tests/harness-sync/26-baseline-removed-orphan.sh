#!/usr/bin/env bash
# Scenario: an upstream-removed file is deleted from the consumer project.
# Asserts:
#   (a) a baseline file absent from Agent0's manifest, consumer project copy == baseline,
#       is removed and reported `- removed`
#   (b) now-empty parent directories are pruned
#   (c) files still in Agent0's manifest are untouched; --apply exits 0

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-26-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks" "$CONSUMER/.claude/skills/legacy"

# Agent0 currently ships only hookA.
printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"

# Consumer project has hookA + an orphan skill Agent0 has since removed.
printf '#!/usr/bin/env bash\necho hookA\n' > "$CONSUMER/.claude/hooks/hookA.sh"
printf '# legacy skill\n' > "$CONSUMER/.claude/skills/legacy/SKILL.md"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh"

hookA_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"
orphan_sha="$(sha256sum "$CONSUMER/.claude/skills/legacy/SKILL.md" | awk '{print $1}')"
# Baseline records both — the orphan's consumer project copy still matches its baseline sha.
mkdir -p "$CONSUMER/.agent0"
cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<EOF
{
  "agent0_commit": null,
  "synced_at": "2026-05-01T00:00:00Z",
  "tool_version": 1,
  "files": {
    ".claude/hooks/hookA.sh": "$hookA_sha",
    ".claude/skills/legacy/SKILL.md": "$orphan_sha"
  }
}
EOF

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: removal --apply expected exit 0, got %d\n%s\n' "$actual_exit" "$out"
  exit 1
fi

if ! printf '%s' "$out" | grep -qE '^- removed.*legacy/SKILL\.md'; then
  printf 'FAIL: expected `- removed` line for the orphan SKILL.md\n%s\n' "$out"
  exit 1
fi

if [ -f "$CONSUMER/.claude/skills/legacy/SKILL.md" ]; then
  printf 'FAIL: orphan SKILL.md still present after --apply\n'
  exit 1
fi

if [ -d "$CONSUMER/.claude/skills/legacy" ]; then
  printf 'FAIL: emptied parent dir .claude/skills/legacy not pruned\n'
  exit 1
fi

if [ ! -f "$CONSUMER/.claude/hooks/hookA.sh" ]; then
  printf 'FAIL: in-manifest hookA.sh wrongly removed\n'
  exit 1
fi

echo "PASS: 26-baseline-removed-orphan"
