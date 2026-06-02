#!/usr/bin/env bash
# Scenario: settings.json merge (additive, no replace).
# Asserts:
#   (a) Agent0 hook entries appended to consumer project's settings.json
#   (b) consumer project's pre-existing entries preserved
#   (c) no duplicates (dedup by matcher + hooks[].command)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-05-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

# Agent0 settings: 3 PreToolUse hooks
jq -cn '{
  hooks: {
    PreToolUse: [
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/governance-gate.sh"}]},
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/secrets-preflight.sh"}]},
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.claude/hooks/runtime-pre-mark.sh"}]}
    ],
    SessionStart: [
      {matcher:"*", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/session-start.sh"}]}
    ]
  }
}' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# Consumer project settings: governance-gate (matches Agent0) + a consumer-only custom hook
jq -cn '{
  hooks: {
    PreToolUse: [
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/governance-gate.sh"}]},
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.claude/hooks/consumer-only-hook.sh"}]}
    ]
  }
}' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer project\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

actual_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || actual_exit=$?

if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: --apply expected exit 0, got %d\n' "$actual_exit"
  exit 1
fi

# Assert: consumer project's PreToolUse now has 4 entries (governance dedup'd, secrets+runtime-pre-mark added, consumer-only preserved)
pre_count="$(jq -r '.hooks.PreToolUse | length' "$CONSUMER/.claude/settings.json")"
if [ "$pre_count" -ne 4 ]; then
  printf 'FAIL: expected 4 PreToolUse entries, got %s\n' "$pre_count"
  jq . "$CONSUMER/.claude/settings.json"
  exit 1
fi

# Assert: consumer-only-hook preserved
if ! jq -e '.hooks.PreToolUse[] | select(.hooks[].command | test("consumer-only-hook"))' "$CONSUMER/.claude/settings.json" >/dev/null; then
  printf 'FAIL: consumer-only-hook.sh entry was dropped\n'
  exit 1
fi

# Assert: SessionStart now exists
if ! jq -e '.hooks.SessionStart | length == 1' "$CONSUMER/.claude/settings.json" >/dev/null; then
  printf 'FAIL: SessionStart should have 1 entry\n'
  exit 1
fi

# Assert: governance-gate NOT duplicated
gov_count="$(jq -r '.hooks.PreToolUse | map(select(.hooks[].command | test("governance-gate"))) | length' "$CONSUMER/.claude/settings.json")"
if [ "$gov_count" -ne 1 ]; then
  printf 'FAIL: governance-gate should appear once, got %s\n' "$gov_count"
  exit 1
fi

echo "PASS: 05-settings-merge-additive"
