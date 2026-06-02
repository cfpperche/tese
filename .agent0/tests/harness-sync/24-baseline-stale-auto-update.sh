#!/usr/bin/env bash
# Scenario: a stale plain file auto-updates without --force.
# Asserts:
#   (a) a file whose consumer project copy == baseline but != Agent0 is reported `~ stale`
#   (b) the file is updated to Agent0's version
#   (c) --apply exits 0 (stale is a successful update, not a refusal)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-24-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks"

# Agent0 ships v2 of hookA.
printf '#!/usr/bin/env bash\necho hookA-v2\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"

# Consumer project still has v1 of hookA — untouched since last sync.
printf '#!/usr/bin/env bash\necho hookA-v1\n' > "$CONSUMER/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh"

# Baseline records v1's sha — consumer project copy matches baseline exactly.
v1_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"
mkdir -p "$CONSUMER/.agent0"
cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<EOF
{
  "agent0_commit": null,
  "synced_at": "2026-05-01T00:00:00Z",
  "tool_version": 1,
  "files": { ".claude/hooks/hookA.sh": "$v1_sha" }
}
EOF

v2_sha="$(sha256sum "$SRC/.claude/hooks/hookA.sh" | awk '{print $1}')"

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: stale --apply expected exit 0, got %d\n%s\n' "$actual_exit" "$out"
  exit 1
fi

if ! printf '%s' "$out" | grep -qE '~ stale.*hookA\.sh'; then
  printf 'FAIL: expected `~ stale` line for hookA.sh\n%s\n' "$out"
  exit 1
fi

if printf '%s' "$out" | grep -qE '!! customized.*hookA\.sh'; then
  printf 'FAIL: stale file wrongly reported customized\n%s\n' "$out"
  exit 1
fi

after_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"
if [ "$after_sha" != "$v2_sha" ]; then
  printf 'FAIL: stale hookA.sh not updated to Agent0 version\n'
  exit 1
fi

echo "PASS: 24-baseline-stale-auto-update"
