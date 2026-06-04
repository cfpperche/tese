#!/usr/bin/env bash
# Scenario 11: clean publish boundary requires the latest session commit to
# include .agent0/HANDOFF.md.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
START_HOOK="$AGENT0_ROOT/.agent0/hooks/session-start.sh"
STOP_HOOK="$AGENT0_ROOT/.agent0/hooks/session-stop.sh"

make_repo() {
  local dir="$1"
  local remote="$2"

  git init -q -b main "$dir"
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "test"
  mkdir -p "$dir/.agent0"
  printf '# Session handoff\n\ninitial\n' >"$dir/.agent0/HANDOFF.md"
  printf '.agent0/.session-state/\n' >"$dir/.gitignore"
  printf 'initial\n' >"$dir/tracked.txt"
  git -C "$dir" add .gitignore .agent0/HANDOFF.md tracked.txt
  git -C "$dir" commit -q -m initial

  git init -q --bare "$remote"
  git -C "$dir" remote add origin "$remote"
  git -C "$dir" push -q -u origin main
}

start_session() {
  local dir="$1"
  local session_id="$2"
  local payload
  export CLAUDE_PROJECT_DIR="$dir"
  payload="$(jq -cn --arg sid "$session_id" --arg cwd "$dir" '{
    hook_event_name: "SessionStart",
    source: "startup",
    session_id: $sid,
    cwd: $cwd
  }')"
  printf '%s' "$payload" | bash "$START_HOOK" >/dev/null

  if [ ! -s "$dir/.agent0/.session-state/$session_id/start-head" ]; then
    printf 'FAIL: SessionStart did not record start-head for %s\n' "$session_id"
    exit 1
  fi
}

stop_session() {
  local dir="$1"
  local session_id="$2"
  local payload
  export CLAUDE_PROJECT_DIR="$dir"
  payload="$(jq -cn --arg sid "$session_id" --arg cwd "$dir" '{
    hook_event_name: "Stop",
    session_id: $sid,
    cwd: $cwd,
    stop_hook_active: false
  }')"
  printf '%s' "$payload" | bash "$STOP_HOOK" 2>&1 || true
}

TMP_STALE="$(mktemp -d -t spec-148-11-stale-XXXXXX)"
TMP_STALE_REMOTE="$(mktemp -d -t spec-148-11-stale-remote-XXXXXX)"
TMP_EARLY="$(mktemp -d -t spec-148-11-early-XXXXXX)"
TMP_EARLY_REMOTE="$(mktemp -d -t spec-148-11-early-remote-XXXXXX)"
TMP_FRESH="$(mktemp -d -t spec-148-11-fresh-XXXXXX)"
TMP_FRESH_REMOTE="$(mktemp -d -t spec-148-11-fresh-remote-XXXXXX)"
TMP_AHEAD="$(mktemp -d -t spec-148-11-ahead-XXXXXX)"
TMP_AHEAD_REMOTE="$(mktemp -d -t spec-148-11-ahead-remote-XXXXXX)"
trap 'rm -rf "$TMP_STALE" "$TMP_STALE_REMOTE" "$TMP_EARLY" "$TMP_EARLY_REMOTE" "$TMP_FRESH" "$TMP_FRESH_REMOTE" "$TMP_AHEAD" "$TMP_AHEAD_REMOTE"' EXIT

make_repo "$TMP_STALE" "$TMP_STALE_REMOTE"
start_session "$TMP_STALE" "test-publish-stale-11"
printf 'changed\n' >"$TMP_STALE/tracked.txt"
git -C "$TMP_STALE" add tracked.txt
git -C "$TMP_STALE" commit -q -m "change without handoff"
git -C "$TMP_STALE" push -q
stale_output="$(stop_session "$TMP_STALE" "test-publish-stale-11")"

if ! printf '%s' "$stale_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop did not block clean pushed session with stale HANDOFF.md\n%s\n' "$stale_output"
  exit 1
fi
if ! printf '%s' "$stale_output" | grep -q 'clean publish boundary'; then
  printf 'FAIL: publish-boundary block reason was not specific\n%s\n' "$stale_output"
  exit 1
fi

make_repo "$TMP_EARLY" "$TMP_EARLY_REMOTE"
start_session "$TMP_EARLY" "test-publish-early-11"
printf '# Session handoff\n\nearly closeout text\n' >"$TMP_EARLY/.agent0/HANDOFF.md"
git -C "$TMP_EARLY" add .agent0/HANDOFF.md
git -C "$TMP_EARLY" commit -q -m "early handoff"
printf 'changed after handoff\n' >"$TMP_EARLY/tracked.txt"
git -C "$TMP_EARLY" add tracked.txt
git -C "$TMP_EARLY" commit -q -m "later change"
git -C "$TMP_EARLY" push -q
early_output="$(stop_session "$TMP_EARLY" "test-publish-early-11")"

if ! printf '%s' "$early_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop did not block when HANDOFF.md was updated before a later pushed commit\n%s\n' "$early_output"
  exit 1
fi

make_repo "$TMP_FRESH" "$TMP_FRESH_REMOTE"
start_session "$TMP_FRESH" "test-publish-fresh-11"
printf 'changed\n' >"$TMP_FRESH/tracked.txt"
printf '# Session handoff\n\npost-push reality recorded\n' >"$TMP_FRESH/.agent0/HANDOFF.md"
git -C "$TMP_FRESH" add tracked.txt .agent0/HANDOFF.md
git -C "$TMP_FRESH" commit -q -m "change with handoff"
git -C "$TMP_FRESH" push -q
fresh_output="$(stop_session "$TMP_FRESH" "test-publish-fresh-11")"

if printf '%s' "$fresh_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop blocked even though latest pushed commit includes HANDOFF.md\n%s\n' "$fresh_output"
  exit 1
fi

make_repo "$TMP_AHEAD" "$TMP_AHEAD_REMOTE"
start_session "$TMP_AHEAD" "test-publish-ahead-11"
printf 'changed\n' >"$TMP_AHEAD/tracked.txt"
git -C "$TMP_AHEAD" add tracked.txt
git -C "$TMP_AHEAD" commit -q -m "local change without push"
ahead_output="$(stop_session "$TMP_AHEAD" "test-publish-ahead-11")"

if printf '%s' "$ahead_output" | grep -q '"decision":"block"'; then
  printf 'FAIL: Stop blocked clean local-ahead session before publish boundary\n%s\n' "$ahead_output"
  exit 1
fi

printf 'PASS\n'
exit 0
