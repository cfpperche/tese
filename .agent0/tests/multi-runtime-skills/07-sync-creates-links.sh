#!/usr/bin/env bash
# sync-harness --apply into a temp consumer creates both discovery symlinks.
source "$(dirname "$0")/_lib.sh"; echo "07-sync-creates-links"
WORK="$(mktemp -d -t mrs-sync-XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q; git -C "$WORK" config user.email t@t; git -C "$WORK" config user.name t
bash "$AGENT0_ROOT/.agent0/tools/sync-harness.sh" --agent0-path="$AGENT0_ROOT" --apply --force "$WORK" >/dev/null 2>&1
[ -L "$WORK/.claude/skills/vuln-audit" ] && ok "consumer .claude/skills/vuln-audit is a symlink" || no "consumer .claude/skills/vuln-audit is a symlink"
[ -L "$WORK/.agents/skills/vuln-audit" ] && ok "consumer .agents/skills/vuln-audit is a symlink" || no "consumer .agents/skills/vuln-audit is a symlink"
[ -f "$WORK/.agent0/skills/vuln-audit/SKILL.md" ] && ok "canonical source propagated" || no "canonical source propagated"
[ -f "$WORK/.claude/skills/vuln-audit/SKILL.md" ] && ok "claude link resolves to SKILL.md" || no "claude link resolves to SKILL.md"
finish
