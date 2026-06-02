#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"; echo "04-single-source"
a="$(realpath "$AGENT0_ROOT/.claude/skills/vuln-audit/SKILL.md")"
b="$(realpath "$AGENT0_ROOT/.agents/skills/vuln-audit/SKILL.md")"
c="$(realpath "$AGENT0_ROOT/.agent0/skills/vuln-audit/SKILL.md")"
assert_eq "$a" "$c" "claude link resolves to canonical source"
assert_eq "$b" "$c" "codex link resolves to canonical source"
finish
