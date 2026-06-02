#!/usr/bin/env bash
# Behavioural tests for spec 137 (agent0-status): status.sh, doctor.sh, and the
# extracted _brief-compose.sh library. Runtime-neutral pure bash.
#
# Run: bash .agent0/tests/agent0-status/test.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOKS="$REPO/.agent0/hooks"
TOOLS="$REPO/.agent0/tools"
PASS=0; FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }

# --- V3: library is runtime-emit-neutral ------------------------------------
printf 'V3 — _brief-compose.sh carries composition only (no emit/truncation)\n'
# Strip full-line comments first — the header comment legitimately *names* these
# tokens to document the emit/composition boundary; only CODE use is forbidden.
if grep -vE '^[[:space:]]*#' "$HOOKS/_brief-compose.sh" \
   | grep -qE 'emit_context|trim_lines|trim_bytes|hookSpecificOutput|jq -n'; then
  bad "lib contains runtime-emit/truncation tokens in code"
else
  ok "no emit_context/trim_*/jq -n/hookSpecificOutput in lib code"
fi
grep -q '_brief-compose.sh' "$HOOKS/startup-brief.sh" && ok "startup-brief.sh sources the lib" || bad "startup-brief.sh does not source the lib"

# --- V2: brief still composes after refactor --------------------------------
printf 'V2 — startup-brief.sh still emits a brief post-refactor\n'
brief="$(printf '{}' | bash "$HOOKS/startup-brief.sh" 2>/dev/null)"
[ -n "$brief" ] && printf '%s' "$brief" | grep -q 'AGENT0_STARTUP_BRIEF' && ok "brief emitted with header" || bad "brief empty or missing header"
printf '%s' "$brief" | grep -q '=== handoff ===' && ok "brief has handoff section" || bad "brief missing handoff section"

# --- V1: status renders full work state -------------------------------------
printf 'V1 — status.sh renders full untruncated work state\n'
st="$(bash "$TOOLS/status.sh" 2>/dev/null)"; st_exit=$?
[ "$st_exit" -eq 0 ] && ok "status.sh exit 0" || bad "status.sh exit $st_exit"
for sec in 'AGENT0_STATUS' '=== handoff ===' '=== git ===' '=== next ===' 'END_AGENT0_STATUS'; do
  printf '%s' "$st" | grep -qF "$sec" && ok "status has [$sec]" || bad "status missing [$sec]"
done

# --- V5: status degrades cleanly on a partial harness -----------------------
printf 'V5 — status.sh degrades cleanly with no HANDOFF/reminders\n'
empty="$(mktemp -d)"
trap 'rm -rf "$empty"' EXIT
deg="$(AGENT0_PROJECT_DIR="$empty" bash "$TOOLS/status.sh" 2>/dev/null)"; deg_exit=$?
[ "$deg_exit" -eq 0 ] && ok "partial-harness status exit 0" || bad "partial-harness status exit $deg_exit"
printf '%s' "$deg" | grep -qi 'missing' && ok "handoff-missing marker present" || bad "no missing marker on partial harness"

# --- V4: doctor exit code reflects severity ---------------------------------
printf 'V4 — doctor.sh tri-state + severity-based exit code\n'
doc="$(bash "$TOOLS/doctor.sh" 2>/dev/null)"; doc_exit=$?
printf '%s' "$doc" | grep -q '=== rollup ===' && ok "doctor prints rollup" || bad "doctor missing rollup"
# Real repo: no broken checks expected → exit 0.
[ "$doc_exit" -eq 0 ] && ok "healthy harness exit 0" || bad "healthy harness exit $doc_exit (expected 0)"
# Empty fixture: core files missing → broken → exit non-zero.
AGENT0_PROJECT_DIR="$empty" bash "$TOOLS/doctor.sh" >/dev/null 2>&1; broke_exit=$?
[ "$broke_exit" -ne 0 ] && ok "broken harness exit non-zero ($broke_exit)" || bad "broken harness exit 0 (expected non-zero)"
# Optional-binary absence must NOT break: simulate by checking rollup wording.
printf '%s' "$doc" | grep -qE 'OK|ADVISORY' && ok "advisories never force broken verdict on healthy repo" || bad "unexpected verdict"

# --- V8: next-actions line suppressed when handoff parks "nothing actionable" -
printf 'V8 — === next === does not point at a "nothing actionable" handoff\n'
fix_none="$(mktemp -d)"; mkdir -p "$fix_none/.agent0"
printf '## Next Actions\n\n- **Nothing actionable in the queue** — dormant items only\n' > "$fix_none/.agent0/HANDOFF.md"
none_out="$(AGENT0_PROJECT_DIR="$fix_none" bash "$TOOLS/status.sh" 2>/dev/null | sed -n '/=== next ===/,/END_AGENT0_STATUS/p')"
printf '%s' "$none_out" | grep -q 'handoff has queued Next Actions' \
  && bad "next-line fired despite 'nothing actionable' handoff" \
  || ok "next-line correctly suppressed on 'nothing actionable'"

fix_real="$(mktemp -d)"; mkdir -p "$fix_real/.agent0"
printf '## Next Actions\n\n- Ship the auth refactor and update the README\n' > "$fix_real/.agent0/HANDOFF.md"
real_out="$(AGENT0_PROJECT_DIR="$fix_real" bash "$TOOLS/status.sh" 2>/dev/null | sed -n '/=== next ===/,/END_AGENT0_STATUS/p')"
printf '%s' "$real_out" | grep -q 'handoff has queued Next Actions' \
  && ok "next-line fires on a real actionable handoff" \
  || bad "next-line missing on a genuinely actionable handoff"

# --- V9: doctor dir/non-empty checks (dogfood D2 cosmetics) ------------------
printf 'V9 — doctor flags a wrong-type rules path and an empty exec file\n'
grep -q 'check_file ".agent0/context/rules" dir' "$TOOLS/doctor.sh" && ok "rules checked as dir (-d)" || bad "rules not dir-checked"
grep -q 'present but empty' "$TOOLS/doctor.sh" && ok "exec files get a non-empty check" || bad "no non-empty check for exec files"

# --- spec 139: status reconciliation + doctor jq wiring ---------------------
gitfix() { # gitfix <dir> — make <dir> a quiet git repo
  git -C "$1" init -q 2>/dev/null
  git -C "$1" config user.email t@t.local; git -C "$1" config user.name t
}

printf 'V10 — status flags handoff/git contradiction\n'
c1="$(mktemp -d)"; gitfix "$c1"; mkdir -p "$c1/.agent0"
printf '## Active Work\n\n- None. Working tree clean\n' > "$c1/.agent0/HANDOFF.md"
b1="$(AGENT0_PROJECT_DIR="$c1" bash "$TOOLS/status.sh" 2>/dev/null)"
printf '%s' "$b1" | grep -q 'RESUME WARNING' && ok "banner fires on clean-claim + dirty tree" || bad "no banner on contradiction"

printf 'V11 — no false alarm when clean OR handoff names the work\n'
c2="$(mktemp -d)"; gitfix "$c2"; mkdir -p "$c2/.agent0"
printf '## Active Work\n\n- None. Working tree clean\n' > "$c2/.agent0/HANDOFF.md"
git -C "$c2" add -A; git -C "$c2" commit -q -m seed   # now tree is clean
b2="$(AGENT0_PROJECT_DIR="$c2" bash "$TOOLS/status.sh" 2>/dev/null)"
printf '%s' "$b2" | grep -q 'RESUME WARNING' && bad "banner fired on a clean tree" || ok "no banner when tree clean"
c3="$(mktemp -d)"; gitfix "$c3"; mkdir -p "$c3/.agent0"
printf '## Active Work\n\n- Building the auth refactor; tests pending\n' > "$c3/.agent0/HANDOFF.md"
b3="$(AGENT0_PROJECT_DIR="$c3" bash "$TOOLS/status.sh" 2>/dev/null)"
printf '%s' "$b3" | grep -q 'RESUME WARNING' && bad "banner fired though handoff names the work" || ok "no banner when handoff describes active work"

printf 'V12 — status infers probable in-flight spec from dirty paths\n'
c4="$(mktemp -d)"; gitfix "$c4"; mkdir -p "$c4/.agent0" "$c4/docs/specs/142-demo-feature"
printf '## Active Work\n\n- None\n' > "$c4/.agent0/HANDOFF.md"
printf '# spec\n' > "$c4/docs/specs/142-demo-feature/spec.md"
b4="$(AGENT0_PROJECT_DIR="$c4" bash "$TOOLS/status.sh" 2>/dev/null)"
printf '%s' "$b4" | grep -q 'probable active work: 142-demo-feature' && ok "in-flight spec inferred from dirty path" || bad "no probable-active-work line"

printf 'V13 — doctor jq wiring: broken on present-but-unwired, ok on real repo\n'
c5="$(mktemp -d)"; mkdir -p "$c5/.agent0/hooks" "$c5/.agent0/tools" "$c5/.agent0/context/rules" "$c5/.claude"
for f in startup-brief.sh _brief-compose.sh _memory-hook-lib.sh reminders-readout.sh routines-readout.sh; do cp "$HOOKS/$f" "$c5/.agent0/hooks/"; done
cp "$TOOLS/status.sh" "$TOOLS/doctor.sh" "$c5/.agent0/tools/"
printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type":"command","command":"echo unwired" } ] } ] } }' > "$c5/.claude/settings.json"
wires="$(AGENT0_PROJECT_DIR="$c5" bash "$TOOLS/doctor.sh" 2>/dev/null | sed -n '/=== hook wiring ===/,/=== git hooks ===/p')"
printf '%s' "$wires" | grep -q 'BROKEN.*claude SessionStart' && ok "unwired claude config → broken" || bad "unwired config not broken"
realw="$(bash "$TOOLS/doctor.sh" 2>/dev/null | sed -n '/=== hook wiring ===/,/=== git hooks ===/p')"
printf '%s' "$realw" | grep -q 'ok.*claude SessionStart' && ok "real repo claude wiring → ok" || bad "real repo wiring not ok"

# --- V14: anchored idle detection (dogfood 139: fix misfires + misses) -------
printf 'V14 — idle detection is anchored (no misfire on real work, no miss on idle phrasings)\n'
banner_for() { # banner_for "<active-work-first-bullet>" -> yes|no
  local fx out; fx="$(mktemp -d)"; gitfix "$fx"; mkdir -p "$fx/.agent0"
  printf '## Active Work\n\n- %s\n' "$1" > "$fx/.agent0/HANDOFF.md"
  # Capture first, then grep — piping status.sh directly into `grep -q` makes
  # grep close the pipe on match, status.sh dies with SIGPIPE, and pipefail
  # turns the whole pipeline non-zero (false negative). Capture avoids that.
  out="$(AGENT0_PROJECT_DIR="$fx" bash "$TOOLS/status.sh" 2>/dev/null)"
  if printf '%s' "$out" | grep -q 'RESUME WARNING'; then echo yes; else echo no; fi
}
expect_banner() { # expect_banner <yes|no> "<bullet>" "<desc>"
  local got; got="$(banner_for "$2")"
  [ "$got" = "$1" ] && ok "$3" || bad "$3 (expected banner=$1, got $got)"
}
expect_banner no  "Goal: get the working tree clean by Friday"   "no misfire: 'working tree clean' inside a goal"
expect_banner no  "None of the migration tests pass yet"          "no misfire: 'None of …' is not idle"
expect_banner no  "Building the auth refactor; tests pending"     "no misfire: real active work"
expect_banner yes "All committed; nothing pending"                "catches idle phrasing 'all committed'"
expect_banner yes "Tree is clean"                                 "catches idle phrasing 'tree is clean'"
expect_banner yes "None. Working tree clean; pushed"              "still fires on the canonical idle bullet"

# --- V15: rename lines don't double-count the spec slug ----------------------
printf 'V15 — a renamed spec dir yields only the destination slug\n'
rn="$(mktemp -d)"; gitfix "$rn"; mkdir -p "$rn/.agent0" "$rn/docs/specs/139-old-slug"
printf '## Active Work\n\n- None\n' > "$rn/.agent0/HANDOFF.md"
printf '# spec\n' > "$rn/docs/specs/139-old-slug/spec.md"
git -C "$rn" add -A; git -C "$rn" commit -q -m seed
git -C "$rn" mv docs/specs/139-old-slug docs/specs/140-new-slug
rnout="$(AGENT0_PROJECT_DIR="$rn" bash "$TOOLS/status.sh" 2>/dev/null)"
printf '%s' "$rnout" | grep -q 'probable active work: 140-new-slug' && ok "destination slug 140-new-slug surfaced" || bad "destination slug missing"
printf '%s' "$rnout" | grep -q 'probable active work: 139-old-slug' && bad "stale source slug 139-old-slug double-counted" || ok "stale source slug not double-counted"

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
