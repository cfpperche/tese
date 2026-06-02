#!/usr/bin/env bash
# SessionStart hook: surface stale .agent0/memory/ entries inside a framed
# === MEMORY DECAY === block. Always exits 0.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
QUERY="$PROJECT_DIR/.agent0/tools/memory-query.sh"

if [ ! -x "$QUERY" ] || ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" 2>/dev/null; then
  exit 0
fi

AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$QUERY" decay --readout 2>/dev/null || true
exit 0
