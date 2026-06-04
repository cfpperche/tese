#!/usr/bin/env bash
# bounded — gate failing beyond max_repair_attempts aborts to aborted_repairs.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-05-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":2,"gate":["false"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
for i in 1 2; do bash "$SQ" gate --run "$R" >/dev/null 2>&1 || true; done
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "running" ] || { echo "FAIL: aborted before exceeding max"; exit 1; }
bash "$SQ" gate --run "$R" >/dev/null 2>&1 || true   # 3rd > max 2
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_repairs" ] || { echo "FAIL: did not abort to aborted_repairs"; exit 1; }
echo PASS
