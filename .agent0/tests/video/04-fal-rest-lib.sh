#!/usr/bin/env bash
# .agent0/tests/video/04-fal-rest-lib.sh
# Spec 132 — shared fal REST lib contract (no network).
#
# Asserts:
#   (a) --help exits 0
#   (b) submit without FAL_KEY dies (exit != 0) — auth is required
#   (c) submit without --model dies even with a key
#   (d) the lib carries NO image/video-specific fields (model-agnostic)
#   (e) it lives at the non-discoverable .agent0/tools/ path, not a skill dir

set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
LIB="$AGENT0_ROOT/.agent0/tools/fal-rest.sh"

fail() { echo "FAIL ($1): $2"; exit 1; }

# (e)
[ -f "$LIB" ] || fail e "fal-rest.sh not at .agent0/tools/"
[ -f "$AGENT0_ROOT/.agent0/skills/video/scripts/fal-rest.sh" ] && fail e "lib must NOT live in a skill dir (discovery surface)"

# (a)
bash "$LIB" --help >/dev/null 2>&1 || fail a "--help did not exit 0"

# (b)
( unset FAL_KEY; bash "$LIB" submit --model=fal-ai/x --body='{}' ) >/dev/null 2>&1 \
  && fail b "submit succeeded without FAL_KEY"

# (c)
export FAL_KEY="fake:key"
bash "$LIB" submit --body='{}' >/dev/null 2>&1 && fail c "submit accepted without --model"

# (d) model-agnostic: no image_size / video duration / aspect baked in the lib
grep -qE 'image_size|aspect|duration|\.images\[0\]|\.video\b' "$LIB" \
  && fail d "fal-rest.sh leaked image/video-specific fields (must be model-agnostic)"

# (f) run (spec 133): synchronous — hits fal.run, NOT queue.fal.run; needs key + model
grep -q 'SYNC_BASE="https://fal.run"' "$LIB" || fail f "run must use the sync fal.run base"
grep -q 'sub_run()' "$LIB" || fail f "run subcommand missing"
( unset FAL_KEY; bash "$LIB" run --model=fal-ai/x --body='{}' ) >/dev/null 2>&1 \
  && fail f "run succeeded without FAL_KEY"
bash "$LIB" run --body='{}' >/dev/null 2>&1 && fail f "run accepted without --model (FAL_KEY=$FAL_KEY set)"

# (g) run is advertised in --help
bash "$LIB" --help 2>&1 | grep -qE '^\s*run\s' || fail g "--help does not list run"

echo "PASS 04-fal-rest-lib"
