#!/usr/bin/env bash
# policy (150.1) — a forbidden path touched DURING a turn → aborted_policy.
# Regression for the dogfood finding: the documented pump order is turn-end → guard,
# and turn-end folds the turn's diff into `boundary`, so guard's changes-since-boundary
# set was empty and an in-turn forbidden touch escaped. Policy must be checked against
# the turn's OWN delta (changed_paths), not only out-of-turn changes. (Test 07 covers
# the out-of-turn case; this covers the in-turn case 07 misses.)
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-09-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["true"],"forbidden_paths":["secrets\\.txt"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null
printf 'leak\n' > "$T/secrets.txt"                              # forbidden path touched DURING the turn
bash "$SQ" turn-end --run "$R" --speaker claude >/dev/null      # turn-end folds it into boundary
bash "$SQ" guard --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_policy" ] || { echo "FAIL: in-turn forbidden path not caught"; exit 1; }
echo PASS
