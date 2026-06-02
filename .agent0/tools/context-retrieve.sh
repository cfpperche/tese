#!/usr/bin/env bash
# context-retrieve.sh — deterministic local retrieval for Agent0 context.

set -uo pipefail

PROJECT_DIR="${AGENT0_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
HELPER="$PROJECT_DIR/.agent0/tools/context-retrieve-helper.py"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'context-retrieve-advisory: python3 missing\n' >&2
  exit 3
fi
if [[ ! -x "$HELPER" ]]; then
  printf 'context-retrieve-advisory: helper not executable: %s\n' "$HELPER" >&2
  exit 3
fi

usage() {
  cat <<'USAGE' >&2
context-retrieve.sh search --query <text> [options]

Options:
  --format text|json|capsules|debug   Output shape (default: text)
  --limit N                           Max returned candidates (default: 5)
  --corpus LIST                       Comma list: rules,memory,specs,handoff (default: all)
  --exclude-source PATH               Omit a repo-relative source path; repeatable

No embeddings, vector DB, hosted service, or project-global cache are required.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

CMD="$1"; shift
case "$CMD" in
  search)
    AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" exec python3 "$HELPER" search "$@"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    printf 'context-retrieve.sh: unknown subcommand: %s\n' "$CMD" >&2
    usage
    exit 2
    ;;
esac
