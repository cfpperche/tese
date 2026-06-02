#!/usr/bin/env bash
# .agent0/hooks/governance-gate.sh
# PreToolUse(Bash) hook enforcing a project-wide safety floor. Runtime-neutral
# (Claude + Codex) — relocated from .claude/hooks/ by spec 107.
#
# Blocks three pattern families:
#   1. Destructive ops    — rm with -r/-R + -f (combined OR separate flags);
#                           git push --force / -f; git reset --hard;
#                           git clean -f with -d/-x; whole-tree git checkout/restore (. or :/)
#   2. Hook bypass        — git commit --no-verify, git push --no-verify
#   3. Blanket staging    — git add -A/--all/./*, git commit -a/-am/-ma/--all
#
# DESIGN — speed-bump, NOT a sandbox. This gate catches the common-and-obvious
# destructive shapes, not every possible one. It deliberately does NOT chase
# shell primitives (`dd`, `truncate`, `: > file`, `chmod -R`, `find -delete`/
# `-exec rm`) — those have unbounded forms, and adding regexes would imply a
# completeness the hook cannot deliver and breed false confidence. An agent
# determined to be destructive has infinite shell forms (pipes, eval, xargs,
# scripts); this gate is a deliberate friction point on the obvious cases, with
# the override as the conscious escape hatch. Non-coverage is by design, not
# oversight (see docs/specs/107-governance-gate-refinement/).
#
# Override: append `# OVERRIDE: <reason>` to the command, where the reason
# (whitespace-trimmed) is >= 10 characters. Case-sensitive marker. This is the
# canonical override-marker precedent the other gates (delegation, secrets-scan,
# tdd) cite.
#
# Exit codes: 0 = allow, 2 = block (Claude Code re-prompts the agent with stderr).
# jq is a hard dependency; if missing, the hook fails closed (exit 2).
#
# Multi-runtime: reads only tool_input.command (identical on Claude + Codex);
# PreToolUse(Bash) blocks identically on both. No state, no PROJECT_DIR.
#
# bash 3.2-compatible: no associative arrays, no mapfile.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

# --- Pre-jq fast-path probe ---
# 99% of Bash commands carry none of this gate's trigger keywords. Checking the
# raw JSON for any trigger fragment before paying for `jq` short-circuits the
# no-op path.
#
# CRITICAL INVARIANT — the probe is a NECESSARY pre-filter, not a fall-through:
# a probe-MISS `exit 0`s immediately (see below), so the command is ALLOWED
# WITHOUT reaching the full family regexes. Therefore the probe keyword set MUST
# be a SUPERSET of every Family 1-3 trigger — if a family's keyword is absent
# here, that destructive command silently skips the gate (false-negative). A
# probe-HIT just pays for the full parse (false-positive is harmless — slower).
# The `.agent0/tests/governance-gate/` drift-guard exercises a representative
# blocked command per family end-to-end; if a new family is added without its
# keyword here, that command stops blocking and the test goes red.
#
# Keyword set, mirroring Family 1-3: `rm -`, `--force`/`-f` (push), `--no-verify`,
# `--hard`, blanket `add`, `commit -a/--all`, and the git subcommands `clean` /
# `checkout` / `restore` (their dangerous shapes are disambiguated by the full
# regex; the probe over-matches innocent `make clean` etc., which is harmless).
# `OVERRIDE` is included so the marker check still runs even when the actual
# pattern isn't in this raw string (defense-in-depth).
if ! printf '%s' "$INPUT" \
    | grep -qE 'rm[[:space:]]+-|--force|--no-verify|--hard|add[[:space:]]+(-A|--all|\\\.|\\\*|\.|\*)|commit[[:space:]]+-[a-zA-Z]*a|commit[[:space:]]+--all|push[[:space:]]+[^"|]*-[a-zA-Z]*f|[[:space:]](clean|checkout|restore)([[:space:]]|\\")|OVERRIDE'; then
  exit 0
fi

if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"; then
  cat >&2 <<'EOF'
governance-gate: failed to parse PreToolUse JSON (jq missing or malformed input).
Failing closed (exit 2) — install jq to restore Bash tool usage.
EOF
  exit 2
fi

[ -z "$CMD" ] && exit 0

# --- Override check: literal `# OVERRIDE: <reason ≥10 chars after trim>` ---
override_line="$(printf '%s' "$CMD" | grep -oE '# OVERRIDE: .*' | head -1 || true)"
if [ -n "$override_line" ]; then
  reason="${override_line#'# OVERRIDE: '}"
  reason="$(printf '%s' "$reason" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ ${#reason} -ge 10 ]; then
    exit 0
  fi
fi

# --- Pattern families (first match wins) ---
family=""
trigger=""

# Family 1: Destructive ops
# rm with BOTH a recursive flag (-r/-R, combined or separate) AND a force flag
# (-f), in any token order. The three sub-conditions (rm present / recursive /
# force) replace the old single-token regex so `rm -r -f` and `rm -f -r` no
# longer evade the gate while `rm -r` (no force), `rm -i`, and `grep -rf` stay
# allowed. The combined `-rf`/`-fr` token still matches (it satisfies both the
# recursive and force checks).
if printf '%s' "$CMD" | grep -qE '\brm([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '\brm[^|;&]*[[:space:]]-([a-zA-Z]*[rR]|-recursive)' \
   && printf '%s' "$CMD" | grep -qE '\brm[^|;&]*[[:space:]]-([a-zA-Z]*[fF]|-force)'; then
  family="destructive"
  trigger="rm with recursive (-r/-R) and force (-f) flags"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*push\b[^|;&]*--force([[:space:]]|$)'; then
  family="destructive"
  trigger="git push --force"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*push\b[^|;&]*[[:space:]]-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)'; then
  family="destructive"
  trigger="git push -f"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*reset[[:space:]]+--hard([[:space:]]|$)'; then
  family="destructive"
  trigger="git reset --hard"
# git clean with force (-f/--force) AND a broad signal (-d dirs / -x ignored),
# excluding dry-run (-n/--dry-run). The untracked/ignored half of "destroy
# uncommitted work" — same family as `git reset --hard` (the tracked half).
# `git clean -f <path>` (narrow, no -d/-x) and `git clean -n` stay allowed.
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]([^|;&]*[[:space:]])?clean([[:space:]]|$)' \
     && ! printf '%s' "$CMD" | grep -qE 'clean[^|;&]*[[:space:]]-([a-zA-Z]*n|-dry-run)' \
     && printf '%s' "$CMD" | grep -qE 'clean[^|;&]*[[:space:]]-([a-zA-Z]*[fF]|-force)' \
     && printf '%s' "$CMD" | grep -qE 'clean[^|;&]*[[:space:]]-[a-zA-Z]*[dx]'; then
  family="destructive"
  trigger="git clean -f with -d/-x (untracked-work destruction)"
# Whole-worktree discard via checkout/restore — the dangerous shape is the
# whole-tree pathspec (`.` or `:/`), NOT a targeted file. `git checkout -- .`,
# `git restore .`, `git restore --staged .` block; `git checkout -- <file>`,
# branch switches, and targeted `git restore <path>` stay allowed.
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]([^|;&]*[[:space:]])?(checkout|restore)\b[^|;&]*[[:space:]](\.|:/)([[:space:]]|$)'; then
  family="destructive"
  trigger="git checkout/restore of the whole worktree (. or :/)"

# Family 2: Hook bypass (meta-defense)
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*commit\b[^|;&]*--no-verify([[:space:]]|$)'; then
  family="no-verify"
  trigger="git commit --no-verify"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*push\b[^|;&]*--no-verify([[:space:]]|$)'; then
  family="no-verify"
  trigger="git push --no-verify"

# Family 3: Blanket staging
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*add[[:space:]]+(-A|--all|\.|\*)([[:space:]]|$)'; then
  family="blanket-staging"
  trigger="git add -A / --all / . / *"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+([^[:space:];|&]+[[:space:]]+)*commit[[:space:]]+(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
  family="blanket-staging"
  trigger="git commit -a / -am / -ma / --all"
fi

[ -z "$family" ] && exit 0

cat >&2 <<EOF
governance-gate: blocked [$family]

Triggered: $trigger
Command:   $CMD

This project enforces a safety floor against destructive operations, hook
bypass, and blanket staging. If you have a real reason to run this command,
append an inline override marker (>= 10 chars of reason after 'OVERRIDE:'):

  <your command>  # OVERRIDE: <why, >= 10 chars>

Marker is case-sensitive: '# OVERRIDE: ' (uppercase, colon, space).
EOF

exit 2
