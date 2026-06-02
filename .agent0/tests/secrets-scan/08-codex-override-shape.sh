#!/usr/bin/env bash
# .agent0/tests/secrets-scan/08-codex-override-shape.sh
# V8 — Scenario: override rewrite output is runtime-aware (spec 108).
#
# The preflight emits hookSpecificOutput.updatedInput to apply an override
# rewrite. The JSON shape differs by runtime:
#   - Codex CLI requires permissionDecision:"allow" alongside updatedInput,
#     else the rewrite is silently ignored.
#   - Claude Code emits updatedInput-only (no permissionDecision — that would
#     auto-approve the tool call and bypass the permission prompt).
#
# Runtime is detected via memory_runtime() in _memory-hook-lib.sh, which keys
# on CLAUDE_PROJECT_DIR being unset (→ codex-cli) vs set (→ claude-code).
#
# Asserts:
#   (a) Codex payload (no CLAUDE_PROJECT_DIR, cwd in JSON) → emitted JSON has
#       permissionDecision == "allow" AND updatedInput.command present
#   (b) Claude payload (CLAUDE_PROJECT_DIR set) → emitted JSON has NO
#       permissionDecision AND updatedInput.command present
#   (c) both audit a row with runtime field matching the runtime

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
AGENT0_PREFLIGHT="$AGENT0_ROOT/.agent0/hooks/secrets-preflight.sh"

TMPDIR="$(mktemp -d -t spec-108-test-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

REASON="documentation test vector for runtime-aware override shape"
CMD_LINE1='git commit -m "land fixture"'
CMD_LINE2="# OVERRIDE: ${REASON}"
COMMAND="${CMD_LINE1}
${CMD_LINE2}"

# --- (a) Codex runtime: no CLAUDE_PROJECT_DIR, cwd carried in the JSON. ---
codex_json="$(jq -cn --arg cmd "$COMMAND" --arg cwd "$TMPDIR" '{"cwd":$cwd,"tool_input":{"command":$cmd}}')"
codex_stdout="$TMPDIR/codex_stdout.txt"
codex_exit=0
printf '%s' "$codex_json" | env -u CLAUDE_PROJECT_DIR -u AGENT0_PROJECT_DIR bash "$AGENT0_PREFLIGHT" >"$codex_stdout" 2>/dev/null || codex_exit=$?

if [ "$codex_exit" -ne 0 ]; then
  printf 'FAIL: codex override exit=%d, want 0\n' "$codex_exit"
  exit 1
fi

codex_pd="$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' "$codex_stdout" 2>/dev/null || true)"
if [ "$codex_pd" != "allow" ]; then
  printf 'FAIL: codex output permissionDecision=%s, want "allow"\n' "$codex_pd"
  printf 'Got: %s\n' "$(cat "$codex_stdout")"
  exit 1
fi
codex_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command // ""' "$codex_stdout" 2>/dev/null || true)"
if [ -z "$codex_cmd" ]; then
  printf 'FAIL: codex output missing updatedInput.command\n'
  exit 1
fi

# --- (b) Claude runtime: CLAUDE_PROJECT_DIR set. ---
claude_stdout="$TMPDIR/claude_stdout.txt"
claude_exit=0
claude_json="$(jq -cn --arg cmd "$COMMAND" '{"tool_input":{"command":$cmd}}')"
printf '%s' "$claude_json" | env CLAUDE_PROJECT_DIR="$TMPDIR" bash "$AGENT0_PREFLIGHT" >"$claude_stdout" 2>/dev/null || claude_exit=$?

if [ "$claude_exit" -ne 0 ]; then
  printf 'FAIL: claude override exit=%d, want 0\n' "$claude_exit"
  exit 1
fi

claude_pd="$(jq -r '.hookSpecificOutput | has("permissionDecision")' "$claude_stdout" 2>/dev/null || true)"
if [ "$claude_pd" != "false" ]; then
  printf 'FAIL: claude output should NOT carry permissionDecision, got has()=%s\n' "$claude_pd"
  printf 'Got: %s\n' "$(cat "$claude_stdout")"
  exit 1
fi
claude_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command // ""' "$claude_stdout" 2>/dev/null || true)"
if [ -z "$claude_cmd" ]; then
  printf 'FAIL: claude output missing updatedInput.command\n'
  exit 1
fi

# --- (c) audit rows carry the runtime field. ---
AUDIT_LOG="$TMPDIR/.agent0/secrets-audit.jsonl"
if [ ! -f "$AUDIT_LOG" ]; then
  printf 'FAIL: audit log not created at %s\n' "$AUDIT_LOG"
  exit 1
fi
if [ -z "$(jq -c 'select(.runtime == "codex-cli" and .decision == "override-pass-through")' "$AUDIT_LOG")" ]; then
  printf 'FAIL: no codex-cli override-pass-through audit row\n'; cat "$AUDIT_LOG"; exit 1
fi
if [ -z "$(jq -c 'select(.runtime == "claude-code" and .decision == "override-pass-through")' "$AUDIT_LOG")" ]; then
  printf 'FAIL: no claude-code override-pass-through audit row\n'; cat "$AUDIT_LOG"; exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
