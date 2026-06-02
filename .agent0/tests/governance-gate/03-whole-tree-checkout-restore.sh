#!/usr/bin/env bash
# Scenario: whole-worktree checkout/restore (. or :/) blocked; targeted paths,
# branch switches, and ./subdir paths stay allowed.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# BLOCK — whole-tree discard.
assert_blocked 'git checkout -- .'
assert_blocked 'git checkout -- :/'
assert_blocked 'git restore .'
assert_blocked 'git restore :/'
assert_blocked 'git restore --staged .'

# ALLOW — targeted file, branch switch, subdir path (not whole-tree).
assert_allowed 'git checkout -- src/file.ts'
assert_allowed 'git checkout main'
assert_allowed 'git checkout -b feature'
assert_allowed 'git restore src/file.ts'
assert_allowed 'git checkout -- ./src'

pass "$0"
