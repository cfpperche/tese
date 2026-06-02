#!/usr/bin/env bash
# Scenario: an upstream-removed file the consumer project customized is NOT deleted.
# Asserts:
#   (a) a baseline file absent from Agent0's manifest whose consumer project copy differs
#       from baseline is preserved (consumer project work is never silently destroyed)
#   (b) it is reported `!! customized ... (upstream-removed)`
#   (c) --apply exits non-zero

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-27-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks"

printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"

printf '#!/usr/bin/env bash\necho hookA\n' > "$CONSUMER/.claude/hooks/hookA.sh"
printf '#!/usr/bin/env bash\necho CONSUMER-EDITED-legacy\n' > "$CONSUMER/.claude/hooks/legacyhook.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh" "$CONSUMER/.claude/hooks/legacyhook.sh"

hookA_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"
# Baseline records legacyhook with a sha the consumer project copy does NOT match — consumer project edited it.
mkdir -p "$CONSUMER/.agent0"
cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<EOF
{
  "agent0_commit": null,
  "synced_at": "2026-05-01T00:00:00Z",
  "tool_version": 1,
  "files": {
    ".claude/hooks/hookA.sh": "$hookA_sha",
    ".claude/hooks/legacyhook.sh": "1111111111111111111111111111111111111111111111111111111111111111"
  }
}
EOF

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: customized-upstream-removed --apply expected non-zero exit, got 0\n%s\n' "$out"
  exit 1
fi

if [ ! -f "$CONSUMER/.claude/hooks/legacyhook.sh" ]; then
  printf 'FAIL: consumer-customized upstream-removed file was deleted (consumer project work destroyed)\n'
  exit 1
fi

if ! printf '%s' "$out" | grep -qE '!! customized.*legacyhook\.sh.*upstream-removed'; then
  printf 'FAIL: expected `!! customized ... (upstream-removed)` for legacyhook.sh\n%s\n' "$out"
  exit 1
fi

echo "PASS: 27-baseline-customized-upstream-removed"
