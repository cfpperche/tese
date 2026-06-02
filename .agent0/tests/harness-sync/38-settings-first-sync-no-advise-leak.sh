#!/usr/bin/env bash
# Scenario: the dev-only propagation-advise.sh hook registration must NEVER reach
# a consumer's .claude/settings.json — on a first sync (consumer has no file yet)
# OR on a resync of a consumer that already carries a leaked registration.
#
# Regression for the COPY_CHECK_EXCLUDE / merge_settings_json split: strip_excluded
# lives inside the jq merge, but two short-circuits used to bypass it — a missing
# consumer file fell back to a verbatim process_file copy, and a sha-identical file
# returned "up to date" before the jq ran. Both leaked (then permanently persisted)
# the registration. Pre-existing settings tests (05/23) always pre-seed a consumer
# settings.json, so the first-sync path was untested. This guards both halves.
# Asserts:
#   (a) first sync to a settings-LESS consumer creates valid JSON with NO propagation-advise
#   (b) the legit hooks DO ship (governance-gate)
#   (c) a consumer carrying a verbatim-leaked settings.json self-heals on resync

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-016-38-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
HEAL="$TMPDIR/consumer-leaked"
mkdir -p "$SRC/.claude" "$CONSUMER" "$HEAL/.claude"

# Agent0 settings: one legit hook + the dev-only propagation-advise registration.
jq -cn '{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  hooks: {
    PreToolUse: [
      {matcher:"Bash", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/governance-gate.sh"}]}
    ],
    PostToolUse: [
      {matcher:"Edit|Write|MultiEdit", hooks:[{type:"command", command:"bash $CLAUDE_PROJECT_DIR/.agent0/hooks/propagation-advise.sh"}]}
    ]
  }
}' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# ---------------------------------------------------------------------------
# (a)+(b) first sync — consumer has NO .claude/settings.json
# ---------------------------------------------------------------------------
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

actual_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || actual_exit=$?
if [ "$actual_exit" -ne 0 ]; then
  printf 'FAIL: first-sync --apply expected exit 0, got %d\n' "$actual_exit"
  exit 1
fi

DST="$CONSUMER/.claude/settings.json"
if [ ! -f "$DST" ]; then
  printf 'FAIL: first sync did not create consumer settings.json\n'
  exit 1
fi
if ! jq -e . "$DST" >/dev/null 2>&1; then
  printf 'FAIL: first-sync consumer settings.json is not valid JSON\n'
  cat "$DST"
  exit 1
fi
if grep -q "propagation-advise" "$DST"; then
  printf 'FAIL: propagation-advise.sh leaked into first-sync consumer settings.json\n'
  jq . "$DST"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse[] | select(.hooks[].command | test("governance-gate"))' "$DST" >/dev/null; then
  printf 'FAIL: legit governance-gate hook did not ship on first sync\n'
  jq . "$DST"
  exit 1
fi

# ---------------------------------------------------------------------------
# (c) self-heal — consumer carries a verbatim-leaked settings.json (old-tool state)
# ---------------------------------------------------------------------------
cp "$SRC/.claude/settings.json" "$HEAL/.claude/settings.json"   # byte-identical to source = the old leak
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$HEAL/CLAUDE.md"
if ! grep -q "propagation-advise" "$HEAL/.claude/settings.json"; then
  printf 'FAIL: precondition — seeded consumer should carry the leak\n'
  exit 1
fi

heal_exit=0
bash "$TOOL" --apply --agent0-path="$SRC" "$HEAL" >/dev/null 2>&1 || heal_exit=$?
if [ "$heal_exit" -ne 0 ]; then
  printf 'FAIL: self-heal --apply expected exit 0, got %d\n' "$heal_exit"
  exit 1
fi
if grep -q "propagation-advise" "$HEAL/.claude/settings.json"; then
  printf 'FAIL: resync did not strip a previously-leaked propagation-advise registration\n'
  jq . "$HEAL/.claude/settings.json"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse[] | select(.hooks[].command | test("governance-gate"))' "$HEAL/.claude/settings.json" >/dev/null; then
  printf 'FAIL: self-heal dropped the legit governance-gate hook\n'
  exit 1
fi

echo "PASS: 38-settings-first-sync-no-advise-leak"
