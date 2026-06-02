#!/usr/bin/env bash
# Static drift checks for the multi-runtime instruction entrypoints.

set -euo pipefail

ROOT="$(pwd)"
AGENT0_PATH=""
SKIP_SYNC_CHECK=0

usage() {
  cat <<'EOF'
check-instruction-drift.sh — verify CLAUDE.md / AGENTS.md entrypoint invariants

Usage:
  check-instruction-drift.sh [--root PATH] [--agent0-path PATH] [--skip-sync-check]

Exit codes:
  0  all checks passed
  1  drift or invalid entrypoint state detected
  2  usage error
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root=*) ROOT="${1#--root=}" ;;
    --root)
      shift
      ROOT="${1:-}"
      ;;
    --agent0-path=*) AGENT0_PATH="${1#--agent0-path=}" ;;
    --agent0-path)
      shift
      AGENT0_PATH="${1:-}"
      ;;
    --skip-sync-check) SKIP_SYNC_CHECK=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'check-instruction-drift: unknown arg: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)"
[ -n "$AGENT0_PATH" ] || AGENT0_PATH="$ROOT"
AGENT0_PATH="$(cd "$AGENT0_PATH" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$ROOT/.agent0/tools/lib/managed-block.sh"
if [ ! -f "$LIB" ]; then
  LIB="$SCRIPT_DIR/lib/managed-block.sh"
fi
if [ ! -f "$LIB" ]; then
  printf 'check-instruction-drift: missing managed-block helper library\n' >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$LIB"

failures=0

ok() {
  printf 'ok: %s\n' "$1"
}

fail() {
  printf 'drift: %s\n' "$1" >&2
  failures=$((failures + 1))
}

claude="$ROOT/CLAUDE.md"
agents="$ROOT/AGENTS.md"

if [ -f "$claude" ] && [ -f "$agents" ]; then
  ok "both root entrypoints exist"
else
  [ -f "$claude" ] || fail "missing CLAUDE.md"
  [ -f "$agents" ] || fail "missing AGENTS.md"
fi

if [ -f "$claude" ]; then
  claude_state="$(detect_marker_state "$claude")"
  [ "$claude_state" = "paired" ] && ok "CLAUDE.md markers paired and ordered" || fail "CLAUDE.md marker state is $claude_state"
fi
if [ -f "$agents" ]; then
  agents_state="$(detect_marker_state "$agents")"
  [ "$agents_state" = "paired" ] && ok "AGENTS.md markers paired and ordered" || fail "AGENTS.md marker state is $agents_state"
fi

if [ -f "$claude" ] && [ -f "$agents" ] &&
   [ "$(detect_marker_state "$claude")" = "paired" ] &&
   [ "$(detect_marker_state "$agents")" = "paired" ]; then
  claude_sha="$(_region_sha "$(_extract_region "$claude")")"
  agents_sha="$(_region_sha "$(_extract_region "$agents")")"
  if [ "$claude_sha" = "$agents_sha" ]; then
    ok "managed blocks are byte-identical"
  else
    fail "managed blocks differ"
  fi
fi

# spec 131 — when a consumer-owned project core exists, both entrypoints must
# carry an AGENT0:PROJECT region that matches it (the always-on mirror). No-op
# in Agent0 itself (no project-core.md) — the feature is opt-in per consumer.
project_core="$ROOT/.agent0/project-core.md"
if [ -f "$project_core" ]; then
  core_sha="$(_region_sha "$(cat "$project_core")")"
  for entry in "$claude" "$agents"; do
    ename="$(basename "$entry")"
    if [ -f "$entry" ] && [ "$(detect_marker_state "$entry" AGENT0:PROJECT)" = "paired" ]; then
      if [ "$(_region_sha "$(_extract_region "$entry" AGENT0:PROJECT)")" = "$core_sha" ]; then
        ok "$ename: PROJECT region matches .agent0/project-core.md"
      else
        fail "$ename: PROJECT region drifted from .agent0/project-core.md (run sync-harness --apply)"
      fi
    else
      fail "$ename: .agent0/project-core.md exists but its PROJECT region is missing/invalid (run sync-harness --apply)"
    fi
  done
fi

if [ "$SKIP_SYNC_CHECK" -eq 1 ]; then
  ok "sync-harness AGENTS.md baseline check skipped by flag"
else
  sync_tool="$ROOT/.agent0/tools/sync-harness.sh"
  if [ ! -f "$sync_tool" ]; then
    fail "missing sync-harness.sh for AGENTS.md baseline check"
  else
    sync_exit=0
    sync_out="$(bash "$sync_tool" --check --agent0-path="$AGENT0_PATH" "$ROOT" 2>&1)" || sync_exit=$?
    if ! printf '%s\n' "$sync_out" | grep -q 'AGENTS.md'; then
      fail "sync-harness --check did not inspect AGENTS.md"
    elif printf '%s\n' "$sync_out" | grep -qE '(^!!|^~|would copy|would remove).*AGENTS\.md|AGENTS\.md.*(customized|stale)'; then
      fail "sync-harness reports AGENTS.md drift"
    else
      ok "sync-harness checks AGENTS.md on the baseline-tracked path"
    fi
    if [ "$sync_exit" -ne 0 ] && ! printf '%s\n' "$sync_out" | grep -q 'AGENTS.md'; then
      fail "sync-harness --check exited $sync_exit before AGENTS.md could be verified"
    fi
  fi
fi

check_runtime_capabilities_registry() {
  local registry_rel=".agent0/context/rules/runtime-capabilities.md"
  local registry="$ROOT/$registry_rel"
  local term file label count before_failures

  # Source of truth: docs/specs/093-runtime-capability-registry/spec.md
  # § "Scenario: users can inspect one canonical capability matrix". If a
  # future spec promotes a 13th minimum row, update this array and that spec in
  # the same change. Extra rows in the registry are allowed.
  local minimum_set=(
    "instruction entrypoints"
    "session handoff"
    "SDD"
    "debate"
    "lifecycle hooks"
    "delegation/subagents"
    "MCP recipes"
    "image generation"
    "memory"
    "harness sync"
    "customization/sync surfaces"
  )

  before_failures="$failures"

  if [ -f "$registry" ]; then
    ok "runtime capability registry exists"
  else
    fail "registry file missing: $registry_rel"
  fi

  for file in "$claude" "$agents"; do
    if [ -f "$file" ] && [ "$(detect_marker_state "$file")" = "paired" ]; then
      if _extract_region "$file" | grep -qF "$registry_rel"; then
        ok "$(basename "$file"): managed block points to runtime capability registry"
      else
        fail "$(basename "$file"): managed block missing registry pointer"
      fi
    fi
  done

  if [ -f "$agents" ]; then
    if grep -qF '## Codex Capability Tiers' "$agents"; then
      fail "AGENTS.md: legacy '## Codex Capability Tiers' table still present"
    else
      ok "AGENTS.md legacy Codex Capability Tiers table absent"
    fi
  fi

  if [ -f "$registry" ]; then
    for term in native native-opt-in convention read-only planned unsupported; do
      if grep -qF "\`$term\`" "$registry"; then
        ok "registry vocabulary term present: $term"
      else
        fail "registry: vocabulary term \`$term\` missing"
      fi
    done

    for label in "${minimum_set[@]}"; do
      count="$(awk -F '|' -v label="$label" '
        NF > 2 {
          cell = $2
          gsub(/^[ \t]+|[ \t]+$/, "", cell)
          if (cell == label) count++
        }
        END { print count + 0 }
      ' "$registry")"
      if [ "$count" -eq 0 ]; then
        fail "registry: required row '$label' missing"
      elif [ "$count" -gt 1 ]; then
        fail "registry: required row '$label' duplicated"
      else
        ok "registry required row present: $label"
      fi
    done
  fi

  if [ "$failures" -eq "$before_failures" ]; then
    ok "runtime capability registry anchor checks passed"
  fi
}

check_runtime_capabilities_registry

if [ "$failures" -eq 0 ]; then
  exit 0
fi
exit 1
