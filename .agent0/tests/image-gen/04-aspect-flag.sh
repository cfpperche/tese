#!/usr/bin/env bash
# .agent0/tests/image-gen/04-aspect-flag.sh
# Exercises the --aspect flag (square|landscape|portrait) added 2026-05-24
# after the initial dogfood surfaced that the v1 skill hardcoded 1024x1024
# and couldn't produce true banner-shape images.
#
# Asserts:
#   (a) --aspect=landscape → image_size=landscape_16_9, dims=1024x576
#   (b) --aspect=portrait → image_size=portrait_16_9, dims=576x1024
#   (c) omitted --aspect → default square (square_hd, 1024x1024)
#   (d) --aspect=panorama (invalid) → exit 2, no envelope emitted

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GEN_SH="$AGENT0_ROOT/.agent0/skills/image/scripts/gen.sh"

TMPDIR="$(mktemp -d -t spec-085-s4-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMPDIR"
export FAL_KEY="test-fake-key-not-real-aspect4-0000-0000-0000-000000000000:0000"

cd "$TMPDIR"

# --- (a) landscape ---
JSON="$(bash "$GEN_SH" prepare --tier=draft --aspect=landscape "banner test prompt" 2>/dev/null | tail -1)"
IMAGE_SIZE="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["image_size"])')"
DIMS="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["dimensions"])')"
ASPECT="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["aspect"])')"
if [ "$IMAGE_SIZE" != "landscape_16_9" ] || [ "$DIMS" != "1024x576" ] || [ "$ASPECT" != "landscape" ]; then
  echo "FAIL (a): landscape mapping wrong"
  echo "got: image_size=$IMAGE_SIZE dims=$DIMS aspect=$ASPECT"
  echo "expected: image_size=landscape_16_9 dims=1024x576 aspect=landscape"
  exit 1
fi

# --- (b) portrait ---
JSON="$(bash "$GEN_SH" prepare --tier=draft --aspect=portrait "vertical mockup" 2>/dev/null | tail -1)"
IMAGE_SIZE="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["image_size"])')"
DIMS="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["dimensions"])')"
if [ "$IMAGE_SIZE" != "portrait_16_9" ] || [ "$DIMS" != "576x1024" ]; then
  echo "FAIL (b): portrait mapping wrong"
  echo "got: image_size=$IMAGE_SIZE dims=$DIMS"
  exit 1
fi

# --- (c) default (omitted --aspect) → square ---
JSON="$(bash "$GEN_SH" prepare --tier=draft "default aspect" 2>/dev/null | tail -1)"
IMAGE_SIZE="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["image_size"])')"
DIMS="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["dimensions"])')"
if [ "$IMAGE_SIZE" != "square_hd" ] || [ "$DIMS" != "1024x1024" ]; then
  echo "FAIL (c): default aspect not square"
  echo "got: image_size=$IMAGE_SIZE dims=$DIMS"
  exit 1
fi

# --- (d) invalid --aspect → exit 2, no envelope emitted ---
set +e
OUT="$(bash "$GEN_SH" prepare --tier=draft --aspect=panorama "x" 2>&1)"
RC=$?
set -e
if [ $RC -ne 2 ]; then
  echo "FAIL (d): invalid --aspect should exit 2, got $RC"
  exit 1
fi
if printf '%s' "$OUT" | grep -q '"tier":'; then
  echo "FAIL (d): JSON envelope emitted despite invalid --aspect"
  exit 1
fi
if ! printf '%s' "$OUT" | grep -q 'invalid --aspect=panorama'; then
  echo "FAIL (d): error message missing 'invalid --aspect=panorama'"
  exit 1
fi

echo "PASS: Scenario --aspect flag (3 valid mappings + 1 invalid rejection)"
