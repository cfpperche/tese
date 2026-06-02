#!/usr/bin/env bash
# Scenario: synthetic Codex apply_patch payload validates, journals, and projects.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$AGENT0_ROOT/.agent0/hooks/memory-events-journal.sh"
TMPDIR="$(mktemp -d -t memory-mr-03-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/memory" "$TMPDIR/.agent0/tools"
cp "$AGENT0_ROOT"/.agent0/tools/memory-* "$TMPDIR/.agent0/tools/"
chmod +x "$TMPDIR"/.agent0/tools/memory-*
cp "$AGENT0_ROOT/.agent0/memory.config.json" "$TMPDIR/.agent0/memory.config.json"

cat > "$TMPDIR/.agent0/memory/foo.md" <<'EOF'
---
name: Foo
description: Updated through Codex hook.
metadata:
  type: project
---
# Foo
EOF
printf -- '- [Old](old.md) — stale\n' > "$TMPDIR/.agent0/memory/MEMORY.md"

patch='*** Begin Patch
*** Update File: .agent0/memory/foo.md
@@
-old
+new
*** End Patch'

payload="$(jq -n \
  --arg cwd "$TMPDIR" \
  --arg command "$patch" \
  '{hook_event_name:"PostToolUse", tool_name:"apply_patch", cwd:$cwd, session_id:"codex-session", tool_use_id:"tool-123", tool_input:{command:$command}, tool_response:{}}')"

stderr_capture="$(mktemp -t memory-mr-03-stderr-XXXXXX)"
printf '%s' "$payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK" 2>"$stderr_capture"

if [ ! -f "$TMPDIR/.agent0/.memory-events.jsonl" ]; then
  printf 'FAIL: journal not written\n'
  cat "$stderr_capture"
  exit 1
fi
if ! jq -e 'select(.actor == "Codex CLI" and .runtime == "codex-cli" and .tool == "apply_patch" and .path == ".agent0/memory/foo.md")' "$TMPDIR/.agent0/.memory-events.jsonl" >/dev/null; then
  printf 'FAIL: journal missing Codex-attributed event\n'
  cat "$TMPDIR/.agent0/.memory-events.jsonl"
  exit 1
fi
if ! grep -q 'Updated through Codex hook' "$TMPDIR/.agent0/memory/MEMORY.md"; then
  printf 'FAIL: MEMORY.md was not regenerated\n'
  cat "$TMPDIR/.agent0/memory/MEMORY.md"
  exit 1
fi

echo "PASS: 03-codex-apply-patch-hooks"
