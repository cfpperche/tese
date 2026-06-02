#!/usr/bin/env bash
# .agent0/tests/video/05-code-render-integration.sh
# Spec 132 — GOLD integration: a real HyperFrames render end-to-end.
#
# Heavy (network + headless Chrome + ffmpeg) and slow, so it is OPT-IN:
# runs only when VIDEO_RENDER_IT=1; otherwise SKIPs clean (exit 0). This keeps
# the default test sweep fast and hermetic while still providing a real
# render-path check for environments that have the toolchain.
#
# Asserts (when enabled):
#   (a) `code.sh doctor` passes (deps present)
#   (b) scaffold + render produces a non-empty MP4 at assets/generated/videos/
#   (c) a fingerprinted manifest line is appended with status=success
#   (d) the composition SOURCE is under the tracked compositions/ root

set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CODE="$AGENT0_ROOT/.agent0/skills/video/scripts/code.sh"

if [ "${VIDEO_RENDER_IT:-0}" != "1" ]; then
  echo "SKIP 05-code-render-integration (set VIDEO_RENDER_IT=1 to run the real render)"
  exit 0
fi

TMP="$(mktemp -d -t spec-132-render-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
fail() { echo "FAIL ($1): $2"; exit 1; }

# (a)
bash "$CODE" doctor >/dev/null 2>&1 || { echo "SKIP 05 — deps not present (doctor failed)"; exit 0; }

# (b)
bash "$CODE" scaffold itclip >/dev/null 2>&1 || fail b "scaffold failed"
[ -f "$TMP/assets/video/compositions/itclip/index.html" ] || fail d "source not under compositions/"
bash "$CODE" render itclip >/dev/null 2>&1 || fail b "render failed"
MP4="$(ls "$TMP"/assets/generated/videos/*-itclip.mp4 2>/dev/null | head -1)"
[ -n "$MP4" ] && [ -s "$MP4" ] || fail b "no non-empty MP4 produced"

# (c)
MAN="$TMP/assets/generated/.video-manifest.jsonl"
[ -f "$MAN" ] || fail c "no manifest written"
tail -1 "$MAN" | jq -e '.mode=="code" and .status=="success" and (.fingerprint.hf_version|length>0)' >/dev/null \
  || fail c "manifest line missing fingerprint/success"

echo "PASS 05-code-render-integration (real MP4: $(basename "$MP4"))"
