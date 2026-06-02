#!/usr/bin/env bash
# Scenario: check mode lists drift.
# Asserts:
#   (a) --check exits 1 when drift exists
#   (b) stdout names each missing file
#   (c) no filesystem writes in consumer project target

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-01-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$SRC/.agent0/context/rules" "$CONSUMER/.claude/hooks" "$CONSUMER/.agent0/context/rules"

# Source: 2 hooks + 1 rule
printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '#!/usr/bin/env bash\necho hookB\n' > "$SRC/.claude/hooks/hookB.sh"
printf '# rule-A\n' > "$SRC/.agent0/context/rules/ruleA.md"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh" "$SRC/.claude/hooks/hookB.sh"

# Consumer project: only hookA present (missing hookB + ruleA)
printf '#!/usr/bin/env bash\necho hookA\n' > "$CONSUMER/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh"

pre_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"

actual_exit=0
out="$(bash "$TOOL" --check --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

# Assertions
if [ "$actual_exit" -ne 1 ]; then
  printf 'FAIL: expected exit=1 (drift), got exit=%d\n' "$actual_exit"
  printf '%s\n' "$out"
  exit 1
fi

if ! printf '%s' "$out" | grep -q 'hookB.sh'; then
  printf 'FAIL: stdout missing hookB.sh\n%s\n' "$out"
  exit 1
fi

if ! printf '%s' "$out" | grep -q 'ruleA.md'; then
  printf 'FAIL: stdout missing ruleA.md\n%s\n' "$out"
  exit 1
fi

post_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"
if [ "$pre_sha" != "$post_sha" ]; then
  printf 'FAIL: --check should not modify consumer project\n'
  exit 1
fi

echo "PASS: 01-check-mode-lists-drift"
