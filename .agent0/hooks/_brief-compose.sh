#!/usr/bin/env bash
# Shared composition library for the Agent0 startup brief and the on-demand
# `status` tool (spec 137).
#
# This file carries ONLY composition: functions that read harness state
# (handoff / reminders / routines / memory-decay / githooks) and emit plain
# text sections. It is deliberately runtime-emit-neutral — it does NOT wrap
# output in Claude hook-JSON, does NOT truncate, and does NOT manage session
# state. Those concerns stay in the caller:
#   - .agent0/hooks/startup-brief.sh  → emit_context (JSON vs plain), trim_*, init_session_state
#   - .agent0/tools/status.sh         → prints the composition verbatim, untruncated
#
# Callers must set the following globals before invoking these functions:
#   INPUT                       raw hook payload (may be empty "")
#   PROJECT_DIR                 repo root
#   SESSION_FILE                "$PROJECT_DIR/.agent0/HANDOFF.md"
#   TODAY                       date -u +%Y-%m-%d
# Optional tunables (callers may override; sensible defaults assumed by callers):
#   HANDOFF_SECTION_LINES REMINDER_LIMIT REMINDER_TEXT_MAX
#
# The library locates its sibling readout helpers relative to its OWN path
# (it lives in .agent0/hooks/ alongside them), so callers in other directories
# — e.g. .agent0/tools/status.sh — resolve them correctly.

_BRIEF_COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section_body() {
  local heading="$1" file="$2"
  awk -v heading="$heading" '
    $0 == "## " heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$file" 2>/dev/null
}

summarize_handoff_section() {
  local heading="$1" body line display count=0
  body="$(section_body "$heading" "$SESSION_FILE")"
  # Flatten-safe sub-section marker (spec 125): '▸' makes Current State /
  # Active Work / Next Actions distinguishable from content bullets even when
  # the renderer collapses newlines into one physical line.
  printf '%s\n' "▸ $heading:"
  if [ -z "$body" ]; then
    printf '  - (empty)\n'
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "---"|"# "*|"_"*) continue ;;
    esac
    display="${line#- }"
    printf '  - %s\n' "$display"
    count=$((count + 1))
    [ "$count" -ge "${HANDOFF_SECTION_LINES:-2}" ] && break
  done <<EOF
$body
EOF
  [ "$count" -gt 0 ] || printf '  - (empty)\n'
}

summarize_handoff() {
  if [ ! -f "$SESSION_FILE" ]; then
    printf '=== handoff ===\n'
    printf "%s\n" "- '.agent0/HANDOFF.md' missing; create it to enable handoff."
    return 0
  fi

  printf '=== handoff ===\n'
  summarize_handoff_section "Current State"
  summarize_handoff_section "Active Work"
  summarize_handoff_section "Next Actions"
  printf 'Full handoff: .agent0/HANDOFF.md\n'
}

githooks_advisory() {
  # Honor both the Claude-named and the runtime-neutral skip flag, matching
  # summarize_reminders / summarize_routines (dogfood D3 parity nit).
  if [[ -d "$PROJECT_DIR/.githooks" && "${CLAUDE_SKIP_GITHOOKS_HINT:-0}" != "1" && "${AGENT0_SKIP_GITHOOKS_HINT:-0}" != "1" ]]; then
    local current_hookspath
    current_hookspath="$(git -C "$PROJECT_DIR" config --get core.hooksPath 2>/dev/null || true)"
    if [[ "$current_hookspath" != ".githooks" ]]; then
      printf '=== githooks ===\n'
      printf 'Native git hooks NOT activated (gitleaks pre-commit inert).\n'
      printf 'Run once: git config core.hooksPath .githooks\n'
    fi
  fi
}

helper_output() {
  local script="$1"
  [ -x "$_BRIEF_COMPOSE_DIR/$script" ] || return 0
  printf '%s' "$INPUT" | env -u CLAUDE_PROJECT_DIR AGENT0_PROJECT_DIR="$PROJECT_DIR" bash "$_BRIEF_COMPOSE_DIR/$script" 2>/dev/null || true
}

summarize_reminders() {
  if [[ "${CLAUDE_SKIP_REMINDERS_READOUT:-0}" = "1" || "${AGENT0_SKIP_REMINDERS_READOUT:-0}" = "1" ]]; then
    return 0
  fi

  local out body total=0 line entry="" due="" include
  out="$(helper_output reminders-readout.sh)"
  body="$(printf '%s\n' "$out" | awk '
    /^=== REMINDERS ===$/ { in_body=1; next }
    /^=== end REMINDERS ===$/ { in_body=0; next }
    in_body { print }
  ')"
  [ -n "$body" ] || return 0
  if printf '%s\n' "$body" | grep -qx '(no pending reminders)'; then
    return 0
  fi

  printf '=== reminders ===\n'

  flush_reminder() {
    local compact
    [ -n "$entry" ] || return 0
    include=0
    if [ -z "$due" ] || [[ "$due" < "$TODAY" || "$due" == "$TODAY" ]]; then
      include=1
    fi
    if [ "$include" -eq 1 ]; then
      total=$((total + 1))
      if [ "$total" -le "${REMINDER_LIMIT:-5}" ]; then
        compact="${entry%%$'\n'*}"
        if [ "${#compact}" -gt "${REMINDER_TEXT_MAX:-220}" ]; then
          compact="${compact:0:${REMINDER_TEXT_MAX:-220}}..."
        fi
        [ -n "$due" ] && compact+=" - due: $due"
        printf '%s\n' "$compact"
      fi
    fi
  }

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "- ["*)
        flush_reminder
        entry="$line"$'\n'
        due=""
        ;;
      "  "*|"    "*)
        entry+="$line"$'\n'
        case "$line" in
          *"due: "*) due="${line##*due: }" ;;
        esac
        ;;
    esac
  done <<EOF
$body
EOF
  flush_reminder
  if [ "$total" -eq 0 ]; then
    printf '(no due or unscheduled reminders)\n'
  elif [ "$total" -gt "${REMINDER_LIMIT:-5}" ]; then
    printf '... %s more reminder(s); run /remind list for the full list.\n' "$((total - ${REMINDER_LIMIT:-5}))"
  fi
}

summarize_routines() {
  if [[ "${CLAUDE_SKIP_ROUTINES_READOUT:-0}" = "1" || "${AGENT0_SKIP_ROUTINES_READOUT:-0}" = "1" ]]; then
    return 0
  fi

  local out
  out="$(helper_output routines-readout.sh)"
  [ -n "$out" ] || return 0
  printf '%s\n' "$out"
}

summarize_memory_decay() {
  local out
  out="$(helper_output memory-decay-readout.sh)"
  [ -n "$out" ] || return 0
  if printf '%s\n' "$out" | grep -qxF '(no stale entries)'; then
    return 0
  fi
  printf '%s\n' "$out"
}

context_pointer() {
  printf '=== context ===\n'
  printf 'Rules live in .agent0/context/rules/. Prompt turns receive bounded capsules from context-inject.sh.\n'
  printf 'For full inventory: AGENT0_CONTEXT_DIAGNOSTIC=1 bash .agent0/hooks/context-inject.sh <payload.json\n'
}
