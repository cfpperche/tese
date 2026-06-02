#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "09-no-discoverable-test-fixtures"

hits="$(
  find "$AGENT0_ROOT/.agent0/skills" \
    -path '*/tests/*/SKILL.md' \
    -print 2>/dev/null
)"

assert_eq "$hits" "" "no test fixture SKILL.md files live under discoverable .agent0/skills"
finish
