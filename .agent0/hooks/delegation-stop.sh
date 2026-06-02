#!/usr/bin/env bash
# .agent0/hooks/delegation-stop.sh
# SubagentStop hook — SHARED MULTI-RUNNER (Claude Code + Codex CLI).
# Appends a close row (event="subagent-stop") to the single canonical
# .agent0/delegation-audit.jsonl, keyed by agent_id, carrying termination
# metadata. Every row carries schema_version / runtime / event. Branches on
# runtime:
#   - Claude: tool_use_id bridge via the per-sub-agent transcript sidecar
#     .meta.json; edit_count from transcript tool_use blocks; exit state from
#     the .agent0/.delegation-state/ loop-budget counter (Claude-only).
#   - Codex:  no sidecar — correlates to the prior subagent-start row by
#     matching agent_id (correlation="agent_id-direct"); edit_count=null,
#     exit=null (loop-budget enforcement deferred for Codex per spec 106).
#
# Fail-open everywhere: missing jq, unparseable payload, unwritable log,
# missing sidecar/transcript — all exit 0 silently. A broken hook must never
# block sub-agent termination or pollute the agent's next turn.
#
# Spec: docs/specs/106-delegation-hooks-multi-runtime/
# Rule: .agent0/context/rules/delegation.md § Audit log + § Codex: convention-only

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
AUDIT_LOG="$PROJECT_DIR/.agent0/delegation-audit.jsonl"
# Loop-budget counter is a Claude-only producer (deferred for Codex) → stays
# in .claude/ per the co-location corollary (harness-home.md).
STATE_DIR="$PROJECT_DIR/.agent0/.delegation-state/agents"
BUDGET="${CLAUDE_DELEGATION_LOOP_BUDGET:-5}"
SCHEMA_VERSION=1

# --- Runtime detection: Claude sets CLAUDE_PROJECT_DIR in hooks; Codex does not. ---
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  RUNTIME="claude-code"
else
  RUNTIME="codex-cli"
fi

# --- Common payload fields (present on both runtimes' SubagentStop) ---
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || true)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null || true)"
LAST_MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)"
STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"

# Mandatory: agent_id. Without it we cannot identify the closing sub-agent.
[ -z "$AGENT_ID" ] && exit 0

# --- Defaults (Codex baseline; the Claude branch overrides these) ---
TOOL_USE_ID=""
EDIT_COUNT="null"
EXIT_JSON="null"
CORRELATION="unmatched"
DISPATCH_TS=""

if [ "$RUNTIME" = "claude-code" ]; then
  # --- Claude Phase 1: bridge to dispatch via sidecar .meta.json ---
  if [ -n "$TRANSCRIPT" ]; then
    META="${TRANSCRIPT%.jsonl}.meta.json"
    if [ -f "$META" ]; then
      TOOL_USE_ID="$(jq -r '.toolUseId // ""' "$META" 2>/dev/null || true)"
    fi
  fi

  # --- Claude Phase 2: count edits in the sub-agent's transcript ---
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    count="$(jq -s '
      [.[]
        | select(.type == "assistant")
        | (.message // [])
        | (.[]?
            | select((type == "object") and (.type == "tool_use") and
                     ((.name == "Edit") or (.name == "Write") or (.name == "MultiEdit"))))
      ] | length
    ' "$TRANSCRIPT" 2>/dev/null || true)"
    case "$count" in
      ''|*[!0-9]*) : ;;
      *)           EDIT_COUNT="$count" ;;
    esac
  fi

  # --- Claude Phase 3: loop-budget exit state ---
  EXIT_STATE="ok"
  FAILS_FILE="$STATE_DIR/$AGENT_ID/consecutive_failures"
  if [ -f "$FAILS_FILE" ]; then
    fails="$(cat "$FAILS_FILE" 2>/dev/null || echo 0)"
    case "$fails" in
      ''|*[!0-9]*) : ;;
      *) [ "$fails" -ge "$BUDGET" ] && EXIT_STATE="loop-budget-exceeded" ;;
    esac
  fi
  EXIT_JSON="$(printf '%s' "$EXIT_STATE" | jq -R -s -c 'rtrimstr("\n")')"

  # --- Claude Phase 4: look up the open dispatch row (event="dispatch") ---
  if [ -f "$AUDIT_LOG" ]; then
    if [ -n "$TOOL_USE_ID" ]; then
      DISPATCH_TS="$(jq -r --arg tu "$TOOL_USE_ID" '
        select(.event == "dispatch" and .tool_use_id == $tu) | .ts
      ' "$AUDIT_LOG" 2>/dev/null | tail -1 || true)"
      [ -n "$DISPATCH_TS" ] && CORRELATION="tool_use_id"
    fi
    if [ -z "$DISPATCH_TS" ] && [ -n "$SESSION_ID" ] && [ -n "$AGENT_TYPE" ]; then
      DISPATCH_TS="$(jq -r --arg sid "$SESSION_ID" --arg at "$AGENT_TYPE" '
        select(.event == "dispatch" and .session_id == $sid and .subagent_type == $at) | .ts
      ' "$AUDIT_LOG" 2>/dev/null | tail -1 || true)"
      [ -n "$DISPATCH_TS" ] && CORRELATION="heuristic-session-type"
    fi
  fi
else
  # --- Codex: correlate to the subagent-start row by agent_id ---
  # No sidecar, no tool_use_id; loop-budget + edit attribution are deferred,
  # so exit and edit_count stay null (the Codex baseline defaults above).
  if [ -f "$AUDIT_LOG" ]; then
    DISPATCH_TS="$(jq -r --arg aid "$AGENT_ID" '
      select(.event == "subagent-start" and .agent_id == $aid) | .ts
    ' "$AUDIT_LOG" 2>/dev/null | tail -1 || true)"
    [ -n "$DISPATCH_TS" ] && CORRELATION="agent_id-direct"
  fi
fi

CLOSE_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
[ -z "$CLOSE_TS" ] && exit 0

DURATION_MS="null"
if [ -n "$DISPATCH_TS" ]; then
  start_epoch="$(date -u -d "$DISPATCH_TS" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$DISPATCH_TS" +%s 2>/dev/null || true)"
  end_epoch="$(date -u -d "$CLOSE_TS" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$CLOSE_TS" +%s 2>/dev/null || true)"
  if [ -n "$start_epoch" ] && [ -n "$end_epoch" ]; then
    DURATION_MS=$(( (end_epoch - start_epoch) * 1000 ))
  fi
fi

LAST_MSG_HEAD="$(printf '%s' "$LAST_MSG" | tr '\n\r' '  ' | cut -c 1-200)"

mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || exit 0

# Probe writability before invoking flock (avoid the sticky-redirect gotcha
# in delegation.md § Gotchas about bare `exec` with 2>/dev/null).
if ! ( : >>"$AUDIT_LOG" ) 2>/dev/null; then
  exit 0
fi

close_row="$(jq -c -n \
  --argjson schema_version "$SCHEMA_VERSION" \
  --arg runtime "$RUNTIME" \
  --arg ts "$CLOSE_TS" \
  --arg event "subagent-stop" \
  --arg session_id "$SESSION_ID" \
  --arg agent_id "$AGENT_ID" \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg agent_type "$AGENT_TYPE" \
  --argjson exit "$EXIT_JSON" \
  --argjson duration_ms "$DURATION_MS" \
  --argjson edit_count "$EDIT_COUNT" \
  --arg last_assistant_message_head "$LAST_MSG_HEAD" \
  --arg agent_transcript_path "$TRANSCRIPT" \
  --arg correlation "$CORRELATION" \
  --argjson stop_hook_active "$STOP_HOOK_ACTIVE" \
  '{schema_version:$schema_version, runtime:$runtime, ts:$ts, event:$event,
    session_id:$session_id, agent_id:$agent_id,
    tool_use_id:(if $tool_use_id == "" then null else $tool_use_id end),
    agent_type:$agent_type, exit:$exit,
    duration_ms:$duration_ms, edit_count:$edit_count,
    last_assistant_message_head:$last_assistant_message_head,
    agent_transcript_path:$agent_transcript_path,
    correlation:$correlation, stop_hook_active:$stop_hook_active}' 2>/dev/null || true)"

[ -z "$close_row" ] && exit 0

# Atomic append via flock.
(
  flock 9
  printf '%s\n' "$close_row" >>"$AUDIT_LOG"
) 9>"$AUDIT_LOG.lock" 2>/dev/null || true

exit 0
