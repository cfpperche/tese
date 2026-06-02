#!/usr/bin/env bash
# Scenario: Agent0 upstream's own .claude/settings.json must NOT carry
# permission-mode bypasses or pre-approved permission rules.
#
# Permission modes (`bypassPermissions`, `acceptEdits`, etc.) and `allow:`
# entries are user-ergonomic decisions that belong in `~/.claude/settings.json`
# (user-global) or `.claude/settings.local.json` (gitignored per-machine),
# NOT in the tracked project settings that fresh clones / template-based consumer projects
# inherit verbatim.
#
# sync-harness.sh § merge_settings_json already excludes `permissions` from the
# upstream-owned keys (consumer projects preserve their own permission block on sync), but
# this test guards the upstream baseline itself against drift: a maintainer
# accidentally re-adding `permissions.defaultMode` or a non-empty `allow:` list
# fails CI here.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SETTINGS="$AGENT0_ROOT/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  printf 'FAIL: upstream .claude/settings.json missing at %s\n' "$SETTINGS"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: jq not available; cannot inspect settings.json shape\n' >&2
  exit 0
fi

default_mode="$(jq -r '.permissions.defaultMode // empty' "$SETTINGS")"
if [ -n "$default_mode" ]; then
  printf 'FAIL: upstream .claude/settings.json carries permissions.defaultMode=%s — permission modes are user-ergonomic decisions; move to ~/.claude/settings.json or .claude/settings.local.json\n' "$default_mode"
  exit 1
fi

allow_count="$(jq '(.permissions.allow // []) | length' "$SETTINGS")"
if [ "$allow_count" -gt 0 ]; then
  printf 'FAIL: upstream .claude/settings.json carries %d permissions.allow entries — pre-approved permission rules are user-ergonomic decisions; move to ~/.claude/settings.json or .claude/settings.local.json\n' "$allow_count"
  jq '.permissions.allow' "$SETTINGS"
  exit 1
fi

# permissions.deny is permitted at project level (genuine project policy —
# blocking dangerous commands across all users). permissions.additionalDirectories
# is also permitted (project context). Only defaultMode + allow are policed.

echo "PASS: 34-no-permission-bypass-in-upstream"
