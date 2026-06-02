#!/usr/bin/env bash
# .agent0/hooks/delegation-verify.sh
# SubagentStop hook — SHARED MULTI-RUNNER (Claude Code + Codex CLI).
# Runs the project validator ONCE at delegated-task close (the DONE_WHEN
# enforcement point), keyed by the documented agent_id. Replaces the deleted
# per-edit post-edit-validate.sh (spec 111): the validator's full suite now
# runs at SubagentStop instead of on every Edit/Write/MultiEdit.
#
# Decision (exit codes):
#   pass (ok=true)                      → exit 0, reset failure counter,
#                                         surface advisory family (lint/typecheck/tdd).
#   fail (ok=false) + !stop_hook_active → exit 2 (block + continue): the
#                                         sub-agent gets one focused continuation
#                                         to fix the failing checks.
#   fail (ok=false) +  stop_hook_active → exit 0 (accept closure as partial-result):
#                                         already continued once and still failing,
#                                         so escalate rather than loop forever.
#
# stop_hook_active is the primary loop guard (Claude's native stop-loop-prevention
# signal, present on SubagentStop — see delegation-stop.sh which already reads it);
# the agent_id-keyed counter at .agent0/.delegation-state/agents/<id>/consecutive_failures
# is forensic and is the value delegation-stop.sh reads for the close row's `exit`
# field. delegation-verify.sh is the WRITER of that counter (took over from
# post-edit-validate.sh); delegation-stop.sh is the reader. The two hooks run in
# PARALLEL (Claude runs all matching SubagentStop hooks concurrently) and share no
# ordering — coordination is the counter file, never a sentinel.
#
# Fail-open everywhere: missing jq, missing/non-exec/unparseable validator,
# unwritable state — all exit 0 silently. A broken verifier must NEVER permanently
# block sub-agent termination.
#
# bash 3.2-compatible: no associative arrays, no mapfile.
#
# Spec: docs/specs/111-delegation-verify-subagent-stop/
# Rule: .agent0/context/rules/delegation.md § Post-edit validator loop (stop-time)
#   .agent0/validators/run.sh           — the validator invoked (JSON contract)
#   .agent0/hooks/delegation-stop.sh     — sibling SubagentStop audit hook (reads the counter)
#   .agent0/hooks/_memory-hook-lib.sh    — memory_project_dir / memory_runtime

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh" 2>/dev/null || true

if command -v memory_project_dir >/dev/null 2>&1; then
  PROJECT_DIR="$(memory_project_dir "$INPUT")"
  RUNTIME="$(memory_runtime "$INPUT")"
else
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
  RUNTIME="claude-code"
fi

# --- Delegated-stop gate: agent_id is the actor discriminator on both runtimes. ---
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || true)"
[ -z "$AGENT_ID" ] && exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || true)"
STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
SUBAGENT_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)"

AUDIT_LOG="$PROJECT_DIR/.agent0/delegation-audit.jsonl"
STATE_DIR="$PROJECT_DIR/.agent0/.delegation-state/agents/$AGENT_ID"
FAILS_FILE="$STATE_DIR/consecutive_failures"
SCHEMA_VERSION=1

# --- Validator cwd: a worktree-isolated sub-agent closes in its worktree, so
# prefer the sub-agent's cwd; fall back to the git toplevel, then PROJECT_DIR. ---
VALIDATOR_CWD="$PROJECT_DIR"
if [ -n "$SUBAGENT_CWD" ] && [ -d "$SUBAGENT_CWD" ]; then
  toplevel="$(git -C "$SUBAGENT_CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$toplevel" ]; then
    VALIDATOR_CWD="$toplevel"
  else
    VALIDATOR_CWD="$SUBAGENT_CWD"
  fi
fi

# --- Validator resolution chain — first executable wins; else fail-open. ---
VALIDATOR=""
if [ -n "${CLAUDE_DELEGATION_VALIDATOR:-}" ] && [ -x "${CLAUDE_DELEGATION_VALIDATOR:-}" ]; then
  VALIDATOR="$CLAUDE_DELEGATION_VALIDATOR"
elif [ -x "$PROJECT_DIR/.agent0/validators/run.sh" ]; then
  VALIDATOR="$PROJECT_DIR/.agent0/validators/run.sh"
else
  exit 0
fi

# --- Run the validator; capture stdout (JSON contract) + stderr (advisory lines). ---
VALIDATOR_STDERR_FILE="$(mktemp 2>/dev/null || mktemp -t delegation-verify-stderr)"
VALIDATOR_OUT="$( ( cd "$VALIDATOR_CWD" && "$VALIDATOR" ) 2>"$VALIDATOR_STDERR_FILE" || true )"
VALIDATOR_OWN_STDERR="$(cat "$VALIDATOR_STDERR_FILE" 2>/dev/null || true)"
rm -f "$VALIDATOR_STDERR_FILE" 2>/dev/null || true

# Surface the validator's own advisory family (lint-advisory: / typecheck-advisory:)
# regardless of pass/fail — relocated verbatim from post-edit-validate.sh.
if [ -n "$VALIDATOR_OWN_STDERR" ]; then
  printf '%s\n' "$VALIDATOR_OWN_STDERR" >&2
fi

# has("ok") keeps `false` (real fail) distinct from missing (broken → fail-open).
OK="$(printf '%s' "$VALIDATOR_OUT" | jq -r 'if type == "object" and has("ok") then (.ok | tostring) else "" end' 2>/dev/null || true)"
if [ "$OK" != "true" ] && [ "$OK" != "false" ]; then
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null || true

# --- Emit a forensic verify row (best-effort; never blocks). ---
emit_verify_row() {
  decision="$1"
  v_exit="$2"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [ -z "$ts" ] && return 0
  row="$(jq -c -n \
    --argjson schema_version "$SCHEMA_VERSION" \
    --arg runtime "$RUNTIME" \
    --arg ts "$ts" \
    --arg event "subagent-verify" \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE" \
    --arg decision "$decision" \
    --argjson validator_exit "${v_exit:-null}" \
    --argjson stop_hook_active "$STOP_HOOK_ACTIVE" \
    '{schema_version:$schema_version, runtime:$runtime, ts:$ts, event:$event,
      session_id:$session_id, agent_id:$agent_id, agent_type:$agent_type,
      decision:$decision, validator_exit:$validator_exit,
      stop_hook_active:$stop_hook_active}' 2>/dev/null || true)"
  [ -z "$row" ] && return 0
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  ( : >>"$AUDIT_LOG" ) 2>/dev/null || return 0
  ( flock 9; printf '%s\n' "$row" >>"$AUDIT_LOG" ) 9>"$AUDIT_LOG.lock" 2>/dev/null || true
}

V_EXIT="$(printf '%s' "$VALIDATOR_OUT" | jq -r '.exit // "null"' 2>/dev/null || echo null)"
case "$V_EXIT" in ''|*[!0-9-]*) V_EXIT="null" ;; esac

if [ "$OK" = "true" ]; then
  # Pass: reset the consecutive-failure counter; surface tdd advisories; accept.
  printf '0' > "$FAILS_FILE" 2>/dev/null || true
  TDD_ADV="$(printf '%s' "$VALIDATOR_OUT" | jq -r 'if type == "object" and has("warnings") then (.warnings[] | "tdd-advisory: " + .message) else empty end' 2>/dev/null || true)"
  [ -n "$TDD_ADV" ] && printf '%s\n' "$TDD_ADV" >&2
  emit_verify_row "pass" "$V_EXIT"
  exit 0
fi

# --- Fail path: increment the forensic counter (read by delegation-stop.sh). ---
COUNT=0
if [ -f "$FAILS_FILE" ]; then
  COUNT="$(tr -cd '0-9' < "$FAILS_FILE" 2>/dev/null || true)"
  [ -z "$COUNT" ] && COUNT=0
fi
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$FAILS_FILE" 2>/dev/null || true

V_CMD="$(printf '%s' "$VALIDATOR_OUT" | jq -r '.command // ""' 2>/dev/null || true)"
V_STDOUT="$(printf '%s' "$VALIDATOR_OUT" | jq -r '.stdout // ""' 2>/dev/null | tail -c 1024 || true)"
V_STDERR="$(printf '%s' "$VALIDATOR_OUT" | jq -r '.stderr // ""' 2>/dev/null | tail -c 1024 || true)"

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Already continued once and still failing → accept closure as a partial-result
  # rather than blocking again (avoids an infinite stop→continue→stop loop).
  emit_verify_row "exhausted" "$V_EXIT"
  cat >&2 <<EOF
delegation-verify: validation STILL failing after a continuation — accepting
closure as a PARTIAL RESULT (sub-agent $AGENT_ID, $COUNT consecutive failures).

Report to the parent what passed, what is still failing, and what remains.

Validator command: $V_CMD
--- validator stdout (tail) ---
$V_STDOUT
--- validator stderr (tail) ---
$V_STDERR

Rule: .agent0/context/rules/delegation.md § Post-edit validator loop (stop-time)
EOF
  exit 0
fi

# First failing stop → block closure, request one focused continuation.
emit_verify_row "blocked" "$V_EXIT"
cat >&2 <<EOF
delegation-verify: delegated task verification FAILED (sub-agent $AGENT_ID).
Fix the failing checks before closing; you get one focused continuation, after
which a still-failing close is accepted as a partial result.

Validator command: $V_CMD
Validator exit:    $V_EXIT
--- validator stdout (tail) ---
$V_STDOUT
--- validator stderr (tail) ---
$V_STDERR

Rule: .agent0/context/rules/delegation.md § Post-edit validator loop (stop-time)
EOF
exit 2
