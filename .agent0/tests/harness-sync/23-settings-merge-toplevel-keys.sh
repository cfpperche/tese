#!/usr/bin/env bash
# Scenario: settings.json merge preserves top-level keys beyond .hooks.
# Regression test for the bug where merge_settings_json only emitted {hooks: ...},
# dropping $schema / permissions / env / model from both sides.
#
# History note: statusLine was previously in the harness override whitelist; it
# was extracted to user-global ~/.claude/settings.json on 2026-05-27, so this
# test no longer asserts harness→consumer statusLine propagation. Instead,
# assertion (b) verifies the inverse contract: a consumer-side statusLine is
# preserved by the merge (since statusLine is no longer harness-owned).
#
# Asserts:
#   (a) Agent0's $schema propagates when consumer project lacks it
#   (b) consumer project's statusLine preserved (NOT overwritten; harness no longer owns this key)
#   (c) consumer project's permissions preserved (Agent0 owns $schema + hooks only)
#   (d) consumer-only top-level key (`env`) preserved
#   (e) hooks merge still works (regression check on the original mechanism)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-21-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude" "$CONSUMER/.claude"

# Agent0 settings: $schema + hooks (no statusLine, no permissions, no env)
jq -cn '{
  "$schema": "https://example.com/schema.json",
  hooks: {
    SessionStart: [
      {matcher:"*", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/session-start.sh"}]}
    ]
  }
}' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# Consumer project settings: statusLine (consumer-owned, set locally) + permissions + env + a hook
jq -cn '{
  statusLine: {type:"command", command:"node /home/operator/.claude/scripts/statusline.mjs"},
  permissions: {defaultMode:"acceptEdits", allow:["Bash(npm test)"], deny:[]},
  env: {CONSUMER_ONLY_VAR: "value"},
  hooks: {
    PreToolUse: [
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.claude/hooks/consumer-hook.sh"}]}
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

# (a) Agent0's $schema propagated
schema="$(jq -r '."$schema" // empty' "$CONSUMER/.claude/settings.json")"
if [ "$schema" != "https://example.com/schema.json" ]; then
  printf 'FAIL: $schema not propagated (got %q)\n' "$schema"
  jq . "$CONSUMER/.claude/settings.json"
  exit 1
fi

# (b) Consumer's statusLine preserved (NOT overwritten — harness no longer owns this key)
statusline_cmd="$(jq -r '.statusLine.command // empty' "$CONSUMER/.claude/settings.json")"
if [ "$statusline_cmd" != "node /home/operator/.claude/scripts/statusline.mjs" ]; then
  printf 'FAIL: consumer statusLine not preserved (got %q)\n' "$statusline_cmd"
  jq . "$CONSUMER/.claude/settings.json"
  exit 1
fi

# (c) Consumer project's permissions preserved (NOT overwritten by Agent0 — Agent0 has none)
perms_mode="$(jq -r '.permissions.defaultMode // empty' "$CONSUMER/.claude/settings.json")"
if [ "$perms_mode" != "acceptEdits" ]; then
  printf 'FAIL: consumer project permissions.defaultMode not preserved (got %q)\n' "$perms_mode"
  exit 1
fi
perms_allow="$(jq -r '.permissions.allow[0] // empty' "$CONSUMER/.claude/settings.json")"
if [ "$perms_allow" != "Bash(npm test)" ]; then
  printf 'FAIL: consumer project permissions.allow not preserved (got %q)\n' "$perms_allow"
  exit 1
fi

# (d) Consumer project-only top-level key (env) preserved
env_val="$(jq -r '.env.CONSUMER_ONLY_VAR // empty' "$CONSUMER/.claude/settings.json")"
if [ "$env_val" != "value" ]; then
  printf 'FAIL: consumer project.env.CONSUMER_ONLY_VAR not preserved (got %q)\n' "$env_val"
  exit 1
fi

# (e) Hooks merged correctly (consumer project's PreToolUse retained, Agent0's SessionStart added)
pre_count="$(jq -r '.hooks.PreToolUse | length' "$CONSUMER/.claude/settings.json")"
ss_count="$(jq -r '.hooks.SessionStart | length' "$CONSUMER/.claude/settings.json")"
if [ "$pre_count" -ne 1 ] || [ "$ss_count" -ne 1 ]; then
  printf 'FAIL: hooks merge wrong — PreToolUse=%s SessionStart=%s\n' "$pre_count" "$ss_count"
  jq . "$CONSUMER/.claude/settings.json"
  exit 1
fi

echo "PASS: 23-settings-merge-toplevel-keys"
