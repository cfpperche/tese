#!/usr/bin/env bash
# check-rubric.sh — Agent0 skill-rubric body-shape advisor
#
# Body-level companion to validate.sh (frontmatter compliance).
# Implements the rubric from `../references/skill-rubric.md`.
#
# Usage:
#   check-rubric.sh <skill-dir-or-SKILL.md>
#
# Behavior:
#   - Honors `<!-- SKILL-RUBRIC-EXEMPT: <reason ≥10 chars> -->` anywhere in body — silent exit 0
#   - Counts qualifying `^## ` step headers (excludes frame sections)
#   - Sub-threshold (<4 qualifying steps) → silent exit 0
#   - Above threshold → checks freedom annotations on each step header line OR its next non-blank line
#   - Above threshold → checks `## Eval Scenarios` exists + ≥2 `### Eval ` sub-headers
#   - Emits `skill-rubric-advisory: <slug> — <gap>` per finding to stderr
#   - ALWAYS exits 0 (advisory only, never blocks)
#
# Exit codes:
#   0 — always (this is an advisory, not a gate)
#   2 — usage / argument error

set -u

usage() {
  echo "usage: $0 <skill-dir-or-SKILL.md>" >&2
  exit 2
}

[ $# -eq 1 ] || usage

target="$1"

# Resolve to skill_dir + skill_md
if [ -d "$target" ]; then
  skill_dir="$target"
  skill_md="$target/SKILL.md"
elif [ -f "$target" ] && [ "$(basename "$target")" = "SKILL.md" ]; then
  skill_md="$target"
  skill_dir="$(dirname "$target")"
else
  echo "check-rubric: argument must be a skill directory or a SKILL.md path; got: $target" >&2
  exit 2
fi

[ -f "$skill_md" ] || exit 0  # missing file is validate.sh's problem, not ours

slug="$(basename "$(realpath "$skill_dir" 2>/dev/null || echo "$skill_dir")")"

# Locate frontmatter close to scope body-only checks
close_line="$(awk 'NR>=2 && NR<=200 && /^---$/ {print NR; exit}' "$skill_md")"
[ -z "$close_line" ] && close_line=0  # treat as "no frontmatter, whole file is body"

# Extract body (everything after frontmatter close)
body="$(awk -v cl="$close_line" 'NR > cl' "$skill_md")"

# ── Override marker — silent exit 0 if present with valid reason ────────────
# Pattern: <!-- SKILL-RUBRIC-EXEMPT: <reason ≥10 chars> -->
override_match="$(printf '%s\n' "$body" | grep -oE '<!-- SKILL-RUBRIC-EXEMPT:[[:space:]]*[^>]{10,}-->' | head -n1 || true)"
if [ -n "$override_match" ]; then
  exit 0
fi

# ── Count qualifying step headers ──────────────────────────────────────────
# Qualifying: ^## ... headers in body that are NOT frame sections.
# Frame sections (excluded):
#   - "## Notes"
#   - "## Gotchas"
#   - "## Cross-references"
#   - "## Reference Files"
#   - "## Eval Scenarios"
#   - "## Argument parsing"
#   - "## Unknown subcommand" / "## Unknown / extra subcommand"
#   - "## Worked example*"
qualifying_steps="$(printf '%s\n' "$body" | awk '
  /^## / {
    line = $0
    if (line ~ /^## Notes$/) next
    if (line ~ /^## Gotchas$/) next
    if (line ~ /^## Cross-references$/) next
    if (line ~ /^## Reference Files$/) next
    if (line ~ /^## Eval Scenarios$/) next
    if (line ~ /^## Argument parsing$/) next
    if (line ~ /^## Unknown/) next
    if (line ~ /^## Worked example/) next
    print line
  }
')"

step_count=0
[ -n "$qualifying_steps" ] && step_count="$(printf '%s\n' "$qualifying_steps" | wc -l | tr -d ' ')"

# Sub-threshold (<4) → silent exit 0
if [ "$step_count" -lt 4 ]; then
  exit 0
fi

# ── Check freedom annotations on each qualifying step ──────────────────────
# A step is annotated if its header line OR its immediate next non-blank line
# carries one of: 🔒, 🔓, ^[[:space:]]*Low freedom:, ^[[:space:]]*Medium freedom:
unannotated_count="$(printf '%s\n' "$body" | awk '
  BEGIN { found_step = 0; checked = 0; unannotated = 0 }
  /^## / {
    # New qualifying step header reached
    if (found_step && !checked) {
      unannotated++
    }
    line = $0
    if (line ~ /^## Notes$/ || line ~ /^## Gotchas$/ ||
        line ~ /^## Cross-references$/ || line ~ /^## Reference Files$/ ||
        line ~ /^## Eval Scenarios$/ || line ~ /^## Argument parsing$/ ||
        line ~ /^## Unknown/ || line ~ /^## Worked example/) {
      found_step = 0
      checked = 0
      next
    }
    found_step = 1
    checked = 0
    # Check the header line itself for a marker
    if (line ~ /🔒/ || line ~ /🔓/ ||
        line ~ /[Ll]ow freedom:/ || line ~ /[Mm]edium freedom:/) {
      checked = 1
    }
    next
  }
  # Non-header line — if currently looking for annotation, check
  found_step && !checked && /[^[:space:]]/ {
    if ($0 ~ /🔒/ || $0 ~ /🔓/ ||
        $0 ~ /^[[:space:]]*[Ll]ow freedom:/ || $0 ~ /^[[:space:]]*[Mm]edium freedom:/) {
      checked = 1
    } else {
      # First non-blank, non-marker line after the step header — no annotation
      checked = 1  # latch so we count once per step
      unannotated++
    }
  }
  END {
    if (found_step && !checked) unannotated++
    print unannotated
  }
')"

if [ "${unannotated_count:-0}" -gt 0 ]; then
  echo "skill-rubric-advisory: ${slug} — has ${step_count} step headers but ${unannotated_count} lack a freedom annotation (🔒/🔓 or Low/Medium freedom: prefix). See .claude/skills/skill/references/skill-rubric.md § Freedom annotations." >&2
fi

# ── Check ## Eval Scenarios section ────────────────────────────────────────
has_eval_section="$(printf '%s\n' "$body" | grep -c '^## Eval Scenarios$' || true)"
if [ "${has_eval_section:-0}" -eq 0 ]; then
  echo "skill-rubric-advisory: ${slug} — has ${step_count} step headers but no \"## Eval Scenarios\" section. Add ≥2 scenarios per .claude/skills/skill/references/skill-rubric.md § Eval scenarios." >&2
else
  # Count ### Eval sub-headers inside the eval section
  eval_subheader_count="$(printf '%s\n' "$body" | awk '
    /^## Eval Scenarios$/ { in_section = 1; next }
    /^## / { in_section = 0 }
    in_section && /^### Eval / { count++ }
    END { print count + 0 }
  ')"

  if [ "${eval_subheader_count:-0}" -lt 2 ]; then
    echo "skill-rubric-advisory: ${slug} — \"## Eval Scenarios\" exists but contains ${eval_subheader_count} \"### Eval \" sub-headers (need ≥2)." >&2
  fi
fi

exit 0
