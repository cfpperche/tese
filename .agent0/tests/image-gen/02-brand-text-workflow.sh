#!/usr/bin/env bash
# .agent0/tests/image-gen/02-brand-text-workflow.sh
# acceptance Scenario 2 — brand-text tier workflow.
#
# Same shape as 01-draft-tier-workflow.sh — exercises the SKILL'S BEHAVIOR
# (script + output flow) by mocking the MCP response. See file header in 01
# for the rationale on why mocking is the right test boundary here.
#
# Asserts:
#   (a) prepare emits estimated cost line first
#   (b) JSON envelope resolves tier→model=fal-ai/gpt-image-2
#   (c) output_path is under assets/brand/<slug>.png (NO date prefix — brand is durable)
#   (d) approx_cost_usd matches the tier table (~$0.200 - the quality:high default baked since spec 088)
#   (e) --name flag overrides the auto-derived slug

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GEN_SH="$AGENT0_ROOT/.agent0/skills/image/scripts/gen.sh"

TMPDIR="$(mktemp -d -t spec-085-s2-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMPDIR"
export FAL_KEY="test-fake-key-not-real-fa20000000-0000-0000-0000-000000000000:0000"

cd "$TMPDIR"

PREPARE_OUT="$(bash "$GEN_SH" prepare --tier=brand-text --name=hero-logo "Minimalist logo design for Agent0" 2>/dev/null)"

if ! printf '%s\n' "$PREPARE_OUT" | head -1 | grep -q '^estimated: \$0\.200 for fal-ai/gpt-image-2 at 1024x1024 (square)$'; then
  echo "FAIL (a): first line of prepare stdout is not the estimated cost line"
  echo "got:"; printf '%s\n' "$PREPARE_OUT" | head -3
  exit 1
fi

JSON_LINE="$(printf '%s\n' "$PREPARE_OUT" | tail -1)"
if ! printf '%s' "$JSON_LINE" | grep -q '"model":"fal-ai/gpt-image-2"'; then
  echo "FAIL (b): JSON envelope model is not fal-ai/gpt-image-2"
  echo "got: $JSON_LINE"
  exit 1
fi

OUTPUT_PATH="$(printf '%s' "$JSON_LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["output_path"])')"
# Brand tier: NO date prefix; --name=hero-logo override → exact path
EXPECTED="assets/brand/hero-logo.png"
if [ "$OUTPUT_PATH" != "$EXPECTED" ]; then
  echo "FAIL (c) + (e): output_path mismatch"
  echo "expected: $EXPECTED"
  echo "got:      $OUTPUT_PATH"
  exit 1
fi

COST="$(printf '%s' "$JSON_LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["approx_cost_usd"])')"
if [ "$COST" != "0.2" ] && [ "$COST" != "0.200" ]; then
  echo "FAIL (d): approx_cost_usd is not 0.200 (got: $COST)"
  exit 1
fi

# Mock MCP + record
mkdir -p "$(dirname "$TMPDIR/$OUTPUT_PATH")"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfeA\x35\xc1\x8b\x00\x00\x00\x00IEND\xaeB`\x82' > "$TMPDIR/$OUTPUT_PATH"

bash "$GEN_SH" record \
  --tier=brand-text \
  --model=fal-ai/gpt-image-2 \
  --cost=0.200 \
  --prompt="Minimalist logo design for Agent0" \
  --output="$OUTPUT_PATH" \
  --dims=1024x1024 \
  >/dev/null

LINE="$(tail -1 "$TMPDIR/assets/generated/.manifest.jsonl")"
TIER_VAL="$(printf '%s' "$LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["tier"])')"
OUTPUT_VAL="$(printf '%s' "$LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["output_path"])')"
if [ "$TIER_VAL" != "brand-text" ] || [ "$OUTPUT_VAL" != "$EXPECTED" ]; then
  echo "FAIL manifest: tier=$TIER_VAL output=$OUTPUT_VAL"
  exit 1
fi

echo "PASS: Scenario 2 (brand-text tier workflow + --name override)"
