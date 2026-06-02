#!/usr/bin/env bash
# .agent0/tests/image-gen/03-brand-photo-workflow.sh
# acceptance Scenario 3 — brand-photo tier workflow.
#
# Same shape as 01-draft / 02-brand-text. See 01-draft-tier-workflow.sh for
# the rationale on test-boundary mocking.
#
# Asserts:
#   (a) prepare emits estimated cost line first ($0.060 / imagen4/ultra)
#   (b) JSON envelope resolves tier→model=fal-ai/imagen4/ultra
#   (c) output_path is under assets/brand/<slug>.png (NO date prefix)
#   (d) auto-derived slug from prompt (no --name): first 5 words kebabed

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GEN_SH="$AGENT0_ROOT/.agent0/skills/image/scripts/gen.sh"

TMPDIR="$(mktemp -d -t spec-085-s3-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMPDIR"
export FAL_KEY="test-fake-key-not-real-fa30000000-0000-0000-0000-000000000000:0000"

cd "$TMPDIR"

PREPARE_OUT="$(bash "$GEN_SH" prepare --tier=brand-photo "engineers collaborating in modern office sunlight" 2>/dev/null)"

if ! printf '%s\n' "$PREPARE_OUT" | head -1 | grep -q '^estimated: \$0\.060 for fal-ai/imagen4/ultra at 1024x1024 (square)$'; then
  echo "FAIL (a): first line of prepare stdout is not the estimated cost line"
  echo "got:"; printf '%s\n' "$PREPARE_OUT" | head -3
  exit 1
fi

JSON_LINE="$(printf '%s\n' "$PREPARE_OUT" | tail -1)"
if ! printf '%s' "$JSON_LINE" | grep -q '"model":"fal-ai/imagen4/ultra"'; then
  echo "FAIL (b): JSON envelope model is not fal-ai/imagen4/ultra"
  echo "got: $JSON_LINE"
  exit 1
fi

OUTPUT_PATH="$(printf '%s' "$JSON_LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["output_path"])')"
EXPECTED="assets/brand/engineers-collaborating-in-modern-office.png"
if [ "$OUTPUT_PATH" != "$EXPECTED" ]; then
  echo "FAIL (c) + (d): output_path mismatch"
  echo "expected: $EXPECTED"
  echo "got:      $OUTPUT_PATH"
  exit 1
fi

# Mock MCP + record
mkdir -p "$(dirname "$TMPDIR/$OUTPUT_PATH")"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfeA\x35\xc1\x8b\x00\x00\x00\x00IEND\xaeB`\x82' > "$TMPDIR/$OUTPUT_PATH"

bash "$GEN_SH" record \
  --tier=brand-photo \
  --model=fal-ai/imagen4/ultra \
  --cost=0.060 \
  --prompt="engineers collaborating in modern office sunlight" \
  --output="$OUTPUT_PATH" \
  --dims=1024x1024 \
  >/dev/null

LINE="$(tail -1 "$TMPDIR/assets/generated/.manifest.jsonl")"
TIER_VAL="$(printf '%s' "$LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["tier"])')"
COST_VAL="$(printf '%s' "$LINE" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["cost_usd"])')"
if [ "$TIER_VAL" != "brand-photo" ]; then
  echo "FAIL manifest: tier=$TIER_VAL, expected brand-photo"
  exit 1
fi
if [ "$COST_VAL" != "0.06" ] && [ "$COST_VAL" != "0.060" ]; then
  echo "FAIL manifest: cost_usd=$COST_VAL, expected ~0.060"
  exit 1
fi

echo "PASS: Scenario 3 (brand-photo tier workflow + auto-derived slug)"
