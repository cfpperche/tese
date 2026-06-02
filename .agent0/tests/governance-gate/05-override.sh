#!/usr/bin/env bash
# Scenario: override marker — reason >= 10 chars allows; shorter still blocks.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Valid override (>= 10-char reason) → allowed despite a blocking pattern.
assert_allowed 'rm -rf /tmp/x # OVERRIDE: nuking my own scratch dir'
assert_allowed 'git clean -fdx # OVERRIDE: clearing generated build artifacts'

# Too-short reason (< 10 chars after trim) → still blocked.
assert_blocked 'rm -rf /tmp/x # OVERRIDE: skip'
assert_blocked 'git checkout -- . # OVERRIDE: n/a'

pass "$0"
