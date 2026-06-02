#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "02-claude-symlink-resolves"
l="$AGENT0_ROOT/.claude/skills/vuln-audit"
[ -L "$l" ] && ok ".claude/skills/vuln-audit is a symlink" || no ".claude/skills/vuln-audit is a symlink"
assert_eq "$(readlink "$l")" "../../.agent0/skills/vuln-audit" "relative target correct"
[ -f "$l/SKILL.md" ] && ok "resolves to a readable SKILL.md" || no "resolves to a readable SKILL.md"
finish
