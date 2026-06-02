#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "05-skill-still-validates"
out="$(bash "$AGENT0_ROOT/.claude/skills/skill/scripts/validate.sh" "$AGENT0_ROOT/.agent0/skills/vuln-audit/SKILL.md" 2>&1)"; rc=$?
assert_eq "$rc" "0" "relocated SKILL.md passes agentskills validator"
finish
