#!/usr/bin/env bash
# Runtime-neutral project-memory maintenance primitives.
#
# Subcommands:
#   validate <entry.md>      advisory-only frontmatter schema check
#   finalize [entry.md ...]  validate provided entries, then regenerate MEMORY.md

set -uo pipefail

PROJECT_DIR="${AGENT0_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PROJECTOR="$PROJECT_DIR/.agent0/tools/memory-project.sh"
SCHEMA_REF=".agent0/context/rules/memory-placement.md § Frontmatter schema"

usage() {
  cat <<'USAGE' >&2
memory-maintain.sh <subcommand> [args]
  validate <entry.md>          advisory-only frontmatter schema check
  finalize [entry.md ...]      validate entries, then regenerate MEMORY.md
USAGE
}

relpath() {
  local path="$1"
  case "$path" in
    "$PROJECT_DIR"/*) path="${path#$PROJECT_DIR/}" ;;
  esac
  path="${path#./}"
  printf '%s' "$path"
}

emit_frontmatter_advisory() {
  local rel="$1" msg="$2"
  printf 'memory-frontmatter-advisory: %s: %s — see %s\n' "$rel" "$msg" "$SCHEMA_REF" >&2
}

validate_entry() {
  local file="$1"
  local rel first_line second_fence_line fm_body line key
  local has_name=0 has_desc=0 has_type=0 in_metadata=0
  local unknown_top="" unknown_nested=""

  [ -n "$file" ] || return 0
  rel="$(relpath "$file")"

  case "$rel" in
    .agent0/memory/*.md|.claude/memory/*.md) ;;
    *) return 0 ;;
  esac
  [ "$(basename "$rel")" = "MEMORY.md" ] && return 0
  [ -r "$file" ] || return 0

  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    emit_frontmatter_advisory "$rel" "no frontmatter block (expected '---' at line 1)"
    return 0
  fi

  second_fence_line="$(awk 'NR>1 && /^---$/{print NR; exit}' "$file" 2>/dev/null || true)"
  if [ -z "$second_fence_line" ]; then
    emit_frontmatter_advisory "$rel" "frontmatter unparseable: missing closing '---'"
    return 0
  fi

  fm_body="$(awk 'NR==1{next} /^---$/{exit} {print}' "$file" 2>/dev/null || true)"

  while IFS= read -r line; do
    case "$line" in
      ""|\#*) continue ;;
    esac

    if printf '%s' "$line" | grep -qE '^[a-z_][a-z0-9_]*:'; then
      key="$(printf '%s' "$line" | sed -E 's/^([a-z_][a-z0-9_]*):.*/\1/')"
      case "$key" in
        name) has_name=1; in_metadata=0 ;;
        description) has_desc=1; in_metadata=0 ;;
        metadata) in_metadata=1 ;;
        *) unknown_top="$unknown_top $key"; in_metadata=0 ;;
      esac
      continue
    fi

    if [ "$in_metadata" = "1" ] && printf '%s' "$line" | grep -qE '^  [a-z_][a-z0-9_]*:'; then
      key="$(printf '%s' "$line" | sed -E 's/^  ([a-z_][a-z0-9_]*):.*/\1/')"
      case "$key" in
        type) has_type=1 ;;
        created_at|last_accessed|confirmed_count) ;;
        *) unknown_nested="$unknown_nested metadata.$key" ;;
      esac
      continue
    fi
  done <<EOF
$fm_body
EOF

  [ "$has_name" = "0" ] && emit_frontmatter_advisory "$rel" "missing required field 'name'"
  [ "$has_desc" = "0" ] && emit_frontmatter_advisory "$rel" "missing required field 'description'"
  [ "$has_type" = "0" ] && emit_frontmatter_advisory "$rel" "missing required field 'metadata.type'"

  for key in $unknown_top; do
    emit_frontmatter_advisory "$rel" "unknown field '$key' — typo guard, allowed top-level: name, description, metadata"
  done
  for key in $unknown_nested; do
    emit_frontmatter_advisory "$rel" "unknown field '$key' — typo guard, allowed metadata.*: type, created_at, last_accessed, confirmed_count"
  done

  return 0
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 2; }
shift

case "$cmd" in
  validate)
    [ $# -eq 1 ] || { usage; exit 2; }
    validate_entry "$1"
    exit 0
    ;;
  finalize)
    for entry in "$@"; do
      validate_entry "$entry"
    done
    if [ ! -x "$PROJECTOR" ]; then
      printf 'memory-maintain: projector not executable: %s\n' "$PROJECTOR" >&2
      exit 3
    fi
    if ! AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECTOR"; then
      printf 'memory-maintain: projection failed; fix the advisory above and retry\n' >&2
      exit 3
    fi
    printf 'memory-maintain: finalized project memory; re-stage .agent0/memory/MEMORY.md if committing\n' >&2
    exit 0
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    printf 'memory-maintain: unknown subcommand: %s\n' "$cmd" >&2
    usage
    exit 2
    ;;
esac
