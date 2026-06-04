#!/usr/bin/env bash
# turn-lock: only the current turn_holder may take a turn (single-writer).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-01-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["true"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
[ "$(bash "$SQ" status --run "$R" | jq -r .turn_holder)" = "claude" ] || { echo "FAIL: initial holder not claude"; exit 1; }
rc=0; bash "$SQ" turn-start --run "$R" --speaker codex >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || { echo "FAIL: wrong-speaker turn-start exit=$rc want 3"; exit 1; }
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null 2>&1 || { echo "FAIL: holder turn-start refused"; exit 1; }
echo PASS
