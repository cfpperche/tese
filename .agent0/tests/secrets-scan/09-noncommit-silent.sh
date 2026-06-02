#!/usr/bin/env bash
# .agent0/tests/secrets-scan/09-noncommit-silent.sh
# V9 — Scenario: non-commit Bash exits silently with NO audit row (spec 108).
#
# Under Codex's broad `^Bash$` matcher (no command-string `if` layer) the hook
# sees every Bash call. The prior `skip-not-commit` audit row was dropped so the
# log doesn't become a shell-activity firehose. A non-`git commit` command must
# exit 0 and write nothing to secrets-audit.jsonl.
#
# Asserts:
#   (a) non-commit command (e.g. `ls -la`) → exit 0
#   (b) no audit log file created (no row written)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
AGENT0_PREFLIGHT="$AGENT0_ROOT/.agent0/hooks/secrets-preflight.sh"

TMPDIR="$(mktemp -d -t spec-108-test-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q

export CLAUDE_PROJECT_DIR="$TMPDIR"

for CMD in 'ls -la' 'git status' 'git add foo.txt' 'git diff --stat'; do
  stdin_json="$(jq -cn --arg cmd "$CMD" '{"tool_input":{"command":$cmd}}')"
  hook_exit=0
  printf '%s' "$stdin_json" | bash "$AGENT0_PREFLIGHT" >/dev/null 2>&1 || hook_exit=$?
  if [ "$hook_exit" -ne 0 ]; then
    printf 'FAIL: non-commit command "%s" exit=%d, want 0\n' "$CMD" "$hook_exit"
    exit 1
  fi
done

AUDIT_LOG="$TMPDIR/.agent0/secrets-audit.jsonl"
if [ -f "$AUDIT_LOG" ]; then
  printf 'FAIL: audit log was created for non-commit commands — skip-not-commit spam not suppressed\n'
  cat "$AUDIT_LOG"
  exit 1
fi

# Note: 'git add foo.txt' / 'git diff --stat' are the adversarial ones — the
# is_git_commit matcher must NOT treat a non-commit git subcommand as a commit.
# (A string literally containing "git commit", e.g. an echo, IS a known regex
# false-positive that audits passthrough — out of scope for this test.)
printf 'PASS: %s\n' "$(basename "$0")"
