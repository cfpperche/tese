#!/usr/bin/env bash
# Scenario: a fully-synced consumer project is idempotent.
# Asserts a second --apply on an already-synced consumer project mutates zero files and
# leaves harness-sync-baseline.json byte-identical.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-30-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude"

printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

BASELINE="$CONSUMER/.agent0/harness-sync-baseline.json"

# First --apply: copies hookA, writes the baseline.
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || true
mid_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"
baseline_mid="$(sha256sum "$BASELINE" | awk '{print $1}')"

# Second --apply: must be a no-op.
second_exit=0
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || second_exit=$?
if [ "$second_exit" -ne 0 ]; then
  printf 'FAIL: second --apply expected exit 0, got %d\n%s\n' "$second_exit" "$out"
  exit 1
fi

if printf '%s' "$out" | grep -qE '(\+ copied|~ stale|^- removed)'; then
  printf 'FAIL: second --apply produced mutation lines (not idempotent)\n%s\n' "$out"
  exit 1
fi

post_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"
if [ "$mid_sha" != "$post_sha" ]; then
  printf 'FAIL: second --apply modified the consumer project filesystem\n'
  exit 1
fi

baseline_post="$(sha256sum "$BASELINE" | awk '{print $1}')"
if [ "$baseline_mid" != "$baseline_post" ]; then
  printf 'FAIL: harness-sync-baseline.json changed on idempotent re-apply\n'
  exit 1
fi

echo "PASS: 30-baseline-idempotent-apply"
