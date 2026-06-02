#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "06-no-claude-skill-dir-dep"
n="$(grep -c 'CLAUDE_SKILL_DIR' "$AGENT0_ROOT/.agent0/skills/vuln-audit/SKILL.md" 2>/dev/null || true)"
assert_eq "$n" "0" "portable skill body has no \${CLAUDE_SKILL_DIR} dependency"
finish
