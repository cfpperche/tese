#!/usr/bin/env bash
# Spec 125 — flatten-safe inline markers must be present in both emitters
# WITHOUT regressing any spec-124 pinned substring (additive contract).
set -euo pipefail

ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
BRIEF="$ROOT/.agent0/hooks/startup-brief.sh"
INJECT="$ROOT/.agent0/hooks/context-inject.sh"

# --- 1. Startup brief: '▸' sub-section markers co-exist with pinned '=== handoff ===' ---
brief_payload="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup","session_id":"spec125-markers"}' "$ROOT")"
brief_out="$(printf '%s' "$brief_payload" | env -u CLAUDE_PROJECT_DIR bash "$BRIEF")"

for needle in \
  "=== handoff ===" \
  "▸ Current State:" \
  "▸ Active Work:" \
  "▸ Next Actions:"; do
  if ! printf '%s\n' "$brief_out" | grep -qF "$needle"; then
    printf 'FAIL: startup brief missing flatten-safe needle: %s\n%s\n' "$needle" "$brief_out"
    exit 1
  fi
done

# The marker must NOT have displaced the section-level pinned label.
if ! printf '%s\n' "$brief_out" | grep -qF "=== context ==="; then
  printf 'FAIL: startup brief lost pinned section label === context ===\n%s\n' "$brief_out"
  exit 1
fi

# --- 2. Capsule block: '▸ ---' boundary co-exists with pinned source:/mode: ---
inject_out="$(
  AGENT0_PROJECT_DIR="$ROOT" bash "$INJECT" <<JSON
{"hook_event_name":"UserPromptSubmit","cwd":"$ROOT","prompt":"vamos mexer em docs/specs e seguir SDD"}
JSON
)"

for needle in \
  "mode: prompt-capsules" \
  "▸ ---" \
  "source: .agent0/context/rules/spec-driven.md" \
  "capsule: Read this file before acting"; do
  if ! printf '%s\n' "$inject_out" | grep -qF "$needle"; then
    printf 'FAIL: capsule block missing flatten-safe needle: %s\n%s\n' "$needle" "$inject_out"
    exit 1
  fi
done

# Boundary marker count must equal capsule/source-pointer count (one '▸ ---'
# per '^source:' across both deterministic rule capsules and retrieval pointers).
boundary_count="$(printf '%s\n' "$inject_out" | grep -cF "▸ ---" || true)"
source_count="$(printf '%s\n' "$inject_out" | grep -c '^source: ' || true)"
if [ "$boundary_count" -ne "$source_count" ] || [ "$boundary_count" -lt 1 ]; then
  printf 'FAIL: capsule boundary markers (%s) != capsule count (%s)\n%s\n' \
    "$boundary_count" "$source_count" "$inject_out"
  exit 1
fi

echo "PASS: 12-flatten-safe-markers"
