#!/usr/bin/env bash
# .agent0/tests/video/02-generative-cost-gate.sh
# Spec 132 — generative mode prepare: hard cost gate + tier resolution.
# No network: prepare never calls fal. A fake FAL_KEY satisfies the key check.
#
# Asserts:
#   (a) prepare WITHOUT --confirm-cost-usd is REFUSED (exit 2)
#   (b) prepare with --confirm-cost-usd BELOW estimate is REFUSED (exit 2)
#   (c) prepare with --confirm-cost-usd >= estimate emits an envelope (exit 0)
#       and resolves tier=draft → a Wan-class model from video-tiers.yaml
#   (d) estimate math = price/sec * duration (draft 0.10 * 5 = 0.50)
#   (e) unknown tier errors; missing FAL_KEY errors

set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GEN="$AGENT0_ROOT/.agent0/skills/video/scripts/gen.sh"

TMP="$(mktemp -d -t spec-132-gate-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"

fail() { echo "FAIL ($1): $2"; exit 1; }

# (e2) missing FAL_KEY → error (run before exporting the fake key)
( unset FAL_KEY; bash "$GEN" prepare --tier=draft --duration=5 --confirm-cost-usd=1 "x" ) >/dev/null 2>&1 \
  && fail e "prepare succeeded without FAL_KEY"

export FAL_KEY="test-fake-fa10000000-0000-0000-0000-000000000000:0000"

# (a) no --confirm-cost-usd → refuse
if bash "$GEN" prepare --tier=draft --duration=5 "slow push-in" >/dev/null 2>&1; then
  fail a "prepare succeeded without --confirm-cost-usd (gate did not fire)"
fi

# (b) below estimate (0.50) → refuse
if bash "$GEN" prepare --tier=draft --duration=5 --confirm-cost-usd=0.25 "x" >/dev/null 2>&1; then
  fail b "prepare succeeded with confirm below estimate"
fi

# (c)+(d) at/above estimate → envelope
OUT="$(bash "$GEN" prepare --tier=draft --duration=5 --confirm-cost-usd=0.50 "slow push-in on hero" 2>/dev/null)"
ENV_LINE="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
[ -n "$ENV_LINE" ] || fail c "no JSON envelope emitted at/above estimate"
printf '%s' "$ENV_LINE" | jq -e '.mode=="generative"' >/dev/null || fail c "envelope mode != generative"
printf '%s' "$ENV_LINE" | jq -e '.model | test("wan")' >/dev/null || fail c "draft did not resolve to a Wan-class model"
EST="$(printf '%s' "$ENV_LINE" | jq -r '.cost_estimate_usd')"
[ "$EST" = "0.50" ] || fail d "estimate math wrong: got $EST, want 0.50"

# (e1) unknown tier → error
if bash "$GEN" prepare --tier=ultra --duration=5 --confirm-cost-usd=99 "x" >/dev/null 2>&1; then
  fail e "prepare accepted unknown tier"
fi

echo "PASS 02-generative-cost-gate"
