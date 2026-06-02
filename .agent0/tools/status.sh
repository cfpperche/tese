#!/usr/bin/env bash
# Agent0 `status` — on-demand, text-first cockpit over live harness state.
#
# The mid-session sibling of the SessionStart brief (.agent0/hooks/startup-brief.sh):
# same composition, full detail, no byte/line cap, plus git-dirty + next-commands.
# Runtime-neutral: invoke as `/status` (Claude), `$status` (Codex), or
# `! bash .agent0/tools/status.sh` (human). Read-only; always exits 0. (Spec 137.)

set -uo pipefail

# The composition library ships next to this tool — locate it relative to THIS
# script, never the inspected project (they can differ under test).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../hooks" && pwd)"

# Data root (HANDOFF / reminders / routines) — honor AGENT0_PROJECT_DIR like the
# rest of the harness, else the git root of this checkout.
if [ -n "${AGENT0_PROJECT_DIR:-}" ]; then
  PROJECT_DIR="$AGENT0_PROJECT_DIR"
else
  PROJECT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# shellcheck source=../hooks/_brief-compose.sh
. "$HOOKS_DIR/_brief-compose.sh"

# Globals the composition functions read.
INPUT=""
SESSION_FILE="$PROJECT_DIR/.agent0/HANDOFF.md"
TODAY="$(date -u +%Y-%m-%d)"
# Open the per-section caps: status is the FULL on-demand view, unlike the
# bounded SessionStart brief. The library defaults stay small for the hook.
HANDOFF_SECTION_LINES=200
REMINDER_LIMIT=999
REMINDER_TEXT_MAX=2000
export HANDOFF_SECTION_LINES REMINDER_LIMIT REMINDER_TEXT_MAX

git_dirty_block() {
  printf '=== git ===\n'
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    printf '(not a git repo)\n'
    return 0
  fi
  local branch porcelain
  branch="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  porcelain="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null)"
  printf 'branch: %s\n' "$branch"
  if [ -z "$porcelain" ]; then
    printf 'working tree clean\n'
  else
    printf '%s\n' "$porcelain"
  fi
}

next_commands_block() {
  printf '=== next ===\n'
  local any=0 next_actions routines due_count

  next_actions="$(section_body "Next Actions" "$SESSION_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)"
  if [ -n "$next_actions" ]; then
    printf -- '- handoff has queued Next Actions (see above)\n'
    any=1
  fi

  # Pending routines surface their own `/routine run <slug>` invocation.
  routines="$(helper_output routines-readout.sh | grep -oE '/routine run [a-z0-9-]+' | sort -u)"
  if [ -n "$routines" ]; then
    while IFS= read -r r; do
      [ -n "$r" ] && printf -- '- %s\n' "$r" && any=1
    done <<EOF
$routines
EOF
  fi

  # Due reminders only — reuse summarize_reminders' due-date filter so this
  # stays consistent with the === reminders === section above (a future-dated
  # reminder is pending but NOT actionable now).
  due_count="$(summarize_reminders | grep -c '^- \[' || true)"
  if [ "${due_count:-0}" -gt 0 ]; then
    printf -- '- /remind list  (%s due)\n' "$due_count"
    any=1
  fi

  if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
     && [ -n "$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null)" ]; then
    printf -- '- review working-tree changes; commit when ready\n'
    any=1
  fi

  [ "$any" -eq 0 ] && printf '(nothing queued)\n'
}

main() {
  printf 'AGENT0_STATUS\n'
  printf 'generated: %sZ (on-demand, untruncated)\n\n' "$(date -u +%Y-%m-%dT%H:%M:%S)"
  summarize_handoff
  printf '\n'
  git_dirty_block
  printf '\n'
  summarize_reminders
  printf '\n'
  summarize_routines
  printf '\n'
  summarize_memory_decay
  printf '\n'
  next_commands_block
  printf '\nEND_AGENT0_STATUS\n'
  return 0
}

main
exit 0
