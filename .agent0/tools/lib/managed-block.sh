#!/usr/bin/env bash
# Shared AGENT0 managed-block helpers.
#
# Sourced by sync-harness.sh and check-instruction-drift.sh so both tools use
# identical marker detection, region extraction, and region hashing semantics.
#
# All three region helpers take an optional marker NAME (default "AGENT0"), so
# the same machinery serves both the harness-index block (`AGENT0:BEGIN/END`)
# and the consumer project-core mirror (`AGENT0:PROJECT:BEGIN/END`). Existing
# callers that pass no name are byte-unaffected.

# Detect marker state in a file. Outputs: absent | paired | mismatched | nested-invalid
detect_marker_state() {
  local file="$1"
  local name="${2:-AGENT0}"
  local begin="<!-- ${name}:BEGIN -->"
  local end="<!-- ${name}:END -->"
  local begin_count end_count begin_line end_line
  if [ ! -f "$file" ]; then
    echo "absent"
    return
  fi
  begin_count="$(grep -Fxc "$begin" "$file" 2>/dev/null || true)"
  end_count="$(grep -Fxc "$end" "$file" 2>/dev/null || true)"
  [ -z "$begin_count" ] && begin_count=0
  [ -z "$end_count" ] && end_count=0

  if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    echo "absent"
    return
  fi

  if [ "$begin_count" -eq 0 ] || [ "$end_count" -eq 0 ]; then
    echo "mismatched"
    return
  fi

  if [ "$begin_count" -gt 1 ] || [ "$end_count" -gt 1 ]; then
    echo "nested-invalid"
    return
  fi

  begin_line="$(grep -Fxn "$begin" "$file" | head -1 | cut -d: -f1)"
  end_line="$(grep -Fxn "$end" "$file" | head -1 | cut -d: -f1)"
  if [ "$begin_line" -ge "$end_line" ]; then
    echo "nested-invalid"
    return
  fi
  echo "paired"
}

# Extract content between the BEGIN and END markers (exclusive).
_extract_region() {
  local file="$1"
  local name="${2:-AGENT0}"
  awk -v b="<!-- ${name}:BEGIN -->" -v e="<!-- ${name}:END -->" '
    $0 == e { in_region=0 }
    in_region { print }
    $0 == b { in_region=1 }
  ' "$file"
}

# sha256 of an in-memory region string. Consistent newline handling so the
# managed-block baseline record and the 3-way check compute the SAME digest.
_region_sha() {
  printf '%s\n' "$1" | sha256sum | awk '{print $1}'
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    detect_marker_state|_extract_region)
      "$cmd" "$@"
      ;;
    _region_sha)
      if [ "$#" -gt 0 ]; then
        _region_sha "$1"
      else
        _region_sha "$(cat)"
      fi
      ;;
    *)
      printf 'usage: managed-block.sh {detect_marker_state|_extract_region|_region_sha} [args]\n' >&2
      exit 2
      ;;
  esac
fi
