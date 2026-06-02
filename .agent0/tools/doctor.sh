#!/usr/bin/env bash
# Agent0 `doctor` — harness health check.
#
# Answers "is this harness wired and recoverable?" with a per-check tri-state
# (ok / advisory / broken) and a severity-based exit code. Reports + proposes,
# never fixes (mirrors vuln-audit discipline). Runtime-neutral: inspects BOTH
# .claude/settings.json and .codex/hooks.json wiring. Invoke as
# `! bash .agent0/tools/doctor.sh` (human), or directly from any runtime. (Spec 137.)
#
# Exit code: non-zero iff any check is `broken`. Advisories never fail the exit.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The harness root to inspect — honor AGENT0_PROJECT_DIR (lets doctor check an
# arbitrary checkout / fixture), else the git root of this checkout.
if [ -n "${AGENT0_PROJECT_DIR:-}" ]; then
  PROJECT_DIR="$AGENT0_PROJECT_DIR"
else
  PROJECT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

OK=0; ADVISORY=0; BROKEN=0

# check <status> <name> <detail>
check() {
  local status="$1" name="$2" detail="$3" mark
  case "$status" in
    ok)       mark='[ ok ]      '; OK=$((OK + 1)) ;;
    advisory) mark='[ advisory ]'; ADVISORY=$((ADVISORY + 1)) ;;
    broken)   mark='[ BROKEN ]  '; BROKEN=$((BROKEN + 1)) ;;
  esac
  printf '%s %-34s %s\n' "$mark" "$name" "$detail"
}

# --- core harness files (missing/non-exec → broken) -------------------------
# check_file <relpath> [exec|dir]
#   exec → must be executable AND non-empty (presence != function, dogfood D2)
#   dir  → must be a directory, not a stray file of that name (dogfood D2)
check_file() {
  local rel="$1" mode="${2:-no}" abs="$PROJECT_DIR/$1"
  if [ ! -e "$abs" ]; then
    check broken "$rel" "missing"
  elif [ "$mode" = "dir" ]; then
    if [ -d "$abs" ]; then check ok "$rel" "present"; else check broken "$rel" "exists but is not a directory"; fi
  elif [ "$mode" = "exec" ] && [ ! -x "$abs" ]; then
    check broken "$rel" "exists but not executable"
  elif [ "$mode" = "exec" ] && [ ! -s "$abs" ]; then
    check broken "$rel" "present but empty"
  else
    check ok "$rel" "present"
  fi
}

printf '=== Agent0 doctor: core files ===\n'
check_file ".agent0/hooks/startup-brief.sh" exec
check_file ".agent0/hooks/_brief-compose.sh"
check_file ".agent0/hooks/_memory-hook-lib.sh"
check_file ".agent0/hooks/reminders-readout.sh" exec
check_file ".agent0/hooks/routines-readout.sh" exec
check_file ".agent0/tools/status.sh" exec
check_file ".agent0/tools/doctor.sh" exec
check_file ".agent0/context/rules" dir
# Handoff absence is degraded, not fatal.
if [ -f "$PROJECT_DIR/.agent0/HANDOFF.md" ]; then
  check ok ".agent0/HANDOFF.md" "present"
else
  check advisory ".agent0/HANDOFF.md" "missing — session handoff disabled"
fi

# --- hook wiring (per-runtime; contract validation, not substring) -----------
# Spec 139: validate the actual SessionStart→startup-brief binding, not a bare
# substring anywhere in the file (which passes on a comment / disabled block /
# wrong event). Config absent → advisory (runtime not configured here); config
# present but no valid binding → broken (the harness claims to be wired but is
# not); bound AND target present+executable → ok. jq absent → degrade to the old
# substring behavior tagged advisory (never crash).
printf '\n=== hook wiring ===\n'
BRIEF_REL=".agent0/hooks/startup-brief.sh"
BRIEF_ABS="$PROJECT_DIR/$BRIEF_REL"
wired_check() {
  local label="$1" file="$2" abs="$PROJECT_DIR/$2" cmd
  if [ ! -f "$abs" ]; then
    check advisory "$label" "$file absent (runtime not configured here)"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    # jq is a REQUIRED binary (the binaries block already marks its absence
    # broken → the rollup is broken regardless). Here we can only report that the
    # wiring contract is unverifiable, not assert it; advisory is honest.
    if grep -q "startup-brief" "$abs" 2>/dev/null; then
      check advisory "$label" "references startup-brief (jq required to verify the binding — jq missing → rollup broken via binaries)"
    else
      check advisory "$label" "$file present; jq required to verify the binding — jq missing → rollup broken via binaries"
    fi
    return
  fi
  # Pull every SessionStart command string; match the one binding startup-brief.
  cmd="$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command // empty] | map(select(test("startup-brief"))) | .[0] // empty' "$abs" 2>/dev/null)"
  if [ -z "$cmd" ]; then
    check broken "$label" "$file present but no SessionStart hook binds startup-brief"
  elif [ ! -x "$BRIEF_ABS" ]; then
    check broken "$label" "binds startup-brief but $BRIEF_REL is missing/not executable"
  else
    check ok "$label" "SessionStart → startup-brief, target present+exec"
  fi
}
wired_check "claude SessionStart" ".claude/settings.json"
wired_check "codex hooks" ".codex/hooks.json"

# --- git hooks activation ----------------------------------------------------
printf '\n=== git hooks ===\n'
if [ -d "$PROJECT_DIR/.githooks" ]; then
  hp="$(git -C "$PROJECT_DIR" config --get core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = ".githooks" ]; then
    check ok "core.hooksPath" "activated (.githooks)"
  else
    check advisory "core.hooksPath" "NOT activated — run: git config core.hooksPath .githooks"
  fi
else
  check advisory "core.hooksPath" ".githooks/ absent — no native git hooks to wire"
fi

# --- binaries (required → broken; optional → advisory) -----------------------
printf '\n=== binaries ===\n'
bin_check() {
  local bin="$1" tier="$2" note="${3:-}"
  if command -v "$bin" >/dev/null 2>&1; then
    check ok "$bin" "found"
  elif [ "$tier" = "required" ]; then
    check broken "$bin" "MISSING (required) ${note}"
  else
    check advisory "$bin" "absent (optional) ${note}"
  fi
}
bin_check git      required
bin_check jq       required "— hook payload parsing degrades without it"
bin_check python3  required "— memory/context helpers need it"
bin_check gitleaks optional "— secrets pre-commit scan"
bin_check osv-scanner optional "— vuln-audit engine"

# --- rollup ------------------------------------------------------------------
printf '\n=== rollup ===\n'
if [ "$BROKEN" -gt 0 ]; then
  verdict="BROKEN"
elif [ "$ADVISORY" -gt 0 ]; then
  verdict="ADVISORY"
else
  verdict="OK"
fi
printf '%s — %d ok, %d advisory, %d broken\n' "$verdict" "$OK" "$ADVISORY" "$BROKEN"

[ "$BROKEN" -gt 0 ] && exit 1
exit 0
