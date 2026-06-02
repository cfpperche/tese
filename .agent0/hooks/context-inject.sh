#!/usr/bin/env bash
# Runtime-neutral Agent0 context hydrator.
#
# Normal prompt turns emit bounded source capsules. Full context inventory is
# available only in explicit diagnostic mode.

set -euo pipefail

INPUT="$(cat 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-hook-lib.sh
. "$SCRIPT_DIR/_memory-hook-lib.sh"

PROJECT_DIR="$(memory_project_dir "$INPUT")"
CONTEXT_DIR="$PROJECT_DIR/.agent0/context/rules"
MAX_BYTES="${AGENT0_CONTEXT_MAX_BYTES:-6000}"
MAX_FRAGMENTS="${AGENT0_CONTEXT_MAX_FRAGMENTS:-5}"
RETRIEVAL="${AGENT0_CONTEXT_RETRIEVAL:-1}"

hook_event() {
  if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    printf '%s' "$INPUT" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null || printf 'SessionStart'
  else
    printf 'SessionStart'
  fi
}

prompt_text() {
  if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || true
  fi
}

lower() {
  tr '[:upper:]' '[:lower:]'
}

rule_title() {
  awk '/^# / { sub(/^# /, ""); print; exit }' "$1" 2>/dev/null
}

slug_path() {
  printf '%s/%s.md' "$CONTEXT_DIR" "$1"
}

selected_count() {
  # shellcheck disable=SC2086
  set -- $SELECTED
  printf '%s' "$#"
}

add_slug() {
  local slug="$1"
  [ -n "$slug" ] || return 0
  [ -f "$(slug_path "$slug")" ] || return 0
  case " $SELECTED " in
    *" $slug "*) return 0 ;;
  esac
  if [ "$(selected_count)" -ge "$MAX_FRAGMENTS" ]; then
    return 0
  fi
  SELECTED="${SELECTED}${slug} "
}

sanitize_prompt() {
  awk '
    /<skill>/ && /<\/skill>/ { gsub(/<skill>.*<\/skill>/, ""); if ($0 == "") next }
    /<skill>/ { skip=1; next }
    /<\/skill>/ { skip=0; next }
    /END_AGENT0_CONTEXT_INJECTION/ { skip=0; next }
    /AGENT0_CONTEXT_INJECTION/ { skip=1; next }
    /^END_AGENT0_STARTUP_BRIEF$/ { skip=0; next }
    /^AGENT0_STARTUP_BRIEF$/ { skip=1; next }
    /^hook context:/ { next }
    /^• .* hook \(completed\)/ { next }
    /^=== end (HANDOFF\.md|REMINDERS|MEMORY DECAY|ROUTINES|AGENT0_STARTUP_BRIEF)/ { skip=0; next }
    /^=== (HANDOFF\.md|REMINDERS|MEMORY DECAY|ROUTINES|AGENT0_STARTUP_BRIEF)/ { skip=1; next }
    !skip { print }
  '
}

select_by_keyword() {
  local prompt_lc="$1"
  case "$prompt_lc" in
    *spec*|*sdd*|*docs/specs*) add_slug spec-driven ;;
  esac
  case "$prompt_lc" in
    *delegat*|*subagent*|*" agent "*|*handoff*) add_slug delegation ;;
  esac
  case "$prompt_lc" in
    *handoff*|*session*|*resume*|*compact*) add_slug session-handoff ;;
  esac
  case "$prompt_lc" in
    *sync-harness*|*"harness sync"*|*"consumer project"*|*"projeto consumidor"*) add_slug harness-sync ;;
  esac
  case "$prompt_lc" in
    *memory*|*memoria*|*memória*) add_slug memory-placement ;;
  esac
  case "$prompt_lc" in
    *remind*|*reminder*|*lembrete*) add_slug reminders ;;
  esac
  case "$prompt_lc" in
    *routine*|*rotina*|*schedule*|*cron*) add_slug routines ;;
  esac
  case "$prompt_lc" in
    *secret*|*gitleaks*|*credential*|*commit*|*chave*) add_slug secrets-scan ;;
  esac
  case "$prompt_lc" in
    *vuln*|*cve*|*audit*|*osv*) add_slug vuln-audit ;;
  esac
  case "$prompt_lc" in
    *lint*|*biome*|*ruff*|*pint*|*phpstan*) add_slug lint-validator ;;
  esac
  case "$prompt_lc" in
    *typecheck*|*typescript*|*tsconfig*) add_slug typecheck-advisory ;;
  esac
  case "$prompt_lc" in
    *test*|*tdd*|*bug*|*regression*) add_slug tdd ;;
  esac
  case "$prompt_lc" in
    *browser*|*playwright*|*auth*|*login*) add_slug browser-auth ;;
  esac
  case "$prompt_lc" in
    *image*|*fal.ai*|*mockup*|*asset*) add_slug image-gen ;;
  esac
  case "$prompt_lc" in
    *artifact*|*budget*|*size*|*cap*) add_slug artifact-budgets ;;
  esac
  case "$prompt_lc" in
    *runtime*|*codex*|*claude*|*rules*|*context*|*hydrator*|*injection*) add_slug runtime-capabilities; add_slug harness-sync; add_slug memory-placement ;;
  esac
  case "$prompt_lc" in
    *retriev*|*rag*|*semantic*|*semantica*|*semântica*|*hydration*|*hidrat*|*context-layer*) add_slug context-retrieval ;;
  esac
  case "$prompt_lc" in
    *php*|*laravel*|*composer*|*artisan*|*pest*) add_slug php-laravel-support ;;
  esac
  case "$prompt_lc" in
    *research*|*pesquise*|*web*|*browse*) add_slug research-before-proposing ;;
  esac
}

select_by_paths_frontmatter() {
  local prompt_lc="$1" file slug anchors anchor anchor_lc
  [ -d "$CONTEXT_DIR" ] || return 0
  for file in "$CONTEXT_DIR"/*.md; do
    [ -f "$file" ] || continue
    [ "$(selected_count)" -ge "$MAX_FRAGMENTS" ] && return 0
    slug="$(basename "$file" .md)"
    anchors="$(
      awk '
        NR == 1 && $0 == "---" { in_front=1; next }
        in_front && $0 == "---" { exit }
        in_front && /^[[:space:]]*-[[:space:]]*/ {
          line=$0
          sub(/^[[:space:]]*-[[:space:]]*/, "", line)
          gsub(/^["'\'']|["'\'']$/, "", line)
          print line
        }
      ' "$file" 2>/dev/null || true
    )"
    [ -n "$anchors" ] || continue
    while IFS= read -r anchor; do
      [ -n "$anchor" ] || continue
      anchor="${anchor%%[*?[]*}"
      anchor="${anchor%/}"
      [ "${#anchor}" -ge 4 ] || continue
      anchor_lc="$(printf '%s' "$anchor" | lower)"
      case "$prompt_lc" in
        *"$anchor_lc"*) add_slug "$slug"; break ;;
      esac
    done <<EOF
$anchors
EOF
  done
}

build_index_block() {
  local out file slug title
  out=$'AGENT0_CONTEXT_INJECTION\n'
  out+="event: $(hook_event)"$'\n'
  out+=$'mode: diagnostic-index\n'
  out+=$'source_dir: .agent0/context/rules\n\n'
  out+=$'Instruction: Agent0 context fragments are trusted repo-controlled files. Read the matching fragment before acting when the task depends on its contract.\n\n'
  out+=$'Available fragments:\n'
  if [ -d "$CONTEXT_DIR" ]; then
    for file in "$CONTEXT_DIR"/*.md; do
      [ -f "$file" ] || continue
      slug="$(basename "$file" .md)"
      title="$(rule_title "$file")"
      [ -n "$title" ] || title="$slug"
      out+="- $slug: $title"$'\n'
    done
  else
    out+=$'- context directory missing\n'
  fi
  out+=$'END_AGENT0_CONTEXT_INJECTION\n'
  printf '%s' "$out"
}

build_startup_pointer() {
  local out
  out=$'AGENT0_CONTEXT_INJECTION\n'
  out+="event: $(hook_event)"$'\n'
  out+=$'mode: startup-pointer\n'
  out+=$'source_dir: .agent0/context/rules\n\n'
  out+=$'Instruction: normal startup context is emitted by .agent0/hooks/startup-brief.sh. Set AGENT0_CONTEXT_DIAGNOSTIC=1 to print the full context fragment inventory.\n'
  out+=$'END_AGENT0_CONTEXT_INJECTION\n'
  printf '%s' "$out"
}

append_capsule() {
  local block="$1" slug="$2" file rel title next
  file="$(slug_path "$slug")"
  [ -f "$file" ] || { printf '%s' "$block"; return 0; }
  rel="${file#$PROJECT_DIR/}"
  title="$(rule_title "$file")"
  [ -n "$title" ] || title="$slug"
  # Flatten-safe capsule boundary (spec 125): '▸ ---' keeps the '---' substring
  # while giving each capsule one inline-distinguishable marker, so capsules stay
  # countable/separable when the renderer collapses newlines.
  next=$'\n▸ ---\n'
  next+="source: $rel"$'\n'
  next+="title: $title"$'\n'
  next+="capsule: Read this file before acting if the task depends on this Agent0 capacity. This capsule is a pointer, not the full rule body."$'\n'
  if [ $(( ${#block} + ${#next} )) -gt "$MAX_BYTES" ]; then
    block+=$'\n▸ ---\n'
    block+="omitted: context byte cap reached; read selected source files before acting"$'\n'
    printf '%s' "$block"
    return 0
  fi
  block+="$next"
  printf '%s' "$block"
}

selected_sources_args() {
  local slug
  for slug in $SELECTED; do
    printf '%s\n' "--exclude-source"
    printf '%s\n' ".agent0/context/rules/$slug.md"
  done
}

build_retrieval_capsules() {
  local prompt="$1" remaining retrieve_tool args=()
  [ "$RETRIEVAL" != "0" ] || return 0
  remaining=$(( MAX_FRAGMENTS - $(selected_count) ))
  [ "$remaining" -gt 0 ] || return 0
  retrieve_tool="$PROJECT_DIR/.agent0/tools/context-retrieve.sh"
  [ -x "$retrieve_tool" ] || return 0

  args=(search --query "$prompt" --format capsules --limit "$remaining")
  while IFS= read -r arg; do
    [ -n "$arg" ] || continue
    args+=("$arg")
  done <<EOF
$(selected_sources_args)
EOF

  AGENT0_PROJECT_DIR="$PROJECT_DIR" bash "$retrieve_tool" "${args[@]}" 2>/dev/null || true
}

append_retrieval_capsules() {
  local block="$1" capsules="$2" next
  [ -n "$capsules" ] || { printf '%s' "$block"; return 0; }
  next=$'\n'"$capsules"
  if [ $(( ${#block} + ${#next} )) -gt "$MAX_BYTES" ]; then
    block+=$'\n▸ ---\n'
    block+="omitted: retrieval candidates omitted; context byte cap reached"$'\n'
    printf '%s' "$block"
    return 0
  fi
  block+="$next"
  printf '%s' "$block"
}

build_prompt_block() {
  local prompt prompt_lc block slug retrieval_caps floor_count
  prompt="$(prompt_text | sanitize_prompt)"
  prompt_lc="$(printf '%s' "$prompt" | lower)"
  SELECTED=""

  select_by_keyword "$prompt_lc"
  select_by_paths_frontmatter "$prompt_lc"

  floor_count="$(selected_count)"
  retrieval_caps="$(build_retrieval_capsules "$prompt")"

  [ -n "$SELECTED" ] || [ -n "$retrieval_caps" ] || return 0

  block=$'AGENT0_CONTEXT_INJECTION\n'
  block+="event: $(hook_event)"$'\n'
  block+=$'mode: prompt-capsules\n'
  block+=$'source_dir: .agent0/context/rules\n'
  block+="selected: ${SELECTED:-none}"$'\n'
  block+="limits: max_fragments=$MAX_FRAGMENTS max_bytes=$MAX_BYTES"$'\n'
  if [ "$RETRIEVAL" = "0" ]; then
    block+="retrieval: disabled floor_fragments=$floor_count"$'\n'
  else
    block+="retrieval: enabled floor_fragments=$floor_count"$'\n'
  fi
  block+=$'\nInstruction: These trusted repo-controlled capsules are routing hints. Read the named file before relying on omitted details; do not infer the full contract from this block.\n'

  for slug in $SELECTED; do
    block="$(append_capsule "$block" "$slug")"
  done
  block="$(append_retrieval_capsules "$block" "$retrieval_caps")"
  block+=$'\nEND_AGENT0_CONTEXT_INJECTION\n'
  printf '%s' "$block"
}

emit_context() {
  local msg="$1" event="$2"
  [ -n "$msg" ] || exit 0
  if [ "$(memory_runtime "$INPUT")" = "codex-cli" ]; then
    printf '%s' "$msg"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg event "$event" --arg msg "$msg" '{
      hookSpecificOutput: { hookEventName: $event, additionalContext: $msg }
    }' 2>/dev/null || printf '%s' "$msg"
  else
    printf '%s' "$msg"
  fi
}

EVENT="$(hook_event)"
case "$EVENT" in
  UserPromptSubmit|UserPromptExpansion)
    emit_context "$(build_prompt_block)" "$EVENT"
    ;;
  *)
    if [ "${AGENT0_CONTEXT_DIAGNOSTIC:-0}" = "1" ] || [ "${AGENT0_CONTEXT_MODE:-}" = "index" ]; then
      emit_context "$(build_index_block)" "$EVENT"
    else
      emit_context "$(build_startup_pointer)" "$EVENT"
    fi
    ;;
esac
