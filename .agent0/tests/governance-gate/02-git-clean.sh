#!/usr/bin/env bash
# Scenario: git clean force+broad (-d/-x) blocked; dry-run and narrow force allowed.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# BLOCK — force present AND broad (-d dirs / -x ignored), any cluster/order.
assert_blocked 'git clean -fdx'
assert_blocked 'git clean -fd'
assert_blocked 'git clean -df'
assert_blocked 'git clean -f -d'
assert_blocked 'git clean -x -f'
assert_blocked 'git clean --force -d'

# ALLOW — dry-run wins even with -d/-x; narrow force (no -d/-x); plain clean.
assert_allowed 'git clean -n'
assert_allowed 'git clean -fdn'
assert_allowed 'git clean --dry-run'
assert_allowed 'git clean -f path/to/file'
assert_allowed 'git clean'

pass "$0"
