#!/usr/bin/env bash
# .agent0/tests/secrets-scan/11-codex-rewrite-reaches-bash.sh
# V11 — Scenario: the CODEX-shape override rewrite reaches Bash end-to-end (spec 108).
#
# This is the mechanical core of acceptance scenario V8 ("live Codex dogfood
# proves the rewrite reached Bash"). It validates everything a REPO can validate
# without the Codex binary:
#
#   1. Drive the preflight as Codex (no CLAUDE_PROJECT_DIR, cwd in JSON) with a
#      valid override on a real `git commit` over a secret-containing fixture.
#   2. Assert the emitted JSON carries permissionDecision:"allow" + updatedInput
#      (the exact shape the official Codex hooks docs require — verified 2026-05-28).
#   3. Apply the rewrite the way a harness would: execute updatedInput.command
#      via `bash -c`. Assert the env var CLAUDE_SECRETS_OVERRIDE_REASON propagated
#      all the way to git's native pre-commit subprocess, which audits "override".
#   4. Assert the commit landed (override allowed it through both layers).
#
# What this does NOT prove (the irreducibly-live remainder of V8): that the real
# Codex CLI binary itself applies updatedInput when it sees permissionDecision.
# That is the Codex runtime contract, verified against the official docs, not the
# repo's testable surface. This test proves the rewrite SEMANTICS; the docs prove
# the contract. Together they are the full validation a repo can carry.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
AGENT0_GITHOOKS="$AGENT0_ROOT/.githooks"
AGENT0_PREFLIGHT="$AGENT0_ROOT/.agent0/hooks/secrets-preflight.sh"
AGENT0_GITLEAKS_TOML="$AGENT0_ROOT/.gitleaks.toml"

if ! command -v gitleaks >/dev/null 2>&1; then
  printf 'SKIP: %s (gitleaks not installed — native layer cannot run)\n' "$(basename "$0")"
  exit 0
fi

TMPDIR="$(mktemp -d -t spec-108-test-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git config core.hooksPath "$AGENT0_GITHOOKS"
cp "$AGENT0_GITLEAKS_TOML" "$TMPDIR/.gitleaks.toml"

TEST_VECTOR="AKIA""1234567890ABCDEF"  # split literal so source does not trip regex scanners
printf 'aws_access_key_id = %s\n' "$TEST_VECTOR" > fixture.env

REASON="documentation test vector for codex rewrite reaching bash"
CMD_LINE1='git add fixture.env && git commit -m "add codex test vector"'
CMD_LINE2="# OVERRIDE: ${REASON}"
COMMAND="${CMD_LINE1}
${CMD_LINE2}"

# (1) Drive the preflight as CODEX: no CLAUDE_PROJECT_DIR, cwd carried in JSON.
codex_json="$(jq -cn --arg cmd "$COMMAND" --arg cwd "$TMPDIR" '{"cwd":$cwd,"tool_input":{"command":$cmd}}')"
stdout_file="$TMPDIR/preflight_stdout.txt"
pf_exit=0
printf '%s' "$codex_json" | env -u CLAUDE_PROJECT_DIR -u AGENT0_PROJECT_DIR bash "$AGENT0_PREFLIGHT" >"$stdout_file" 2>/dev/null || pf_exit=$?

if [ "$pf_exit" -ne 0 ]; then
  printf 'FAIL: codex preflight exit=%d, want 0\n' "$pf_exit"; exit 1
fi

# (2) Assert the Codex-required shape: permissionDecision:"allow" + updatedInput.
pd="$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' "$stdout_file" 2>/dev/null || true)"
if [ "$pd" != "allow" ]; then
  printf 'FAIL: codex output permissionDecision=%s, want "allow"\n' "$pd"; cat "$stdout_file"; exit 1
fi
rewritten_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command // ""' "$stdout_file" 2>/dev/null || true)"
case "$rewritten_cmd" in
  "export CLAUDE_SECRETS_OVERRIDE_REASON="*) : ;;
  *) printf 'FAIL: rewrite must start with `export CLAUDE_SECRETS_OVERRIDE_REASON=`, got: %s\n' "$rewritten_cmd"; exit 1 ;;
esac

# (3) Apply the rewrite as a harness would — execute it. The env var must
# propagate across the `&& git commit` chain to git's native pre-commit hook.
AUDIT_LOG="$TMPDIR/.agent0/secrets-audit.jsonl"
commit_exit=0
bash -c "$rewritten_cmd" 2>"$TMPDIR/commit_stderr.txt" || commit_exit=$?
if [ "$commit_exit" -ne 0 ]; then
  printf 'FAIL: rewritten commit exit=%d, want 0\n' "$commit_exit"
  printf 'Stderr: %s\n' "$(cat "$TMPDIR/commit_stderr.txt")"; exit 1
fi

# The native hook saw the env var → audits "override" + finding_count>=1.
if [ ! -f "$AUDIT_LOG" ]; then
  printf 'FAIL: audit log not created at %s\n' "$AUDIT_LOG"; exit 1
fi
native_matched="$(jq -c 'select(.decision == "override" and .scan_mode == "native-pre-commit" and .finding_count >= 1 and (.override_reason != null))' "$AUDIT_LOG")"
if [ -z "$native_matched" ]; then
  printf 'FAIL: env var did NOT reach the native hook — no override row with finding_count>=1\n'
  cat "$AUDIT_LOG"; exit 1
fi

# (4) Commit landed.
if ! git log --oneline | grep -q "add codex test vector"; then
  printf 'FAIL: commit not found in git log after codex-shape override\n'; exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
