#!/usr/bin/env bash
# policy — a forbidden path touched → aborted_policy (never silently accepted).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-07-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["true"],"forbidden_paths":["secrets\\.txt"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null
bash "$SQ" turn-end --run "$R" --speaker claude >/dev/null
printf 'leak\n' > "$T/secrets.txt"
bash "$SQ" guard --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_policy" ] || { echo "FAIL: forbidden path not caught"; exit 1; }
echo PASS
