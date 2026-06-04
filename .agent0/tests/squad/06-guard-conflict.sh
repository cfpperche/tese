#!/usr/bin/env bash
# write-serialization — changes appearing with no open turn (out-of-turn) → aborted_conflict.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-06-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["true"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null
printf 'work\n' > "$T/a.txt"
bash "$SQ" turn-end --run "$R" --speaker claude >/dev/null     # boundary snapshot includes a.txt
bash "$SQ" guard --run "$R" >/dev/null 2>&1 || true            # no new change, no open turn → clean
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "running" ] || { echo "FAIL: clean guard flagged"; exit 1; }
printf 'sneaky\n' > "$T/out_of_turn.txt"                       # change with no open turn
bash "$SQ" guard --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_conflict" ] || { echo "FAIL: out-of-turn change not caught"; exit 1; }
echo PASS
