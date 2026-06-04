#!/usr/bin/env bash
# squad.sh — deterministic state machine for an autonomous /squad build run (spec 150).
#
# Owns the mechanical, safety-critical state; the RUNTIME owns the loop content
# (mirrors meeting.sh: state here, turns there). The autonomous pump (initiating
# runtime → exec bridge → peer → repeat) lives in SKILL.md and drives these
# subcommands. The hard invariant: agent AGREEMENT only sets `propose-done`; the
# external `gate` (squad.json commands green) is the ONLY thing that reaches
# `ready_for_human_prod`. Bounded by round/repair ceilings — never infinite.
#
# Contract: docs/specs/<spec>/squad.json (jq-parseable; v1 uses JSON not YAML to
# avoid a yq dependency — jq is already a harness-wide dep).
#
# Terminal states: ready_for_human_prod | human_checkpoint_required |
#   aborted_budget | aborted_repairs | aborted_conflict | aborted_policy
#
# Exit codes: 0 ok; 1 not-as-expected / gate-fail; 2 usage / bad input;
#   3 turn-lock / roster violation.
#
# bash 3.2-compatible: no associative arrays, no mapfile.

set -uo pipefail

die()   { echo "squad: $*" >&2; exit 2; }
errln() { echo "squad: $*" >&2; }

command -v jq >/dev/null 2>&1 || die "jq is required"

# ── state.json helpers ───────────────────────────────────────────────────────
sget() { jq -r "$2" "$1/state.json"; }
sset() {
  # sset <run> [jq-args...] <jq-program> — pass-through any --arg/--argjson before the program
  local run=$1; shift
  local tmp; tmp="$(mktemp)"
  jq "$@" "$run/state.json" > "$tmp" && cat "$tmp" > "$run/state.json"; rm -f "$tmp"
}

_repo_root() {
  local d=$1 root
  root="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-$PWD}"
  printf '%s' "$root"
}

# working-tree fingerprint: sorted porcelain (captures modified + untracked)
_fingerprint() { git -C "$1" status --porcelain 2>/dev/null | LC_ALL=C sort; }

_is_terminal() {
  case "$1" in
    ready_for_human_prod|human_checkpoint_required|aborted_*) return 0;;
    *) return 1;;
  esac
}

# ── init ─────────────────────────────────────────────────────────────────────
cmd_init() {
  local spec="" initiator="" contract="" repo="" run_root=""
  while [ $# -gt 0 ]; do case "$1" in
    --spec)      spec=$2; shift 2;;
    --initiator) initiator=$2; shift 2;;
    --contract)  contract=$2; shift 2;;
    --repo)      repo=$2; shift 2;;
    --run-root)  run_root=$2; shift 2;;
    *) die "init: unknown arg: $1";; esac; done
  [ -n "$spec" ] || die "init: --spec <NNN-slug> required"
  [ -n "$repo" ] || repo="$(_repo_root "$PWD")"
  [ -n "$contract" ] || contract="$repo/docs/specs/$spec/squad.json"
  [ -f "$contract" ] || die "init: contract not found: $contract"
  jq -e . "$contract" >/dev/null 2>&1 || die "init: contract is not valid JSON: $contract"
  # the autonomous pump drives the peer via the exec bridges, which anchor ROOT to
  # the harness root and refuse a cwd outside it → the target repo must CONTAIN the
  # harness. Non-fatal (assisted / single-runtime can still run). (150.1 finding.)
  [ -f "$repo/.agent0/skills/codex-exec/scripts/codex-exec.sh" ] || \
    errln "init: WARNING — '$repo' has no Agent0 exec bridge (.agent0/skills/codex-exec); the autonomous pump cannot drive a peer here (bridge anchors to the harness root). Assisted/single-runtime only."

  local roster maxr maxrep
  roster="$(jq -r '(.roster // ["claude","codex"]) | join(",")' "$contract")"
  maxr="$(jq -r '.max_rounds // 20' "$contract")"
  maxrep="$(jq -r '.max_repair_attempts // 3' "$contract")"
  [ -n "$initiator" ] || initiator="$(printf '%s' "$roster" | cut -d, -f1)"

  [ -n "$run_root" ] || run_root="$repo/.agent0/.runtime-state/squads"
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local run="$run_root/${spec}-${ts}"
  mkdir -p "$run"
  local head; head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  jq -n \
    --arg spec "$spec" --arg repo "$repo" --arg contract "$contract" \
    --arg roster "$roster" --arg holder "$initiator" --arg head "$head" \
    --arg created "$ts" --argjson maxr "$maxr" --argjson maxrep "$maxrep" \
    '{schema_version:1, spec:$spec, repo:$repo, contract:$contract,
      roster:($roster|split(",")), status:"running", turn_holder:$holder,
      round:0, max_rounds:$maxr, repair_attempts:0, max_repair_attempts:$maxrep,
      proposed_done:[], start_head:$head, boundary:[], changed_paths:[], turn_start_fp:[],
      turn_open:false, created:$created}' > "$run/state.json"
  echo "$run"
}

_load_run() { [ -f "$1/state.json" ] || die "run not found: $1/state.json"; }

# ── turn lifecycle ───────────────────────────────────────────────────────────
cmd_turn_start() {
  local run="" speaker=""
  while [ $# -gt 0 ]; do case "$1" in
    --run) run=$2; shift 2;; --speaker) speaker=$2; shift 2;; *) die "turn-start: unknown arg: $1";; esac; done
  [ -n "$run" ] && [ -n "$speaker" ] || die "turn-start: --run and --speaker required"
  _load_run "$run"
  local status holder
  status="$(sget "$run" .status)"
  _is_terminal "$status" && { errln "turn-start: run is terminal ($status)"; return 1; }
  holder="$(sget "$run" .turn_holder)"
  [ "$holder" = "$speaker" ] || { errln "turn-start: not '$speaker' turn (holder=$holder) — single-writer lock"; return 3; }
  # snapshot the pre-turn fingerprint so turn-end can compute THIS turn's own delta
  # (the delta is what policy/forbidden checks must run against — see guard).
  local repo sfp; repo="$(sget "$run" .repo)"; sfp="$(_fingerprint "$repo")"
  sset "$run" --argjson sfp "$(printf '%s' "$sfp" | jq -R . | jq -s 'map(select(length>0))')" \
    '.turn_start_fp=$sfp | .turn_open=true'
  echo "turn-start: $speaker (round $(sget "$run" .round))"
}

cmd_turn_end() {
  local run="" speaker=""
  while [ $# -gt 0 ]; do case "$1" in
    --run) run=$2; shift 2;; --speaker) speaker=$2; shift 2;; *) die "turn-end: unknown arg: $1";; esac; done
  [ -n "$run" ] && [ -n "$speaker" ] || die "turn-end: --run and --speaker required"
  _load_run "$run"
  local holder repo; holder="$(sget "$run" .turn_holder)"; repo="$(sget "$run" .repo)"
  [ "$holder" = "$speaker" ] || { errln "turn-end: not '$speaker' turn (holder=$holder)"; return 3; }
  # boundary = full working-tree fingerprint (for out-of-turn conflict detection);
  # changed_paths = THIS turn's own delta vs the turn-start fingerprint (what policy
  # checks must run against — an in-turn forbidden touch lives here, not in the
  # changes-since-boundary set, which turn-end zeroes by definition).
  local fp; fp="$(_fingerprint "$repo")"
  local sfp delta
  sfp="$(sget "$run" '.turn_start_fp[]?' 2>/dev/null)"
  delta="$(comm -23 <(printf '%s\n' "$fp"  | sed '/^$/d' | LC_ALL=C sort -u) \
                    <(printf '%s\n' "$sfp" | sed '/^$/d' | LC_ALL=C sort -u))"
  sset "$run" \
    --argjson b "$(printf '%s' "$fp"    | jq -R . | jq -s 'map(select(length>0))')" \
    --argjson d "$(printf '%s' "$delta" | jq -R . | jq -s 'map(select(length>0))')" \
    '.boundary=$b | .changed_paths=$d'
  # flip holder + advance round; close the turn
  local peer; peer="$(sget "$run" '[.roster[] | select(. != "human" and . != "'"$holder"'")][0]')"
  sset "$run" --arg peer "$peer" '.turn_holder=$peer | .round=(.round+1) | .turn_open=false'
  # budget ceiling
  local round maxr; round="$(sget "$run" .round)"; maxr="$(sget "$run" .max_rounds)"
  if [ "$round" -ge "$maxr" ]; then
    sset "$run" '.status="aborted_budget"'
    echo "turn-end: round $round reached max_rounds $maxr → aborted_budget"
    return 0
  fi
  echo "turn-end: round now $round, holder → $peer"
}

cmd_propose_done() {
  local run="" speaker=""
  while [ $# -gt 0 ]; do case "$1" in
    --run) run=$2; shift 2;; --speaker) speaker=$2; shift 2;; *) die "propose-done: unknown arg: $1";; esac; done
  [ -n "$run" ] && [ -n "$speaker" ] || die "propose-done: --run and --speaker required"
  _load_run "$run"
  sset "$run" --arg s "$speaker" '.proposed_done = (.proposed_done + [$s] | unique)'
  echo "propose-done: $speaker (agreement only proposes — the gate decides)"
}

# ── gate (the ONLY path to done) ─────────────────────────────────────────────
cmd_gate() {
  local run=""
  while [ $# -gt 0 ]; do case "$1" in --run) run=$2; shift 2;; *) die "gate: unknown arg: $1";; esac; done
  [ -n "$run" ] || die "gate: --run required"
  _load_run "$run"
  local repo contract; repo="$(sget "$run" .repo)"; contract="$(sget "$run" .contract)"
  local green=1 cmd
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    if ! ( cd "$repo" && bash -c "$cmd" >/dev/null 2>&1 ); then
      green=0; errln "gate: FAILED — $cmd"; break
    fi
  done < <(jq -r '.gate[]? // empty' "$contract")

  if [ "$green" -eq 1 ]; then
    # gate green — but agreement must ALSO be present to close. Agreement alone
    # (without a green gate) can NEVER reach this branch.
    local need have
    need="$(sget "$run" '[.roster[] | select(. != "human")] | length')"
    have="$(sget "$run" '[.proposed_done[] | select(. != "human")] | unique | length')"
    if [ "$have" -ge "$need" ]; then
      sset "$run" '.status="ready_for_human_prod"'
      echo "gate: GREEN + all agents proposed done → ready_for_human_prod"
    else
      echo "gate: GREEN but only $have/$need agents proposed done — still running"
    fi
    return 0
  fi

  # gate red → count a repair attempt; abort if over ceiling
  sset "$run" '.repair_attempts=(.repair_attempts+1)'
  local att maxa; att="$(sget "$run" .repair_attempts)"; maxa="$(sget "$run" .max_repair_attempts)"
  if [ "$att" -gt "$maxa" ]; then
    sset "$run" '.status="aborted_repairs"'
    echo "gate: RED — repair attempts $att > max $maxa → aborted_repairs"
  else
    echo "gate: RED — repair attempt $att/$maxa"
  fi
  return 1
}

# ── guard (write-serialization + policy) ─────────────────────────────────────
cmd_guard() {
  local run=""
  while [ $# -gt 0 ]; do case "$1" in --run) run=$2; shift 2;; *) die "guard: unknown arg: $1";; esac; done
  [ -n "$run" ] || die "guard: --run required"
  _load_run "$run"
  local repo; repo="$(sget "$run" .repo)"
  local cur; cur="$(_fingerprint "$repo")"
  # changed paths = porcelain entries whose path is not in the recorded boundary
  local boundary; boundary="$(sget "$run" '.boundary[]?' 2>/dev/null)"
  local newlines; newlines="$(comm -23 <(printf '%s\n' "$cur" | LC_ALL=C sort -u) <(printf '%s\n' "$boundary" | LC_ALL=C sort -u))"
  newlines="$(printf '%s' "$newlines" | sed '/^$/d')"

  # policy: forbidden / human-gated path patterns from the contract.
  # Checked against the union of THIS turn's own delta (changed_paths) and any
  # out-of-turn changes (newlines) — so an in-turn forbidden touch is caught even
  # though turn-end zeroed the changes-since-boundary set. Conflict stays on newlines.
  local contract; contract="$(sget "$run" .contract)"
  local changed; changed="$(sget "$run" '.changed_paths[]?' 2>/dev/null)"
  local paths; paths="$(printf '%s\n%s\n' "$changed" "$newlines" | sed '/^$/d' | LC_ALL=C sort -u | sed -E 's/^.{2,3}//')"
  local pat hit_forbidden=0 hit_human=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s\n' "$paths" | grep -qE "$pat" && hit_forbidden=1
  done < <(jq -r '.forbidden_paths[]? // empty' "$contract")
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s\n' "$paths" | grep -qE "$pat" && hit_human=1
  done < <(jq -r '.human_gated_paths[]? // empty' "$contract")

  if [ "$hit_forbidden" -eq 1 ]; then
    sset "$run" '.status="aborted_policy"'
    echo "guard: forbidden path touched → aborted_policy"; return 1
  fi
  # out-of-turn: changes present while no turn is open
  local turn_open; turn_open="$(sget "$run" .turn_open)"
  if [ -n "$newlines" ] && [ "$turn_open" = "false" ]; then
    sset "$run" '.status="aborted_conflict"'
    echo "guard: changes detected with no open turn → aborted_conflict"; return 1
  fi
  if [ "$hit_human" -eq 1 ]; then
    sset "$run" '.status="human_checkpoint_required"'
    echo "guard: human-gated path touched → human_checkpoint_required"; return 1
  fi
  echo "guard: clean"
  return 0
}

cmd_rollback() {
  local run=""
  while [ $# -gt 0 ]; do case "$1" in --run) run=$2; shift 2;; *) die "rollback: unknown arg: $1";; esac; done
  [ -n "$run" ] || die "rollback: --run required"
  _load_run "$run"
  local repo; repo="$(sget "$run" .repo)"
  git -C "$repo" checkout -- . 2>/dev/null || true
  git -C "$repo" clean -fdq 2>/dev/null || true   # OVERRIDE handled by caller policy; squad rollback to last clean boundary
  echo "rollback: restored working tree to last committed state"
}

cmd_status() {
  local run=""
  while [ $# -gt 0 ]; do case "$1" in --run) run=$2; shift 2;; *) run=$1; shift;; esac; done
  [ -n "$run" ] || die "status: --run required"
  _load_run "$run"
  jq . "$run/state.json"
}

cmd_abort() {
  local run="" reason=""
  while [ $# -gt 0 ]; do case "$1" in --run) run=$2; shift 2;; --reason) reason=$2; shift 2;; *) die "abort: unknown arg: $1";; esac; done
  [ -n "$run" ] || die "abort: --run required"
  _load_run "$run"
  sset "$run" --arg r "${reason:-manual}" '.status="aborted_policy" | .abort_reason=$r'
  echo "abort: $reason"
}

# ── dispatch ─────────────────────────────────────────────────────────────────
main() {
  local sub=${1:-}
  [ -n "$sub" ] || die "usage: squad.sh <init|turn-start|turn-end|propose-done|gate|guard|rollback|status|abort> ..."
  shift
  case "$sub" in
    init)         cmd_init "$@";;
    turn-start)   cmd_turn_start "$@";;
    turn-end)     cmd_turn_end "$@";;
    propose-done) cmd_propose_done "$@";;
    gate)         cmd_gate "$@";;
    guard)        cmd_guard "$@";;
    rollback)     cmd_rollback "$@";;
    status)       cmd_status "$@";;
    abort)        cmd_abort "$@";;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
