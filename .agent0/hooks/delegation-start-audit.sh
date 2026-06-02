#!/usr/bin/env bash
# .agent0/hooks/delegation-start-audit.sh
# SubagentStart hook — CODEX observability (non-blocking).
#
# Codex's SubagentStart CANNOT block a spawn ("continue:false ... doesn't stop
# the subagent from starting"), so this hook only AUDITS: it appends a
# "subagent-start" row to the single canonical .agent0/delegation-audit.jsonl,
# giving the shared delegation-stop close row a correlation/duration anchor
# (paired by agent_id → correlation="agent_id-direct").
#
# The Codex SubagentStart payload carries NO brief/instruction text (verified
# 0.134.0: session_id, turn_id, transcript_path, cwd, hook_event_name, model,
# permission_mode, agent_id, agent_type), so this hook records
# brief_observable=false / formatted=null — it observes that a dispatch
# happened, never whether the 5-field contract was followed. That discipline is
# convention-only on Codex; see .agent0/context/rules/delegation.md § Codex: convention-only.
#
# Fail-open / never-block: missing jq, unparseable payload, unwritable log —
# all exit 0 silently.
#
# Spec: docs/specs/106-delegation-hooks-multi-runtime/
# Rule: .agent0/context/rules/delegation.md § Audit log (Codex subagent-start row)

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
AUDIT_LOG="$PROJECT_DIR/.agent0/delegation-audit.jsonl"
SCHEMA_VERSION=1

# Registered only by Codex (Claude's "start" record is the gate dispatch row),
# but detect defensively so a stray Claude invocation labels itself correctly.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  RUNTIME="claude-code"
else
  RUNTIME="codex-cli"
fi

AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || true)"
TURN_ID="$(printf '%s' "$INPUT" | jq -r '.turn_id // ""' 2>/dev/null || true)"

# Mandatory: agent_id — the correlation key the close row pairs against.
[ -z "$AGENT_ID" ] && exit 0

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
[ -z "$TS" ] && exit 0

mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || exit 0

# Probe writability before invoking flock (sticky-redirect gotcha — see
# delegation.md § Gotchas).
if ! ( : >>"$AUDIT_LOG" ) 2>/dev/null; then
  exit 0
fi

start_row="$(jq -c -n \
  --argjson schema_version "$SCHEMA_VERSION" \
  --arg runtime "$RUNTIME" \
  --arg ts "$TS" \
  --arg event "subagent-start" \
  --arg session_id "$SESSION_ID" \
  --arg agent_id "$AGENT_ID" \
  --arg agent_type "$AGENT_TYPE" \
  --arg turn_id "$TURN_ID" \
  '{schema_version:$schema_version, runtime:$runtime, ts:$ts, event:$event,
    session_id:$session_id, agent_id:$agent_id, agent_type:$agent_type,
    turn_id:(if $turn_id == "" then null else $turn_id end),
    brief_observable:false, formatted:null}' 2>/dev/null || true)"

[ -z "$start_row" ] && exit 0

(
  flock 9
  printf '%s\n' "$start_row" >>"$AUDIT_LOG"
) 9>"$AUDIT_LOG.lock" 2>/dev/null || true

exit 0
