#!/usr/bin/env bash
# .agent0/tests/video/03-code-scaffold-contract.sh
# Spec 132 — code mode scaffold/render contract (no actual render here; render
# is exercised by the gold integration check 05 when deps are present).
#
# Asserts:
#   (a) scaffold <slug> creates the owned mini-project (index.html + 3 config files)
#       from the Agent0 template (NOT `hyperframes init` — no upstream-skill nudge)
#   (b) scaffolded source lands under assets/video/compositions/<slug>/ (tracked root)
#   (c) duplicate scaffold is refused
#   (d) invalid (non-kebab) slug is refused
#   (e) render on a missing composition fails clean (exit != 0)

set -uo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CODE="$AGENT0_ROOT/.agent0/skills/video/scripts/code.sh"

TMP="$(mktemp -d -t spec-132-code-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"

fail() { echo "FAIL ($1): $2"; exit 1; }

# (a)+(b)
bash "$CODE" scaffold demo-clip >/dev/null 2>&1 || fail a "scaffold failed"
DEST="$TMP/assets/video/compositions/demo-clip"
for f in index.html hyperframes.json package.json meta.json; do
  [ -f "$DEST/$f" ] || fail a "scaffold missing $f"
done
grep -q 'window.__timelines' "$DEST/index.html" || fail a "scaffolded index.html missing GSAP timeline"
# owned template, not `hyperframes init`: positive signals — our package name +
# our pin, AND none of the project-level CLAUDE.md/AGENTS.md that `init` injects.
grep -q 'agent0-video-composition' "$DEST/package.json" || fail a "not the Agent0-owned template (package name)"
grep -q 'hyperframes@0.6.64' "$DEST/package.json" || fail a "engine pin missing from scaffold"
[ -f "$DEST/CLAUDE.md" ] && fail a "scaffold injected a project CLAUDE.md (looks like 'hyperframes init', not our template)"
[ -f "$DEST/AGENTS.md" ] && fail a "scaffold injected a project AGENTS.md (looks like 'hyperframes init', not our template)"

# (c) duplicate
bash "$CODE" scaffold demo-clip >/dev/null 2>&1 && fail c "duplicate scaffold was allowed"

# (d) invalid slug
bash "$CODE" scaffold 'Bad Slug' >/dev/null 2>&1 && fail d "non-kebab slug accepted"
bash "$CODE" scaffold '1leading' >/dev/null 2>&1 && fail d "slug starting with digit accepted"

# (e) render missing composition → clean failure
bash "$CODE" render does-not-exist >/dev/null 2>&1 && fail e "render of missing composition returned success"

echo "PASS 03-code-scaffold-contract"
