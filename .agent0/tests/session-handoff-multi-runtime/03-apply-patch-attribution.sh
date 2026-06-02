#!/usr/bin/env bash
# Scenario 3: Codex apply_patch payloads are attributed into edited-files.txt.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TRACK_HOOK="$AGENT0_ROOT/.agent0/hooks/session-track-edits.sh"

TMPDIR="$(mktemp -d -t spec-101-03-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR"
SESSION_ID="codex-track-03"
TRACK_FILE="$TMPDIR/.agent0/.session-state/$SESSION_ID/edited-files.txt"

patch_body=$'*** Begin Patch\n*** Add File: src/new.ts\n+export const value = 1;\n*** Update File: tracked.txt\n@@\n-old\n+new\n*** Delete File: old.txt\n*** Update File: rename-source.txt\n*** Move to: moved.txt\n@@\n-old\n+new\n*** Update File: tracked.txt\n@@\n-new\n+newer\n*** End Patch\n'
payload="$(jq -cn --arg sid "$SESSION_ID" --arg cwd "$TMPDIR" --arg patch "$patch_body" '{
  tool_name: "apply_patch",
  session_id: $sid,
  cwd: $cwd,
  tool_input: {command: $patch}
}')"

printf '%s' "$payload" | bash "$TRACK_HOOK"
printf '%s' "$payload" | bash "$TRACK_HOOK"

if [ ! -f "$TRACK_FILE" ]; then
  printf 'FAIL: edited-files.txt was not created\n'
  exit 1
fi

expected="$TMPDIR/expected.txt"
cat > "$expected" <<'EOF'
src/new.ts
tracked.txt
old.txt
rename-source.txt
moved.txt
EOF

if ! diff -u "$expected" "$TRACK_FILE"; then
  printf 'FAIL: apply_patch attribution mismatch\n'
  exit 1
fi

printf 'PASS\n'
exit 0
