#!/usr/bin/env bash
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$ROOT/.agent0/hooks/startup-brief.sh"

payload="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup","session_id":"spec124-budget"}' "$ROOT")"
out="$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR bash "$HOOK")"

bytes="${#out}"
lines="$(printf '%s' "$out" | wc -l | tr -d ' ')"

if [ "$bytes" -gt 6000 ]; then
  printf 'FAIL: startup brief exceeds byte budget (%s)\n%s\n' "$bytes" "$out"
  exit 1
fi

if [ "$lines" -gt 80 ]; then
  printf 'FAIL: startup brief exceeds line budget (%s)\n%s\n' "$lines" "$out"
  exit 1
fi

for needle in \
  "AGENT0_STARTUP_BRIEF" \
  "mode: summary" \
  "=== handoff ===" \
  "=== context ===" \
  "END_AGENT0_STARTUP_BRIEF"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    printf 'FAIL: startup brief missing needle: %s\n%s\n' "$needle" "$out"
    exit 1
  fi
done

if printf '%s\n' "$out" | grep -qF "AGENT0_CONTEXT_INJECTION"; then
  printf 'FAIL: normal startup brief should not emit context fragment index\n%s\n' "$out"
  exit 1
fi

TMPDIR="$(mktemp -d -t agent0-startup-brief-budget-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.agent0/skills/remind/scripts"
cp "$ROOT/.agent0/skills/remind/scripts/reminders-helper.py" "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"
chmod +x "$TMPDIR/.agent0/skills/remind/scripts/reminders-helper.py"

cat > "$TMPDIR/.agent0/HANDOFF.md" <<'MD'
# Session handoff

## Current State
- Fixture state for startup budget.

## Active Work
- Fixture active work.

## Next Actions
1. Fixture next action.

## Decisions & Gotchas
- Fixture gotcha.
MD

cat > "$TMPDIR/.agent0/reminders.yaml" <<'YAML'
reminders:
  - id: r-2026-05-01-large-reminder-one
    created: '2026-05-01'
    context: This is a deliberately long reminder fixture that should be reduced to one compact startup line instead of carrying every raw helper sub-bullet into the model-visible startup context. It keeps going long enough to exercise the per-reminder truncation behavior and avoid relying only on the global byte cap.
    status: pending
    due: '2026-05-01'
    check_command: very-noisy-check-command --with --many --arguments
    links:
      - fixture-link-one
      - fixture-link-two
  - id: r-2026-05-01-large-reminder-two
    created: '2026-05-01'
    context: Second long reminder fixture that proves the summary path handles multiple entries without emitting raw sub-bullets.
    status: pending
YAML

fixture_payload="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup","session_id":"spec124-budget-fixture"}' "$TMPDIR")"
fixture_out="$(printf '%s' "$fixture_payload" | AGENT0_PROJECT_DIR="$TMPDIR" bash "$HOOK")"

if printf '%s\n' "$fixture_out" | grep -qE 'very-noisy-check-command|fixture-link-one'; then
  printf 'FAIL: startup brief emitted raw reminder helper details instead of compact summaries\n%s\n' "$fixture_out"
  exit 1
fi

if ! printf '%s\n' "$fixture_out" | grep -q 'large-reminder-one.*due: 2026-05-01'; then
  printf 'FAIL: startup brief missing compact reminder summary with due date\n%s\n' "$fixture_out"
  exit 1
fi

echo "PASS: 09-startup-brief-budget"
