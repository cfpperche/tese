#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "01-canonical-source-exists"
f="$AGENT0_ROOT/.agent0/skills/vuln-audit/SKILL.md"
{ [ -f "$f" ] && [ ! -L "$f" ]; } && ok "canonical SKILL.md is a real file" || no "canonical SKILL.md is a real file"
finish
