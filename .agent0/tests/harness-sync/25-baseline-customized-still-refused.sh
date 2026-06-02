#!/usr/bin/env bash
# Scenario: a genuinely customized file is still refused.
# Asserts:
#   (a) a file differing from BOTH baseline and Agent0 is `!! customized`
#   (b) it is NOT the `(no baseline)` path — a baseline IS present
#   (c) the file is left untouched and --apply exits non-zero

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-25-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks"

printf '#!/usr/bin/env bash\necho agent0-version\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"

printf '#!/usr/bin/env bash\necho CONSUMER-EDITED-version\n' > "$CONSUMER/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh"

# Baseline records a THIRD distinct value — consumer project differs from baseline AND Agent0.
mkdir -p "$CONSUMER/.agent0"
cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<'EOF'
{
  "agent0_commit": null,
  "synced_at": "2026-05-01T00:00:00Z",
  "tool_version": 1,
  "files": { ".claude/hooks/hookA.sh": "0000000000000000000000000000000000000000000000000000000000000000" }
}
EOF

before_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -eq 0 ]; then
  printf 'FAIL: customized --apply expected non-zero exit, got 0\n%s\n' "$out"
  exit 1
fi

if ! printf '%s' "$out" | grep -qE '!! customized.*hookA\.sh'; then
  printf 'FAIL: expected `!! customized` for hookA.sh\n%s\n' "$out"
  exit 1
fi

# A baseline IS present — the customized line must NOT carry `(no baseline)`.
if printf '%s' "$out" | grep -E 'hookA\.sh' | grep -q 'no baseline'; then
  printf 'FAIL: customized hookA.sh wrongly tagged `(no baseline)` despite a present baseline\n%s\n' "$out"
  exit 1
fi

after_sha="$(sha256sum "$CONSUMER/.claude/hooks/hookA.sh" | awk '{print $1}')"
if [ "$before_sha" != "$after_sha" ]; then
  printf 'FAIL: customized hookA.sh was overwritten\n'
  exit 1
fi

echo "PASS: 25-baseline-customized-still-refused"
