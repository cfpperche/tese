#!/usr/bin/env bash
# 150.2 — content-aware fingerprint: an in-turn REWRITE of an already-listed path
# is detected. The dogfood (Pass 2) showed the porcelain set-diff was path-level:
# a file under an already-untracked dir collapses to one stable "?? dir/" line, so
# rewriting its CONTENT left the fingerprint unchanged and guard saw nothing — an
# in-turn forbidden rewrite escaped. The fingerprint now lists files individually
# (-uall) and appends a content hash, so a rewrite changes the line → guard catches
# it. (Tied to the safety model: the rewritten path here is forbidden.)
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SQ="$AGENT0_ROOT/.agent0/skills/squad/scripts/squad.sh"
T="$(mktemp -d -t sq-10-XXXXXX)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; mkdir -p "$T/docs/specs/199-demo" "$T/sandbox"
printf '%s\n' '{"spec":"199-demo","roster":["claude","codex"],"max_rounds":20,"max_repair_attempts":3,"gate":["true"],"forbidden_paths":["sandbox/locked\\.sh"]}' > "$T/docs/specs/199-demo/squad.json"
printf 'v1\n' > "$T/sandbox/locked.sh"             # already-listed (new untracked dir+file) BEFORE the run
R="$(bash "$SQ" init --spec 199-demo --repo "$T")"
bash "$SQ" turn-start --run "$R" --speaker claude >/dev/null
printf 'v2-rewritten\n' > "$T/sandbox/locked.sh"   # in-turn REWRITE: content changes, path-level porcelain line does not
bash "$SQ" turn-end --run "$R" --speaker claude >/dev/null
bash "$SQ" guard --run "$R" >/dev/null 2>&1 || true
[ "$(bash "$SQ" status --run "$R" | jq -r .status)" = "aborted_policy" ] || { echo "FAIL: in-turn REWRITE of an already-listed forbidden path not detected (content-blind fingerprint)"; exit 1; }
echo PASS
