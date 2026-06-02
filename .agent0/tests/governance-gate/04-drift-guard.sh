#!/usr/bin/env bash
# Scenario: fast-path probe ⊇ families (drift guard).
#
# The pre-jq probe exits 0 on a miss, BEFORE the family regexes run. So every
# family-blocked command MUST also hit the probe — otherwise it silently skips
# the gate. This test drives one representative blocked command per family
# end-to-end: if a family regex is added without its probe keyword (or vice
# versa), the command stops blocking and this test goes red. That red is the
# drift signal.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# One representative per blocking family — all must reach the regex and block.
assert_blocked 'rm -rf /tmp/x'                  # destructive: rm
assert_blocked 'git push --force origin main'   # destructive: push --force
assert_blocked 'git reset --hard HEAD~1'         # destructive: reset --hard
assert_blocked 'git clean -fdx'                  # destructive: clean (new family — needs probe keyword)
assert_blocked 'git checkout -- .'               # destructive: whole-tree checkout (new family — needs probe keyword)
assert_blocked 'git restore .'                   # destructive: whole-tree restore (new family — needs probe keyword)
assert_blocked 'git commit --no-verify -m x'     # hook-bypass
assert_blocked 'git add -A'                       # blanket-staging
assert_blocked 'git commit -am wip'              # blanket-staging

pass "$0"
