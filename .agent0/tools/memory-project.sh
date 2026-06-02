#!/usr/bin/env bash
# .agent0/tools/memory-project.sh
# Regenerates .agent0/memory/MEMORY.md from the current entries' YAML frontmatter.
# Reads `name` + `description` per the 082 schema via the Python helper (which
# correctly handles folded/multi-line YAML strings) and emits one bullet per
# entry sorted by filename slug.
#
# Idempotent + deterministic: re-running on an unchanged corpus produces
# byte-identical output. LC_ALL=C locks sort order cross-machine.
#
# Also checks each projected line length against
# `.agent0/memory.config.json` § cap.max_line_chars (default 250) and emits
# `memory-cap-advisory:` to stderr for overflows. The bullet is still
# emitted (no truncation) — the cap is a writing discipline, not a
# silent edit. Exit 0 regardless of advisories.
#
# Schema: .agent0/context/rules/memory-placement.md § Frontmatter schema

set -uo pipefail
LC_ALL=C

PROJECT_DIR="${AGENT0_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
MEMORY_DIR="$PROJECT_DIR/.agent0/memory"
INDEX_PATH="$MEMORY_DIR/MEMORY.md"
CONFIG_PATH="$PROJECT_DIR/.agent0/memory.config.json"
HELPER="$PROJECT_DIR/.agent0/tools/memory-query-helper.py"
OUT_PATH="$INDEX_PATH"

while [ $# -gt 0 ]; do
  case "$1" in
    --out=*)
      OUT_PATH="${1#--out=}"
      ;;
    --out)
      shift
      OUT_PATH="${1:-}"
      ;;
    --dry-run)
      # Backward-compatible no-op. Use --out to choose the projection target.
      ;;
    -h|--help)
      cat <<'USAGE'
memory-project.sh [--out PATH] [--dry-run]

Regenerate the project-memory index from .agent0/memory/*.md frontmatter.
By default writes .agent0/memory/MEMORY.md. With --out, writes the projection
to PATH instead; useful for non-mutating checks.
USAGE
      exit 0
      ;;
    *)
      printf 'memory-project: unknown arg: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ ! -d "$MEMORY_DIR" ]; then
  printf 'memory-project: %s does not exist\n' "$MEMORY_DIR" >&2
  exit 1
fi

# Read cap.max_line_chars from config (default 250 if config absent/malformed).
CAP_DEFAULT=250
CAP_MAX="$CAP_DEFAULT"
if [ -r "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
  v="$(jq -r '.cap.max_line_chars // empty' "$CONFIG_PATH" 2>/dev/null || true)"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    CAP_MAX="$v"
  fi
fi

# Verify helper available; fall back to a degraded awk path otherwise (for
# bootstrapping consumer projects that haven't installed PyYAML yet).
USE_HELPER=0
if [ -x "$HELPER" ] && command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  USE_HELPER=1
fi

tmp="$(mktemp 2>/dev/null || mktemp -t memory-project)"
trap 'rm -f "$tmp"' EXIT

if [ "$USE_HELPER" -eq 1 ]; then
  # Helper-canonical path: handles folded YAML correctly.
  AGENT0_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PROJECT_DIR="$PROJECT_DIR" python3 "$HELPER" project-entries | while IFS=$'\t' read -r slug name description; do
    bullet="$(printf -- '- [%s](%s.md) — %s' "$name" "$slug" "$description")"
    blen=${#bullet}
    if [ "$blen" -gt "$CAP_MAX" ]; then
      printf 'memory-cap-advisory: %s.md projects to %d chars (cap %d) — shorten description\n' "$slug" "$blen" "$CAP_MAX" >&2
    fi
    printf '%s\t%s\n' "$slug" "$bullet" >> "$tmp"
  done
else
  # Degraded path: awk reads only first line of frontmatter values. Works
  # when descriptions fit on one YAML line. Emits a one-time advisory.
  printf 'memory-project-advisory: python3+yaml unavailable; degraded awk projection (folded YAML descriptions will truncate)\n' >&2
  strip_quotes() {
    local v="$1"
    case "$v" in
      \"*\") v="${v#\"}"; v="${v%\"}" ;;
      \'*\') v="${v#\'}"; v="${v%\'}" ;;
    esac
    printf '%s' "$v"
  }
  for file in "$MEMORY_DIR"/*.md; do
    [ -e "$file" ] || continue
    base="$(basename "$file")"
    [ "$base" = "MEMORY.md" ] && continue
    slug="${base%.md}"
    fm="$(awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit} in_fm' "$file" 2>/dev/null || true)"
    [ -z "$fm" ] && continue
    name="$(printf '%s\n' "$fm" | awk '/^name:/{sub(/^name:[[:space:]]*/, ""); print; exit}')"
    description="$(printf '%s\n' "$fm" | awk '/^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}')"
    name="$(strip_quotes "$name")"
    description="$(strip_quotes "$description")"
    [ -z "$name" ] && name="$slug"
    [ -z "$description" ] && continue
    bullet="$(printf -- '- [%s](%s.md) — %s' "$name" "$slug" "$description")"
    blen=${#bullet}
    if [ "$blen" -gt "$CAP_MAX" ]; then
      printf 'memory-cap-advisory: %s projects to %d chars (cap %d) — shorten description\n' "$base" "$blen" "$CAP_MAX" >&2
    fi
    printf '%s\t%s\n' "$slug" "$bullet" >> "$tmp"
  done
fi

mkdir -p "$(dirname "$OUT_PATH")" 2>/dev/null || true
sort -t "$(printf '\t')" -k1,1 "$tmp" | cut -f2- > "$OUT_PATH"

count="$(wc -l < "$OUT_PATH" | tr -d ' ')"
printf 'memory-project: regenerated %s with %s entries (cap %d)\n' "$OUT_PATH" "$count" "$CAP_MAX" >&2
