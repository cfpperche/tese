#!/usr/bin/env bash
# gate GREEN + all model agents proposed-done → ready_for_human_prod. Also: gate
# green but NOT all proposed → stays running (gate green is necessary, agreement
# completes the move, the external gate is the closer).
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-03-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["test -f DONE"]}' > "$T/docs/specs/199-demo/squad.json"
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
touch "$T/DONE"
bash "$SQ" propose-done --run "$R" --speaker claude >/dev/null
bash "$SQ" gate --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "running" ] || { echo "FAIL: closed with only one agent proposed"; exit 1; }
bash "$SQ" propose-done --run "$R" --speaker codex >/dev/null
bash "$SQ" gate --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "ready_for_human_prod" ] || { echo "FAIL: green gate + both proposed did not reach ready_for_human_prod"; exit 1; }
echo PASS
