#!/usr/bin/env bash
# .agent0/tests/secrets-scan/07-template-portable.sh
# V7 — Scenario: fix is template-portable.
#
# Clones the Agent0 repo fresh into a temp dir, follows the per-consumer checklist
# (git config core.hooksPath .githooks — the one new step), then runs a real
# git add + git commit sequence to confirm the secrets-scan gate is operative
# in a consumer project without any additional hook-copying.
#
# The native pre-commit hook is the durable portability layer: it lives in
# .githooks/ which is cloned along with the rest of the repo. The single
# install step (`git config core.hooksPath .githooks`) activates it.
#
# This test exercises the NATIVE HOOK ONLY (not the preflight). The preflight
# is a Claude Code harness hook; consumer projects may not use Claude Code. Template
# portability means the native git hook works in any environment.
#
# Asserts:
#   (a) Clone succeeds and .githooks/pre-commit exists in the consumer project
#   (b) After `git config core.hooksPath .githooks`, git commit with a
#       secret-containing staged file is blocked (exit 1)
#   (c) Audit log in the consumer project has decision="block" + scan_mode="native-pre-commit"
#   (d) git log does NOT contain the blocked commit

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
AGENT0_GITLEAKS_TOML="$AGENT0_ROOT/.gitleaks.toml"

TMPDIR="$(mktemp -d -t spec-007-test-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CONSUMER_DIR="$TMPDIR/agent0-consumer project"

# Clone the Agent0 repo (local file:// clone — no network required).
git clone "$AGENT0_ROOT" "$CONSUMER_DIR" -q

# (a) Assert .githooks/pre-commit exists in the consumer project.
if [ ! -f "$CONSUMER_DIR/.githooks/pre-commit" ]; then
  printf 'FAIL: .githooks/pre-commit not present in cloned consumer project\n'
  exit 1
fi
if [ ! -x "$CONSUMER_DIR/.githooks/pre-commit" ]; then
  printf 'FAIL: .githooks/pre-commit is not executable in cloned consumer project\n'
  exit 1
fi

# Per-consumer project checklist step: activate core.hooksPath (the one manual step).
cd "$CONSUMER_DIR"
git config user.email "consumer project@example.com"
git config user.name "Consumer project Test"
git config core.hooksPath .githooks

# Copy .gitleaks.toml so detectors apply (already present via clone, but
# confirm by checking — it's checked into the repo, so it will be there).
if [ ! -f "$CONSUMER_DIR/.gitleaks.toml" ]; then
  cp "$AGENT0_GITLEAKS_TOML" "$CONSUMER_DIR/.gitleaks.toml"
fi

# Stage a file with the canonical test vector.
TEST_VECTOR="AKIA""1234567890ABCDEF"  # split literal so source does not trip regex scanners; runtime concat yields the canonical test vector
printf 'aws_access_key_id = %s\n' "$TEST_VECTOR" > consumer-fixture.env
git add consumer-fixture.env

# Run git commit — the native hook should block it.
commit_exit=0
commit_stderr_file="$TMPDIR/consumer_commit_stderr.txt"
git commit -m "add key in consumer project" 2>"$commit_stderr_file" || commit_exit=$?

# (b) Assert exit 1 (native hook blocked it).
if [ "$commit_exit" -ne 1 ]; then
  printf 'FAIL: git commit exit=%d in consumer project, want 1 (should be blocked by native hook)\n' "$commit_exit"
  printf 'Stderr: %s\n' "$(cat "$commit_stderr_file")"
  exit 1
fi

# Assert stderr contains block message.
if ! grep -qF "secrets-scan: blocked" "$commit_stderr_file"; then
  printf 'FAIL: consumer project commit stderr missing "secrets-scan: blocked"\n'
  printf 'Got: %s\n' "$(cat "$commit_stderr_file")"
  exit 1
fi

# (c) Assert consumer project audit log entry.
CONSUMER_AUDIT="$CONSUMER_DIR/.agent0/secrets-audit.jsonl"
if [ ! -f "$CONSUMER_AUDIT" ]; then
  printf 'FAIL: audit log not created in consumer project at %s\n' "$CONSUMER_AUDIT"
  exit 1
fi

matched="$(jq -c 'select(.decision == "block" and .scan_mode == "native-pre-commit")' "$CONSUMER_AUDIT")"
if [ -z "$matched" ]; then
  printf 'FAIL: no consumer project audit line with decision=block + scan_mode=native-pre-commit\n'
  printf 'Consumer project audit log contents:\n'
  cat "$CONSUMER_AUDIT"
  exit 1
fi

# (d) Assert git log does NOT contain the blocked commit.
if git log --oneline 2>/dev/null | grep -q "add key in consumer project"; then
  printf 'FAIL: blocked commit appeared in consumer project git log\n'
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
