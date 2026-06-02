#!/usr/bin/env bash
# .agent0/tests/video/01-router-and-portability.sh
# Spec 132 — static contract: skill frontmatter, multi-runtime discovery,
# openai.yaml policy, mode-required router text.
#
# Asserts:
#   (a) SKILL.md frontmatter declares name=video + agentskills-portable tier
#   (b) both discovery symlinks resolve to the canonical SKILL.md
#   (c) agents/openai.yaml sets allow_implicit_invocation: false
#   (d) SKILL.md documents the mode-required error (no silent default)
#   (e) no model IDs baked in the skill body (tiers resolve from video-tiers.yaml)

set -euo pipefail
AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SKILL="$AGENT0_ROOT/.agent0/skills/video/SKILL.md"

fail() { echo "FAIL ($1): $2"; exit 1; }

# (a)
grep -qE '^name: video$' "$SKILL" || fail a "SKILL.md missing 'name: video'"
grep -qE 'agent0-portability-tier: agentskills-portable' "$SKILL" || fail a "not declared agentskills-portable"

# (b)
for rt in .claude/skills/video .agents/skills/video; do
  [ -L "$AGENT0_ROOT/$rt" ] || fail b "$rt is not a symlink"
  [ -f "$AGENT0_ROOT/$rt/SKILL.md" ] || fail b "$rt/SKILL.md does not resolve"
done

# (c)
OPENAI="$AGENT0_ROOT/.agent0/skills/video/agents/openai.yaml"
grep -qE '^\s*allow_implicit_invocation:\s*false' "$OPENAI" || fail c "allow_implicit_invocation not false"

# (d)
grep -q -- '--mode is required' "$SKILL" || fail d "mode-required error not documented"
grep -q -- '--mode=code' "$SKILL" || fail d "code mode option missing from error"
grep -q -- '--mode=generative' "$SKILL" || fail d "generative mode option missing from error"

# (e) no fal-ai/<vendor> model endpoint IDs hardcoded in the skill body or scripts
if grep -rIqE 'fal-ai/(wan|kling|veo)' "$AGENT0_ROOT/.agent0/skills/video/SKILL.md" "$AGENT0_ROOT/.agent0/skills/video/scripts/"; then
  fail e "model IDs leaked into skill body/scripts (must live only in video-tiers.yaml)"
fi
grep -qE 'fal-ai/(wan|kling|veo)' "$AGENT0_ROOT/.agent0/skills/video/references/video-tiers.yaml" \
  || fail e "video-tiers.yaml has no seed model IDs"

echo "PASS 01-router-and-portability"
