#!/usr/bin/env bash
# .agent0/tests/image-gen/01-draft-tier-workflow.sh
# acceptance Scenario 1 — draft tier workflow.
#
# The scenario as written presupposes a real FAL_KEY + .mcp.json activation.
# This test exercises the SKILL'S BEHAVIOR (the script + output flow) by
# mocking the MCP response — same pattern the secrets-scan tests use to
# exercise the preflight without a real git commit. It validates everything
# downstream of "MCP returns image bytes": path derivation, cost printing,
# manifest writing. The real-fal.ai integration test belongs in a CI job with
# a real key; this test runs everywhere without external dependencies.
#
# Asserts:
#   (a) gen.sh prepare emits estimated cost BEFORE the JSON envelope
#   (b) JSON envelope resolves tier→model=fal-ai/flux/schnell
#   (c) output_path is under assets/generated/mockups/<YYYY-MM-DD>-<slug>.png
#   (d) approx_cost_usd matches the tier table (~$0.003)
#   (e) gen.sh record appends one JSONL line with the 8-field shape

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GEN_SH="$AGENT0_ROOT/.agent0/skills/image/scripts/gen.sh"

TMPDIR="$(mktemp -d -t spec-085-s1-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMPDIR"
export FAL_KEY="test-fake-key-not-real-fa10000000-0000-0000-0000-000000000000:0000"

cd "$TMPDIR"

# --- (a) + (b) + (c) + (d): prepare emits cost first, then JSON envelope ---
PREPARE_OUT="$(bash "$GEN_SH" prepare --tier=draft "a cat sitting on a fence" 2>/dev/null)"

if ! printf '%s\n' "$PREPARE_OUT" | head -1 | grep -q '^estimated: \$0\.003 for fal-ai/flux/schnell at 1024x1024 (square)$'; then
  echo "FAIL (a): first line of prepare stdout is not the estimated cost line"
  echo "got:"; printf '%s\n' "$PREPARE_OUT" | head -3
  exit 1
fi

JSON_LINE="$(printf '%s\n' "$PREPARE_OUT" | tail -1)"
if ! printf '%s' "$JSON_LINE" | grep -q '"model":"fal-ai/flux/schnell"'; then
  echo "FAIL (b): JSON envelope model is not fal-ai/flux/schnell"
  echo "got: $JSON_LINE"
  exit 1
fi

OUTPUT_PATH="$(printf '%s' "$JSON_LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["output_path"])')"
TODAY="$(date -u +%Y-%m-%d)"
EXPECTED_PREFIX="assets/generated/mockups/$TODAY-a-cat-sitting-on-a"
if ! printf '%s' "$OUTPUT_PATH" | grep -q "^${EXPECTED_PREFIX}.*\.jpg$"; then
  echo "FAIL (c): output_path does not match expected prefix or extension (.jpg for draft tier)"
  echo "expected prefix: $EXPECTED_PREFIX, ext: .jpg"
  echo "got: $OUTPUT_PATH"
  exit 1
fi

# Also assert envelope carries the new fields: aspect, image_size, extension
for f in aspect image_size extension; do
  if ! printf '%s' "$JSON_LINE" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert '$f' in d, '$f missing'" 2>/dev/null; then
    echo "FAIL: prepare envelope missing '$f' field"
    echo "got: $JSON_LINE"
    exit 1
  fi
done

COST="$(printf '%s' "$JSON_LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["approx_cost_usd"])')"
if [ "$COST" != "0.003" ]; then
  echo "FAIL (d): approx_cost_usd is not 0.003 (got: $COST)"
  exit 1
fi

# --- Mock the MCP response: create a fake PNG at the resolved output_path ---
# Use a real 1-pixel PNG byte sequence so the file is a valid PNG.
mkdir -p "$(dirname "$TMPDIR/$OUTPUT_PATH")"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfeA\x35\xc1\x8b\x00\x00\x00\x00IEND\xaeB`\x82' > "$TMPDIR/$OUTPUT_PATH"

# --- (e): record appends manifest line with 8-field shape ---
bash "$GEN_SH" record \
  --tier=draft \
  --model=fal-ai/flux/schnell \
  --cost=0.003 \
  --prompt="a cat sitting on a fence" \
  --output="$OUTPUT_PATH" \
  --dims=1024x1024 \
  >/dev/null

MANIFEST="$TMPDIR/assets/generated/.manifest.jsonl"
if [ ! -f "$MANIFEST" ]; then
  echo "FAIL (e): manifest file not created at $MANIFEST"
  exit 1
fi

LINE="$(tail -1 "$MANIFEST")"
for field in ts session_id tier model cost_usd prompt output_path dimensions status; do
  if ! printf '%s' "$LINE" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert '$field' in d, '$field missing'" 2>/dev/null; then
    echo "FAIL (e): manifest line missing '$field'"
    echo "got: $LINE"
    exit 1
  fi
done

# Spot-check key values
TIER_VAL="$(printf '%s' "$LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["tier"])')"
if [ "$TIER_VAL" != "draft" ]; then
  echo "FAIL (e): manifest tier=$TIER_VAL, expected draft"
  exit 1
fi

echo "PASS: Scenario 1 (draft tier workflow)"
