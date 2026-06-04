#!/usr/bin/env bash
# THE load-bearing invariant (149 dependency): agent agreement alone never
# closes the run. Both agents propose-done, but the gate is RED → status must
# stay running (NOT ready_for_human_prod).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-02-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":5,"gate":["false"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" propose-done --run "$R" --speaker claude >/dev/null
bash "$SQ" propose-done --run "$R" --speaker codex >/dev/null
bash "$SQ" gate --run "$R" >/dev/null 2>&1 || true
st="$(bash "$SQ" status --run "$R" | jq -r .status)"
[ "$st" != "ready_for_human_prod" ] || { echo "FAIL: agreement closed the run despite a red gate"; exit 1; }
[ "$st" = "running" ] || { echo "FAIL: status=$st want running"; exit 1; }
echo PASS
