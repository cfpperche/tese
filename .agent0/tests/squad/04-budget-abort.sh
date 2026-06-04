#!/usr/bin/env bash
# bounded — reaching max_rounds aborts to aborted_budget (never infinite).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-04-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":2,"max_repair_attempts":3,"gate":["false"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null; bash "$SQ" turn-end --run "$R" --speaker claude >/dev/null
bash "$SQ" turn-start --run "$R" --speaker codex  >/dev/null; bash "$SQ" turn-end --run "$R" --speaker codex >/dev/null
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_budget" ] || { echo "FAIL: max_rounds did not abort to aborted_budget"; exit 1; }
echo PASS
