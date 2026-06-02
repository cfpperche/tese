#!/usr/bin/env bash
# Scenario: dry-run shows actions without performing them.
# Asserts:
#   (a) --apply --dry-run emits decision lines like a real apply
#   (b) zero filesystem changes in consumer project (sha256 stable)
#   (c) exit 0

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-07-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks"

printf '#!/usr/bin/env bash\necho new\n' > "$SRC/.claude/hooks/newhook.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/newhook.sh"

printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

pre_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"
pre_files="$(find "$CONSUMER" -type f | sort)"

actual_exit=0
out="$(bash "$TOOL" --apply --dry-run --agent0-path="$SRC" "$CONSUMER" 2>&1)" || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --dry-run expected exit 0, got %d\n%s\n' "$actual_exit" "$out"
  exit 1
fi

# Decision lines emitted (would-copy shape acceptable; real apply emits `+ copied`)
if ! printf '%s' "$out" | grep -qE '(copied|would copy).*newhook'; then
  printf 'FAIL: dry-run did not name newhook.sh in decision output\n%s\n' "$out"
  exit 1
fi

# Filesystem unchanged
post_sha="$(find "$CONSUMER" -type f -exec sha256sum {} \; | sort)"
post_files="$(find "$CONSUMER" -type f | sort)"
if [ "$pre_sha" != "$post_sha" ] || [ "$pre_files" != "$post_files" ]; then
  printf 'FAIL: dry-run modified consumer project filesystem\n'
  diff <(printf '%s' "$pre_files") <(printf '%s' "$post_files") || true
  exit 1
fi

echo "PASS: 07-dry-run-no-writes"
