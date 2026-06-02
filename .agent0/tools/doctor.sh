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
check_file() {
  local rel="$1" need_exec="${2:-no}" abs="$PROJECT_DIR/$1"
  if [ ! -e "$abs" ]; then
    check broken "$rel" "missing"
  elif [ "$need_exec" = "exec" ] && [ ! -x "$abs" ]; then
    check broken "$rel" "exists but not executable"
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
check_file ".agent0/context/rules"
# Handoff absence is degraded, not fatal.
if [ -f "$PROJECT_DIR/.agent0/HANDOFF.md" ]; then
  check ok ".agent0/HANDOFF.md" "present"
else
  check advisory ".agent0/HANDOFF.md" "missing — session handoff disabled"
fi

# --- hook wiring (per-runtime; missing one runtime → advisory) ---------------
printf '\n=== hook wiring ===\n'
wired_check() {
  local label="$1" file="$2" needle="$3" abs="$PROJECT_DIR/$2"
  if [ ! -f "$abs" ]; then
    check advisory "$label" "$file absent (runtime not configured here)"
  elif grep -q "$needle" "$abs" 2>/dev/null; then
    check ok "$label" "references $needle"
  else
    check advisory "$label" "$file present but no $needle reference"
  fi
}
wired_check "claude SessionStart" ".claude/settings.json" "startup-brief"
wired_check "codex hooks" ".codex/hooks.json" "startup-brief"

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
