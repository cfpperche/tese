#!/usr/bin/env bash
# .agent0/tests/video/run-all.sh — run the spec 132 /video test sweep.
# Default sweep is fast + hermetic (no network/paid calls). The real-render
# integration (05) is opt-in via VIDEO_RENDER_IT=1.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$HERE/../../.." && pwd)}"

rc=0
for t in "$HERE"/[0-9][0-9]-*.sh; do
  if bash "$t"; then :; else echo "  ^ FAILED: $(basename "$t")"; rc=1; fi
done
[ "$rc" -eq 0 ] && echo "video: all tests passed" || echo "video: FAILURES above"
exit "$rc"
