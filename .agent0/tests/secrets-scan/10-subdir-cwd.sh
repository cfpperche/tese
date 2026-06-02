#!/usr/bin/env bash
# .agent0/tests/secrets-scan/10-subdir-cwd.sh
# V10 — Scenario: audit log lands at repo root when invoked from a subdir (spec 108).
#
# A Codex session can start in a subdirectory. The hook resolves the project
# root via memory_project_dir() (git rev-parse --show-toplevel), not the raw
# cwd, so the audit log must land at <repo-root>/.agent0/secrets-audit.jsonl,
# NOT <subdir>/.agent0/secrets-audit.jsonl.
#
# Asserts:
#   (a) a blocked commit issued with cwd = a nested subdir
#   (b) audit log is written at the repo ROOT, not the subdir
#   (c) no .agent0/secrets-audit.jsonl exists under the subdir

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
AGENT0_PREFLIGHT="$AGENT0_ROOT/.agent0/hooks/secrets-preflight.sh"

TMPDIR="$(mktemp -d -t spec-108-test-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
SUBDIR="$TMPDIR/packages/nested/deep"
mkdir -p "$SUBDIR"

# A dangerous shape (--no-verify) so the hook reaches the reject-shape audit path.
COMMAND='git commit --no-verify -m "x"'

# Codex-style payload: no CLAUDE_PROJECT_DIR, cwd is the nested subdir.
stdin_json="$(jq -cn --arg cmd "$COMMAND" --arg cwd "$SUBDIR" '{"cwd":$cwd,"tool_input":{"command":$cmd}}')"
hook_exit=0
printf '%s' "$stdin_json" | env -u CLAUDE_PROJECT_DIR -u AGENT0_PROJECT_DIR bash "$AGENT0_PREFLIGHT" >/dev/null 2>&1 || hook_exit=$?

# (a) reject-shape exits 2
if [ "$hook_exit" -ne 2 ]; then
  printf 'FAIL: dangerous shape exit=%d, want 2\n' "$hook_exit"
  exit 1
fi

# (b) audit log at repo ROOT
ROOT_AUDIT="$TMPDIR/.agent0/secrets-audit.jsonl"
if [ ! -f "$ROOT_AUDIT" ]; then
  printf 'FAIL: audit log not at repo root %s\n' "$ROOT_AUDIT"
  exit 1
fi
if [ -z "$(jq -c 'select(.decision == "reject-shape" and .runtime == "codex-cli")' "$ROOT_AUDIT")" ]; then
  printf 'FAIL: no reject-shape/codex-cli row at repo root\n'; cat "$ROOT_AUDIT"; exit 1
fi

# (c) NO audit log under the subdir
if [ -f "$SUBDIR/.agent0/secrets-audit.jsonl" ]; then
  printf 'FAIL: audit log wrongly written under subdir %s\n' "$SUBDIR/.agent0/secrets-audit.jsonl"
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
