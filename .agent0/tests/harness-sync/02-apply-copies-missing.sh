#!/usr/bin/env bash
# Scenario: apply mode copies missing files.
# Asserts:
#   (a) --apply exits 0 on clean apply
#   (b) every missing file gets a `+ copied` line
#   (c) post-apply --check exits 0 (no drift)
#   (d) executable mode preserved on copied .sh files

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$SRC/.agent0/context/rules" "$CONSUMER/.claude"

printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '#!/usr/bin/env bash\necho hookB\n' > "$SRC/.claude/hooks/hookB.sh"
printf '# rule-A\n' > "$SRC/.agent0/context/rules/ruleA.md"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh" "$SRC/.claude/hooks/hookB.sh"

printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

actual_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit=0, got %d\n%s\n' "$actual_exit" "$out"
  exit 1
fi

for f in .claude/hooks/hookA.sh .claude/hooks/hookB.sh .agent0/context/rules/ruleA.md; do
  if [ ! -f "$CONSUMER/$f" ]; then
    printf 'FAIL: %s not copied\n%s\n' "$f" "$out"
    exit 1
  fi
done

if ! printf '%s' "$out" | grep -q '+ copied.*hookB.sh'; then
  printf 'FAIL: missing `+ copied` line for hookB.sh\n%s\n' "$out"
  exit 1
fi

if [ ! -x "$CONSUMER/.claude/hooks/hookA.sh" ]; then
  printf 'FAIL: executable mode not preserved on hookA.sh\n'
  exit 1
fi

check_exit=0
bash "$TOOL" --check --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || check_exit=$?
if [ "$check_exit" -ne 0 ]; then
  printf 'FAIL: post-apply --check should exit 0, got %d\n' "$check_exit"
  exit 1
fi

echo "PASS: 02-apply-copies-missing"
