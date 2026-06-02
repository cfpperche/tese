#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "03-agents-symlink-resolves"
l="$AGENT0_ROOT/.agents/skills/vuln-audit"
[ -L "$l" ] && ok ".agents/skills/vuln-audit is a symlink" || no ".agents/skills/vuln-audit is a symlink"
assert_eq "$(readlink "$l")" "../../.agent0/skills/vuln-audit" "relative target correct"
[ -f "$l/SKILL.md" ] && ok "resolves to a readable SKILL.md" || no "resolves to a readable SKILL.md"
finish
