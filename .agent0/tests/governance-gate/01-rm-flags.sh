#!/usr/bin/env bash
# Scenario: rm recursive+force in any flag arrangement is blocked; recursive-only,
# interactive, force-only, and grep -rf stay allowed (no false-positive).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# BLOCK — recursive + force, combined and separate, both orders, -R variant.
assert_blocked 'rm -rf /tmp/x'
assert_blocked 'rm -fr /tmp/x'
assert_blocked 'rm -r -f /tmp/x'
assert_blocked 'rm -f -r /tmp/x'
assert_blocked 'rm -R -f /tmp/x'
assert_blocked 'rm --recursive --force /tmp/x'

# ALLOW — no force (rm -r prompts), interactive, force-only single file, grep.
assert_allowed 'rm -r /tmp/x'
assert_allowed 'rm -i file.txt'
assert_allowed 'rm -f single.txt'
assert_allowed 'grep -rf patterns.txt .'

pass "$0"
