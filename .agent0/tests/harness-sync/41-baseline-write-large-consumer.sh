#!/usr/bin/env bash
# Scenario: write_baseline must succeed when the managed file-set is large.
# Regression for the field bug found propagating spec 149/150 to real consumers:
# write_baseline passed the entire files-map to jq via a single `--argjson`
# command-line argument, which exceeds Linux MAX_ARG_STRLEN (~128 KB per arg) once
# the consumer has ~1000+ managed files → execve E2BIG ("Argument list too long")
# → "!! failed to write ...baseline.json (jq error)" and a stale/absent baseline.
# Synthetic SRCs in the other tests have only a handful of files, so they never
# crossed the limit. This test seeds enough managed files to cross it.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-068-41-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.agent0/skills/bulk" "$SRC/.claude" "$CONSUMER/.claude"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

# Seed enough managed files (.agent0/skills is a recursive copy root) that the
# resulting files-map JSON exceeds ~128 KB as a single string.
n=1600
i=1
while [ "$i" -le "$n" ]; do
  printf '#!/usr/bin/env bash\necho %05d\n' "$i" > "$SRC/.agent0/skills/bulk/file-$(printf '%05d' "$i").sh"
  i=$((i + 1))
done

bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || true

BASELINE="$CONSUMER/.agent0/harness-sync-baseline.json"
if [ ! -f "$BASELINE" ]; then
  printf 'FAIL: baseline not written for a large (%d-file) consumer (MAX_ARG_STRLEN regression)\n' "$n"
  exit 1
fi
if ! jq -e . "$BASELINE" >/dev/null 2>&1; then
  printf 'FAIL: baseline written but not valid JSON\n'
  exit 1
fi
recorded_count="$(jq -r '.files | length' "$BASELINE")"
if [ "$recorded_count" -lt "$n" ]; then
  printf 'FAIL: baseline files-map has %s entries, expected >= %d\n' "$recorded_count" "$n"
  exit 1
fi
echo "PASS: 41-baseline-write-large-consumer"
