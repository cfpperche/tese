#!/usr/bin/env bash
# With symlink creation forced to fail, sync materializes copies + emits skills-advisory.
source "$(dirname "$0")/_lib.sh"; echo "08-sync-symlink-hostile-fallback"
WORK="$(mktemp -d -t mrs-hostile-XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q; git -C "$WORK" config user.email t@t; git -C "$WORK" config user.name t
# Simulate a symlink-hostile checkout: a PATH shim whose `ln -s` always fails.
SHIM="$WORK/.shim"; mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "-s" ]; then exit 1; fi\nexec /bin/ln "$@"\n' > "$SHIM/ln"
chmod +x "$SHIM/ln"
out="$(PATH="$SHIM:$PATH" bash "$AGENT0_ROOT/.agent0/tools/sync-harness.sh" --agent0-path="$AGENT0_ROOT" --apply --force "$WORK" 2>&1)"
assert_contains "$out" "skills-advisory:" "emits skills-advisory on hostile checkout"
assert_contains "$out" "symlinks unavailable" "advisory explains the fallback"
{ [ -f "$WORK/.claude/skills/vuln-audit/SKILL.md" ] && [ ! -L "$WORK/.claude/skills/vuln-audit" ]; } && ok "materialized real copy (not a symlink)" || no "materialized real copy (not a symlink)"
finish
