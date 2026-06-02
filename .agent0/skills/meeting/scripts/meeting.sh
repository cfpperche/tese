#!/usr/bin/env bash
# meeting.sh — deterministic state machine for a /meeting transcript.
#
# Owns the YAML front-matter header of a meeting.md file: the participant
# roster, the round-robin rotation of model participants, the turn counter,
# the next legal speaker, and the synthesis status. The conversational turn
# *content* is authored by the active runtime; this script owns only the
# machine-readable state, so turn legality and single-writer-per-turn are
# mechanical and testable.
#
# Subcommands:
#   init        scaffold a meeting.md from the template and fill the header
#   state       print the parsed header fields as `key: value` lines
#   next        print next_speaker
#   check       exit 0 iff <speaker> is the legal next speaker (or human)
#   advance     bump turn_counter and move next_speaker along the rotation
#   append-turn append a turn section to the body, then advance
#
# Exit codes: 0 ok; 1 not-legal / not-found-as-expected; 2 usage / bad input;
#   3 unknown participant (not in roster).

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DEFAULT="$SELF_DIR/../templates/meeting.md.tmpl"

die()   { echo "meeting: $*" >&2; exit 2; }
errln() { echo "meeting: $*" >&2; }

# ── front-matter helpers ─────────────────────────────────────────────────────
# The front-matter is the region between the first '---' (line 1) and the next
# '---'. We only ever read/write single-line scalar fields there.

_fm_end_line() {
  # echo the line number of the closing '---' (search lines 2..200)
  awk 'NR>=2 && NR<=200 && /^---[[:space:]]*$/ {print NR; exit}' "$1"
}

get_field() {
  # get_field <file> <key>  → value (trailing ws + surrounding dquotes stripped)
  local file=$1 key=$2 end raw
  end="$(_fm_end_line "$file")"
  [ -n "$end" ] || { errln "no front-matter in $file"; return 2; }
  raw="$(sed -n "2,$((end-1))p" "$file" | sed -n "s|^${key}:[[:space:]]*\(.*\)\$|\1|p" | head -n1)"
  raw="${raw%"${raw##*[![:space:]]}"}"          # rtrim
  if [ "${raw#\"}" != "$raw" ] && [ "${raw%\"}" != "$raw" ]; then
    raw="${raw#\"}"; raw="${raw%\"}"            # strip surrounding dquotes
  fi
  printf '%s\n' "$raw"
}

set_field() {
  # set_field <file> <key> <value> — rewrite the scalar line within front-matter
  local file=$1 key=$2 val=$3 end tmp
  end="$(_fm_end_line "$file")"
  [ -n "$end" ] || { errln "no front-matter in $file"; return 2; }
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" -v end="$end" '
    NR>=2 && NR<end && $0 ~ "^" k ":" { print k ": " v; next }
    { print }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# csv_has <csv> <item> → 0 if item is a member of comma-separated list
csv_has() {
  local csv=$1 item=$2 x
  IFS=',' read -ra _a <<< "$csv"
  for x in "${_a[@]}"; do
    x="${x// /}"
    [ "$x" = "$item" ] && return 0
  done
  return 1
}

# csv_successor <csv> <item> → element after item, wrapping; empty if item absent
csv_successor() {
  local csv=$1 item=$2 i n
  IFS=',' read -ra _a <<< "$csv"
  n=${#_a[@]}
  for ((i=0; i<n; i++)); do
    local cur="${_a[i]// /}"
    if [ "$cur" = "$item" ]; then
      local nxt="${_a[(i+1)%n]// /}"
      printf '%s\n' "$nxt"
      return 0
    fi
  done
  return 1
}

# ── subcommands ──────────────────────────────────────────────────────────────

cmd_init() {
  local dir="" slug="" topic="" convener="" roster="" rotation="" next="" template="$TEMPLATE_DEFAULT" pblock=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)        dir=$2; shift 2;;
      --slug)       slug=$2; shift 2;;
      --topic)      topic=$2; shift 2;;
      --convener)   convener=$2; shift 2;;
      --roster)     roster=$2; shift 2;;
      --rotation)   rotation=$2; shift 2;;
      --next)       next=$2; shift 2;;
      --participants-block) pblock=$2; shift 2;;
      --template)   template=$2; shift 2;;
      *) die "init: unknown arg: $1";;
    esac
  done
  [ -n "$dir" ]      || die "init: --dir required"
  [ -n "$slug" ]     || die "init: --slug required"
  [ -n "$topic" ]    || die "init: --topic required"
  [ -n "$convener" ] || die "init: --convener required"
  [ -n "$roster" ]   || die "init: --roster required"
  [ -n "$rotation" ] || die "init: --rotation required"
  [ -f "$template" ] || die "init: template not found: $template"
  [ -n "$next" ] || next="$(printf '%s' "$rotation" | cut -d, -f1 | tr -d ' ')"
  [ -n "$pblock" ] || pblock="$(printf '%s' "$roster" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/^/- /')"

  mkdir -p "$dir"
  local out="$dir/meeting.md"
  [ -e "$out" ] && die "init: $out already exists"

  local created; created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Substitute placeholders. Use awk to keep multi-line participants block intact.
  awk -v topic="$topic" -v slug="$slug" -v created="$created" -v convener="$convener" \
      -v roster="$roster" -v rotation="$rotation" -v nextsp="$next" -v pblock="$pblock" '
    { gsub(/\{\{SLUG\}\}/, slug)
      gsub(/\{\{TOPIC\}\}/, topic)
      gsub(/\{\{CREATED\}\}/, created)
      gsub(/\{\{CONVENER\}\}/, convener)
      gsub(/\{\{ROSTER\}\}/, roster)
      gsub(/\{\{ROTATION\}\}/, rotation)
      gsub(/\{\{NEXT_SPEAKER\}\}/, nextsp)
      if ($0 ~ /\{\{PARTICIPANTS_BLOCK\}\}/) { print pblock; next }
      print }
  ' "$template" > "$out"

  echo "$out"
}

cmd_state() {
  local file=${1:-}
  [ -f "$file" ] || die "state: file not found: $file"
  local k
  for k in meeting topic created convener mode roster rotation turn_counter next_speaker synthesis; do
    printf '%s: %s\n' "$k" "$(get_field "$file" "$k")"
  done
}

cmd_next() {
  local file=${1:-}
  [ -f "$file" ] || die "next: file not found: $file"
  get_field "$file" next_speaker
}

cmd_check() {
  local file=${1:-} speaker=${2:-}
  [ -f "$file" ] || die "check: file not found: $file"
  [ -n "$speaker" ] || die "check: <speaker> required"
  local roster next
  roster="$(get_field "$file" roster)"
  next="$(get_field "$file" next_speaker)"
  if ! csv_has "$roster" "$speaker"; then
    errln "check: '$speaker' is not in the roster ($roster)"
    return 3
  fi
  # The human is the orchestrator and may interject at any point.
  if [ "$speaker" = "human" ]; then
    echo "legal: human may interject"
    return 0
  fi
  if [ "$speaker" = "$next" ]; then
    echo "legal: $speaker is the next speaker"
    return 0
  fi
  errln "check: not '$speaker' turn; next legal speaker is '$next'"
  return 1
}

cmd_advance() {
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "advance: file not found: $file"
  local speaker="" synthesis=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --speaker)   speaker=$2; shift 2;;
      --synthesis) synthesis=$2; shift 2;;
      *) die "advance: unknown arg: $1";;
    esac
  done
  if [ -n "$synthesis" ]; then
    case "$synthesis" in
      pending|written|accepted|rejected) set_field "$file" synthesis "$synthesis";;
      *) die "advance: --synthesis must be pending|written|accepted|rejected";;
    esac
  fi
  [ -n "$speaker" ] || { [ -n "$synthesis" ] && { cmd_state "$file"; return 0; }; die "advance: --speaker or --synthesis required"; }

  local roster rotation counter next
  roster="$(get_field "$file" roster)"
  rotation="$(get_field "$file" rotation)"
  csv_has "$roster" "$speaker" || { errln "advance: '$speaker' not in roster"; return 3; }

  counter="$(get_field "$file" turn_counter)"
  counter=$((counter + 1))
  set_field "$file" turn_counter "$counter"

  if csv_has "$rotation" "$speaker"; then
    # a model spoke → next_speaker is its rotation successor
    next="$(csv_successor "$rotation" "$speaker")"
    set_field "$file" next_speaker "$next"
  fi
  # a human turn does not consume a model's rotation slot → next_speaker unchanged
  cmd_state "$file"
}

cmd_append_turn() {
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "append-turn: file not found: $file"
  local speaker="" label="" body_file="" sources_file="" require_sources=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --speaker)         speaker=$2; shift 2;;
      --label)           label=$2; shift 2;;
      --body-file)       body_file=$2; shift 2;;
      --sources-file)    sources_file=$2; shift 2;;
      --require-sources) require_sources=1; shift;;
      *) die "append-turn: unknown arg: $1";;
    esac
  done
  [ -n "$speaker" ]   || die "append-turn: --speaker required"
  [ -f "$body_file" ] || die "append-turn: --body-file not found: $body_file"
  [ -n "$label" ] || label="$speaker"

  local roster; roster="$(get_field "$file" roster)"
  csv_has "$roster" "$speaker" || { errln "append-turn: '$speaker' not in roster ($roster)"; return 3; }

  # Validate sources BEFORE mutating anything (fail-before-write).
  if [ "$require_sources" -eq 1 ]; then
    if [ -n "$sources_file" ]; then
      [ -s "$sources_file" ] || { errln "append-turn: --require-sources but sources file empty/missing"; return 1; }
    elif ! grep -q '^Sources:' "$body_file"; then
      errln "append-turn: --require-sources but body has no 'Sources:' block"
      return 1
    fi
  fi

  local counter; counter="$(get_field "$file" turn_counter)"
  local n=$((counter + 1))

  # Build the turn block, then insert it into the Transcript section — i.e. just
  # before the '## Synthesis' header so the synthesis stays last. If there is no
  # Synthesis header, fall back to appending at EOF.
  local block tmp
  block="$(mktemp)"; tmp="$(mktemp)"
  {
    printf '\n### Turn %s — %s (%s)\n\n' "$n" "$label" "$speaker"
    cat "$body_file"
    if [ -n "$sources_file" ] && [ -f "$sources_file" ]; then
      printf '\nSources:\n'
      cat "$sources_file"
    fi
    printf '\n'
  } > "$block"

  awk -v bf="$block" '
    /^## Synthesis[[:space:]]*$/ && !done { while ((getline ln < bf) > 0) print ln; close(bf); done=1 }
    { print }
    END { if (!done) { while ((getline ln < bf) > 0) print ln; close(bf) } }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$block" "$tmp"

  # Advance only after the body is safely appended.
  cmd_advance "$file" --speaker "$speaker" >/dev/null
  echo "appended turn $n by $speaker"
}

# ── dispatch ─────────────────────────────────────────────────────────────────
main() {
  local sub=${1:-}
  [ -n "$sub" ] || die "usage: meeting.sh <init|state|next|check|advance|append-turn> ..."
  shift
  case "$sub" in
    init)        cmd_init "$@";;
    state)       cmd_state "$@";;
    next)        cmd_next "$@";;
    check)       cmd_check "$@";;
    advance)     cmd_advance "$@";;
    append-turn) cmd_append_turn "$@";;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
