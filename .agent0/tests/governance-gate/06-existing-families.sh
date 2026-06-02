#!/usr/bin/env bash
# Scenario: regression — the pre-107 families still block exactly as before.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Destructive (existing)
assert_blocked 'git push --force origin main'
assert_blocked 'git push -f origin main'
assert_blocked 'git reset --hard HEAD~1'
# Hook bypass
assert_blocked 'git commit --no-verify -m x'
assert_blocked 'git push --no-verify'
# Blanket staging
assert_blocked 'git add -A'
assert_blocked 'git add --all'
assert_blocked 'git add .'
assert_blocked 'git commit -am wip'
assert_blocked 'git commit --all -m wip'

# Ordinary commands stay allowed.
assert_allowed 'git push origin main'
assert_allowed 'git commit -m "real message"'
assert_allowed 'git add src/file.ts'
assert_allowed 'ls -la'
assert_allowed 'echo hello'

pass "$0"
