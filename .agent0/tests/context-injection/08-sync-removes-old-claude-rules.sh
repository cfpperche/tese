#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SYNC="$ROOT/.agent0/tools/sync-harness.sh"
TMPDIR="$(mktemp -d -t context-injection-08-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CONSUMER="$TMPDIR/consumer"
mkdir -p "$CONSUMER/.claude/rules" "$CONSUMER/.agent0"
printf '# old rule\n' > "$CONSUMER/.claude/rules/old.md"
old_sha="$(sha256sum "$CONSUMER/.claude/rules/old.md" | awk '{print $1}')"

cat > "$CONSUMER/.agent0/harness-sync-baseline.json" <<JSON
{
  "agent0_commit": null,
  "synced_at": "2026-05-30T00:00:00Z",
  "tool_version": 1,
  "files": {
    ".claude/rules/old.md": "$old_sha"
  }
}
JSON

bash "$SYNC" --apply --agent0-path="$ROOT" "$CONSUMER" >/dev/null 2>&1

if [ -e "$CONSUMER/.claude/rules/old.md" ]; then
  printf 'FAIL: old .claude/rules file was not removed\n'
  exit 1
fi

echo "PASS: 08-sync-removes-old-claude-rules"
