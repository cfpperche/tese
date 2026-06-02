#!/usr/bin/env bash
# Shared helpers for Agent0 project-memory hooks.

memory_project_dir() {
  local input="$1" cwd="" candidate="" root=""
  if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  fi
  if [ -n "${AGENT0_PROJECT_DIR:-}" ]; then
    candidate="$AGENT0_PROJECT_DIR"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    candidate="$CLAUDE_PROJECT_DIR"
  elif [ -n "$cwd" ]; then
    candidate="$cwd"
  else
    candidate="$(pwd)"
  fi

  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    root="$(cd "$candidate" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$root" ]; then
      printf '%s' "$root"
      return 0
    fi
  fi

  printf '%s' "$candidate"
}

memory_relpath() {
  local project="$1" path="$2"
  path="$(printf '%s' "$path" | tr -d '\r')"
  case "$path" in
    "$project"/*) path="${path#$project/}" ;;
  esac
  path="${path#./}"
  printf '%s\n' "$path"
}

memory_abspath() {
  local project="$1" path="$2"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$project" "$path" ;;
  esac
}

memory_patch_body() {
  local input="$1"
  printf '%s' "$input" | jq -r '
    if (.tool_input | type) == "string" then .tool_input
    else
      .tool_input.command
      // .tool_input.input
      // .tool_input.patch
      // .tool_input.content
      // ""
    end
  ' 2>/dev/null || true
}

memory_extract_paths() {
  local input="$1" project="$2" file_path body

  {
    file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
    if [ -n "$file_path" ]; then
      memory_relpath "$project" "$file_path"
    fi

    body="$(memory_patch_body "$input")"
    if [ -n "$body" ]; then
      printf '%s\n' "$body" | awk '
        /^\*\*\* Add File: / { sub(/^\*\*\* Add File: /, ""); print; next }
        /^\*\*\* Update File: / { sub(/^\*\*\* Update File: /, ""); print; next }
        /^\*\*\* Delete File: / { sub(/^\*\*\* Delete File: /, ""); print; next }
        /^\*\*\* Move to: / { sub(/^\*\*\* Move to: /, ""); print; next }
      ' | while IFS= read -r p; do
        [ -n "$p" ] && memory_relpath "$project" "$p"
      done
    fi
  } | awk 'NF && !seen[$0]++'
}

memory_is_index_path() {
  case "$1" in
    .agent0/memory/MEMORY.md|.claude/memory/MEMORY.md) return 0 ;;
    *) return 1 ;;
  esac
}

memory_is_entry_path() {
  case "$1" in
    .agent0/memory/*.md|.claude/memory/*.md)
      [ "$(basename "$1")" != "MEMORY.md" ]
      return $?
      ;;
    *) return 1 ;;
  esac
}

memory_actor() {
  local input="$1" tool_name agent_type
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  case "$tool_name" in
    apply_patch) printf 'Codex CLI'; return 0 ;;
  esac
  agent_type="$(printf '%s' "$input" | jq -r '.agent_type // .agent_id // ""' 2>/dev/null || true)"
  if [ -n "$agent_type" ]; then
    printf '%s' "$agent_type"
  else
    printf 'parent'
  fi
}

memory_runtime() {
  local input="$1" tool_name hook_event source
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  case "$tool_name" in
    apply_patch) printf 'codex-cli' ;;
    *)
      hook_event="$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || true)"
      source="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null || true)"
      if [ -z "${CLAUDE_PROJECT_DIR:-}" ] && { [ "$hook_event" = "SessionStart" ] || [ -n "$source" ] || [ -n "$input" ] || [ -n "${AGENT0_PROJECT_DIR:-}" ]; }; then
        printf 'codex-cli'
      else
        printf 'claude-code'
      fi
      ;;
  esac
}
