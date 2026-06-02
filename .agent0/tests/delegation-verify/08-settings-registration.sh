#!/usr/bin/env bash
# .agent0/tests/delegation-verify/08-settings-registration.sh
# Structural: settings.json registers delegation-verify.sh on SubagentStop AND
# no longer registers the removed post-edit-validate.sh anywhere.
set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SETTINGS="$AGENT0_ROOT/.claude/settings.json"

jq empty "$SETTINGS" || { printf 'FAIL: settings.json not valid JSON\n'; exit 1; }

# delegation-verify.sh registered under SubagentStop
hits="$(jq -r '.hooks.SubagentStop[].hooks[].command' "$SETTINGS" 2>/dev/null | grep -c 'delegation-verify.sh' || true)"
[ "${hits:-0}" -ge 1 ] || { printf 'FAIL: delegation-verify.sh not registered on SubagentStop\n'; exit 1; }

# delegation-stop.sh still registered alongside (we did NOT remove it)
hits2="$(jq -r '.hooks.SubagentStop[].hooks[].command' "$SETTINGS" 2>/dev/null | grep -c 'delegation-stop.sh' || true)"
[ "${hits2:-0}" -ge 1 ] || { printf 'FAIL: delegation-stop.sh missing from SubagentStop\n'; exit 1; }

# post-edit-validate.sh removed everywhere in settings.json
if grep -q 'post-edit-validate' "$SETTINGS"; then
  printf 'FAIL: post-edit-validate.sh still referenced in settings.json\n'; exit 1
fi

# the hook file itself is gone
if [ -e "$AGENT0_ROOT/.claude/hooks/post-edit-validate.sh" ]; then
  printf 'FAIL: .claude/hooks/post-edit-validate.sh still exists\n'; exit 1
fi

printf 'PASS\n'
