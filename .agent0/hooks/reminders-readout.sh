#!/usr/bin/env bash
# SessionStart hook: inject pending + past-snoozed reminders into the agent's
# context. Reads .agent0/reminders.yaml (the structured replacement for
# the legacy .claude/REMINDERS.md plain-bullet format).
#
# Tool tier (degraded gracefully):
#   1. python3 + PyYAML available -> invoke reminders-helper.py readout
#      (canonical formatted output)
#   2. yq (Go-yq) available -> filter + emit one line per entry as fallback
#   3. neither -> raw YAML inside frame with one-line install advisory
#
# Honors CLAUDE_SKIP_REMINDERS_READOUT=1 or AGENT0_SKIP_REMINDERS_READOUT=1.
# Always exits 0; never blocks SessionStart.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

if [[ "${CLAUDE_SKIP_REMINDERS_READOUT:-0}" = "1" || "${AGENT0_SKIP_REMINDERS_READOUT:-0}" = "1" ]]; then
  exit 0
fi

PROJECT_DIR="$(memory_project_dir "$INPUT")"
YAML_FILE="$PROJECT_DIR/.agent0/reminders.yaml"
HELPER="$PROJECT_DIR/.agent0/skills/remind/scripts/reminders-helper.py"
TODAY="$(date -u +%Y-%m-%d)"

emit_frame_open() { printf '=== REMINDERS ===\n'; }
emit_frame_close() { printf '=== end REMINDERS ===\n'; }
emit_empty() { printf '(no pending reminders)\n'; }

# Tier 1: helper-based readout (Python + PyYAML).
try_helper() {
  [[ -x "$HELPER" ]] || return 1
  python3 -c "import yaml" 2>/dev/null || return 1
  local out
  out="$(AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" python3 "$HELPER" readout 2>/dev/null)"
  if [[ -z "$out" ]]; then
    emit_empty
  else
    printf '%s\n' "$out"
  fi
  return 0
}

# Tier 2: yq-based filter (Go-yq, mikefarah/yq).
try_yq() {
  command -v yq >/dev/null 2>&1 || return 1
  # mikefarah/yq filter: pending OR (snoozed AND snoozed_until <= today)
  local query='.reminders[] | select(.status == "pending" or (.status == "snoozed" and (.snoozed_until // "9999-12-31") <= "'"$TODAY"'")) | "- [" + .id + "] " + .context'
  local out
  out="$(yq eval "$query" "$YAML_FILE" 2>/dev/null)"
  if [[ -z "$out" || "$out" == "null" ]]; then
    emit_empty
    printf '(yq fast-path: minimal format; install pyyaml for full sub-bullets)\n'
  else
    printf '%s\n' "$out"
    printf '(yq fast-path: minimal format; install pyyaml for full sub-bullets)\n'
  fi
  return 0
}

# Tier 3: raw YAML fallback.
emit_raw_fallback() {
  printf 'reminders-degraded-advisory: python3+PyYAML and yq unavailable; emitting raw .agent0/reminders.yaml without filtering\n' >&2
  printf '(yq/python3+yaml absent; install yq or pip install pyyaml for filtered readout)\n'
  cat "$YAML_FILE"
}

emit_frame_open
if [[ ! -r "$YAML_FILE" ]]; then
  emit_empty
elif try_helper; then
  :
elif try_yq; then
  :
else
  emit_raw_fallback
fi
emit_frame_close

exit 0
