#!/usr/bin/env bash
# 150.3 — the shipped squad.json.example must (a) be valid JSON and (b) forbid
# HANDOFF.md by default. 151 dogfood finding F3: a peer turn rewrote the
# orchestrator-owned HANDOFF.md despite the brief saying not to — forbidden_paths
# is the ONLY mechanically-enforced scope (the natural-language brief is a hint),
# so the default contract must guard the handoff out of the box.
set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
EX="$AGENT0_ROOT/.agent0/skills/squad/references/squad.json.example"
jq -e . "$EX" >/dev/null 2>&1 || { echo "FAIL: squad.json.example is not valid JSON"; exit 1; }
jq -e '.forbidden_paths | any(test("HANDOFF"))' "$EX" >/dev/null 2>&1 \
  || { echo "FAIL: squad.json.example forbidden_paths does not forbid HANDOFF by default (F3)"; exit 1; }
echo PASS
