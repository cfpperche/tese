#!/usr/bin/env bash
# memory-query.sh — thin dispatcher to memory-query-helper.py.
#
# Subcommands:
#   search <pattern>
#   list [--type=T] [--stale=Nd|Nw|Nm]
#   confirm <name1> [<name2> ...]
#   decay [--readout]
#
# Mutation paths require PyYAML; refuses to operate if absent (no degraded
# query path because filtering frontmatter without YAML parsing would be
# fragile). See .agent0/context/rules/memory-placement.md § Cap / query / decay.

set -uo pipefail

PROJECT_DIR="${AGENT0_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
HELPER="$PROJECT_DIR/.agent0/tools/memory-query-helper.py"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'memory-query-advisory: python3 missing\n' >&2
  exit 3
fi
if ! python3 -c "import yaml" 2>/dev/null; then
  printf 'memory-query-advisory: PyYAML missing (pip install pyyaml)\n' >&2
  exit 3
fi
if [[ ! -x "$HELPER" ]]; then
  printf 'memory-query-advisory: helper not executable: %s\n' "$HELPER" >&2
  exit 3
fi

usage() {
  cat <<'USAGE' >&2
memory-query.sh <subcommand> [args]
  search <pattern>                       case-insensitive grep across entries
  list [--type=T] [--stale=Nd|Nw|Nm]     filtered index
  confirm <name1> [<name2> ...]          bump last_accessed + confirmed_count
  decay [--readout]                      staleness readout (framed when --readout)
USAGE
}

if [[ $# -lt 1 ]]; then
  usage; exit 2
fi

CMD="$1"; shift
case "$CMD" in
  search|list|confirm|decay)
    AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" exec python3 "$HELPER" "$CMD" "$@"
    ;;
  -h|--help|help)
    usage; exit 0
    ;;
  *)
    printf 'memory-query.sh: unknown subcommand: %s\n' "$CMD" >&2
    usage; exit 2
    ;;
esac
