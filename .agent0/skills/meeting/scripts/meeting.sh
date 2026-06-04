#!/usr/bin/env bash
# meeting.sh — deterministic state machine for a /meeting transcript.
#
# Owns the YAML front-matter header of a meeting.md file: the participant
# roster, the fallback speaker order (`rotation`), the turn counter, the
# derived default next speaker, and the synthesis status. The conversational
# turn *content* is authored by the active runtime; this script owns only the
# machine-readable state, so single-writer-per-turn and speaker selection are
# mechanical and testable.
#
# Speaker selection (spec 140) is context-driven, not round-robin: a turn body
# MAY end with an explicit trailing `Next: <roster-id>` directive (exact match
# only, never NLP). That marker becomes `next_speaker`. `next_speaker` is a
# derived, reported default — NOT enforced legality. `rotation` is retained
# only as a deterministic fallback order when no default is resolvable.
#
# Subcommands:
#   init            scaffold a meeting.md from the template and fill the header
#   state           print the parsed header fields as `key: value` lines
#   next            print next_speaker
#   check           exit 0 iff <speaker> is in the roster (membership only)
#   resolve-speaker print the resolved default speaker (precedence-ordered)
#   advance         bump turn_counter; set next_speaker from --next if given
#   append-turn     append a turn section to the body, then advance
#
# Exit codes: 0 ok; 1 not-found-as-expected / sources-missing; 2 usage / bad
#   input; 3 unknown participant or bad address directive (not in roster).

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

# csv_first <csv> → first element, whitespace-stripped; empty if csv empty
csv_first() {
  printf '%s' "$1" | cut -d, -f1 | tr -d ' '
}

# _marker_from_body <body_file> → if the LAST non-empty line is an explicit
# `Next: <token>` address directive, echo the trimmed token (which may be
# empty, multi-word, or a non-roster id — the CALLER validates) and return 0.
# Any final line NOT beginning with `Next:` is "no marker" → return 1.
# Parsing is exact-shape only; prose `@mentions` or the word "Next" mid-line
# never count.
_marker_from_body() {
  local body=$1 last tok
  last="$(awk 'NF{l=$0} END{print l}' "$body")"
  case "$last" in
    Next:*)
      tok="${last#Next:}"
      tok="${tok#"${tok%%[![:space:]]*}"}"   # ltrim
      tok="${tok%"${tok##*[![:space:]]}"}"   # rtrim
      printf '%s\n' "$tok"
      return 0;;
    *) return 1;;
  esac
}

# compute_friction <file> → echoes "<total_model_turns> <max_consecutive_model> <current_trailing_streak>"
# Reads the ordered turn-header ids from the body. A "model turn" is any turn
# whose speaker id is not `human`. The friction signal is the longest run of
# consecutive model turns with no human turn between them — the mechanical half
# of the demand test (see .agent0/context/rules/meeting.md § Demand test).
compute_friction() {
  local file=$1 id max=0 cur=0 total=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if [ "$id" = "human" ]; then
      cur=0
    else
      total=$((total + 1)); cur=$((cur + 1)); [ "$cur" -gt "$max" ] && max=$cur
    fi
  done < <(sed -n -E 's/^### Turn [0-9]+ — .* \(([A-Za-z0-9_-]+)\)[[:space:]]*$/\1/p' "$file")
  printf '%s %s %s\n' "$total" "$max" "$cur"
}

# ── subcommands ──────────────────────────────────────────────────────────────

cmd_init() {
  local dir="" slug="" topic="" convener="" roster="" rotation="" next="" template="$TEMPLATE_DEFAULT" pblock="" tier="light"
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)        dir=$2; shift 2;;
      --slug)       slug=$2; shift 2;;
      --topic)      topic=$2; shift 2;;
      --convener)   convener=$2; shift 2;;
      --roster)     roster=$2; shift 2;;
      --rotation)   rotation=$2; shift 2;;
      --next)       next=$2; shift 2;;
      --tier)       tier=$2; shift 2;;
      --participants-block) pblock=$2; shift 2;;
      --template)   template=$2; shift 2;;
      *) die "init: unknown arg: $1";;
    esac
  done
  case "$tier" in light|decision-grade) ;; *) die "init: --tier must be light|decision-grade";; esac
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
      -v roster="$roster" -v rotation="$rotation" -v nextsp="$next" -v pblock="$pblock" -v tier="$tier" '
    { gsub(/\{\{SLUG\}\}/, slug)
      gsub(/\{\{TOPIC\}\}/, topic)
      gsub(/\{\{CREATED\}\}/, created)
      gsub(/\{\{CONVENER\}\}/, convener)
      gsub(/\{\{ROSTER\}\}/, roster)
      gsub(/\{\{ROTATION\}\}/, rotation)
      gsub(/\{\{NEXT_SPEAKER\}\}/, nextsp)
      gsub(/\{\{TIER\}\}/, tier)
      if ($0 ~ /\{\{PARTICIPANTS_BLOCK\}\}/) { print pblock; next }
      print }
  ' "$template" > "$out"

  echo "$out"
}

cmd_state() {
  local file=${1:-}
  [ -f "$file" ] || die "state: file not found: $file"
  local k
  for k in meeting topic created convener mode roster rotation tier blind_phase turn_counter next_speaker synthesis; do
    printf '%s: %s\n' "$k" "$(get_field "$file" "$k")"
  done
  # Derived autopilot-friction signal (computed from the body, not the header).
  local total maxc streak
  read -r total maxc streak < <(compute_friction "$file")
  printf 'model_turns: %s\n' "$total"
  printf 'max_consecutive_model_turns: %s\n' "$maxc"
  printf 'current_model_streak: %s\n' "$streak"
}

cmd_friction() {
  local file=${1:-}
  [ -f "$file" ] || die "friction: file not found: $file"
  local total maxc streak threshold=4
  read -r total maxc streak < <(compute_friction "$file")
  printf 'model_turns: %s\n' "$total"
  printf 'max_consecutive_model_turns: %s\n' "$maxc"
  printf 'current_model_streak: %s\n' "$streak"
  if [ "$maxc" -ge "$threshold" ]; then
    printf 'demand-test (mechanical half): MET — %s consecutive model turns without human intervention (>= %s). A qualifying meeting also needs an explicit human "continue unattended" note.\n' "$maxc" "$threshold"
  else
    printf 'demand-test (mechanical half): not met — max %s consecutive model turns (< %s)\n' "$maxc" "$threshold"
  fi
}

cmd_next() {
  local file=${1:-}
  [ -f "$file" ] || die "next: file not found: $file"
  get_field "$file" next_speaker
}

cmd_check() {
  # Spec 140: membership-only. Speaker selection is context-driven (the
  # addressing marker / --speaker decides who speaks), so `check` no longer
  # enforces a round-robin "next legal speaker" — it only confirms the id is
  # a known participant.
  local file=${1:-} speaker=${2:-}
  [ -f "$file" ] || die "check: file not found: $file"
  [ -n "$speaker" ] || die "check: <speaker> required"
  local roster
  roster="$(get_field "$file" roster)"
  if ! csv_has "$roster" "$speaker"; then
    errln "check: '$speaker' is not in the roster ($roster)"
    return 3
  fi
  echo "ok: $speaker is in the roster"
  return 0
}

cmd_resolve_speaker() {
  # Print the resolved default speaker following the precedence:
  #   --speaker <id>  >  next_speaker header  >  first model in rotation  >  convener
  # Every source is roster-validated; a stale/non-roster value is skipped.
  # An explicit --speaker that is not in the roster is an error (exit 3).
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "resolve-speaker: file not found: $file"
  local want=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --speaker) want=$2; shift 2;;
      *) die "resolve-speaker: unknown arg: $1";;
    esac
  done
  local roster; roster="$(get_field "$file" roster)"
  if [ -n "$want" ]; then
    csv_has "$roster" "$want" || { errln "resolve-speaker: '$want' is not in the roster ($roster)"; return 3; }
    printf '%s\n' "$want"; return 0
  fi
  local cand
  cand="$(get_field "$file" next_speaker)"
  if [ -n "$cand" ] && csv_has "$roster" "$cand"; then printf '%s\n' "$cand"; return 0; fi
  cand="$(csv_first "$(get_field "$file" rotation)")"
  if [ -n "$cand" ] && csv_has "$roster" "$cand"; then printf '%s\n' "$cand"; return 0; fi
  cand="$(get_field "$file" convener)"
  if [ -n "$cand" ] && csv_has "$roster" "$cand"; then printf '%s\n' "$cand"; return 0; fi
  errln "resolve-speaker: no roster-valid default speaker"
  return 1
}

cmd_advance() {
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "advance: file not found: $file"
  local speaker="" synthesis="" next=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --speaker)   speaker=$2; shift 2;;
      --next)      next=$2; shift 2;;
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

  local roster counter
  roster="$(get_field "$file" roster)"
  csv_has "$roster" "$speaker" || { errln "advance: '$speaker' not in roster"; return 3; }
  # Validate the directed next-speaker BEFORE mutating anything (fail-before-write).
  if [ -n "$next" ]; then
    csv_has "$roster" "$next" || { errln "advance: --next '$next' not in roster ($roster)"; return 3; }
  fi

  counter="$(get_field "$file" turn_counter)"
  counter=$((counter + 1))
  set_field "$file" turn_counter "$counter"

  # Spec 140: no round-robin. next_speaker changes only when this turn directed
  # the floor via an explicit `Next: <id>` marker (passed through as --next).
  # With no directive, the derived default persists unchanged.
  if [ -n "$next" ]; then
    set_field "$file" next_speaker "$next"
  fi
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

  # Parse the addressing marker BEFORE mutating anything (fail-before-write).
  # A final `Next: <id>` line directs the floor; an explicit-but-invalid
  # directive (empty / multi-token / non-roster id) is an author error and
  # fails the append. A final line not beginning with `Next:` = no marker.
  local marker_next=""
  if marker_tok="$(_marker_from_body "$body_file")"; then
    if csv_has "$roster" "$marker_tok"; then
      marker_next="$marker_tok"
    else
      errln "append-turn: invalid 'Next: $marker_tok' directive — not a roster id ($roster)"
      return 3
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

  # Advance only after the body is safely appended. A valid trailing marker
  # directs the floor via --next; otherwise the derived default persists.
  if [ -n "$marker_next" ]; then
    cmd_advance "$file" --speaker "$speaker" --next "$marker_next" >/dev/null
  else
    cmd_advance "$file" --speaker "$speaker" >/dev/null
  fi
  echo "appended turn $n by $speaker"
}

# ── anti-confirmation-bias mechanics (spec 149) ──────────────────────────────
# Shared by /meeting (decision-grade tier) and /sdd debate. Four stages:
#   commit/reveal  — blind opening (de-anchor turn 1)
#   ab-map         — randomized Proposal A/B labels at the judgment surface
#   ledger         — claim/evidence convergence GATE (assertion-only != resolved)
#   check-anchors  — deterministic verification of cheap evidence anchors
# Sealed blind-phase state lives under the already-gitignored
# .agent0/.runtime-state/ tree so un-revealed openings never reach a peer prompt
# and never enter git. Blindness here is procedural + tamper-evident (the hash is
# recorded before reveal), not cryptographic against an adversarial peer.

_repo_root() {
  local file=$1 root
  root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-$PWD}"
  printf '%s' "$root"
}

_state_dir() {
  # <file> → sealed gitignored scratch keyed by the transcript's absolute path
  local file=$1 abs key root
  abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  key="$(printf '%s' "$abs" | sha256sum | cut -c1-16)"
  root="$(_repo_root "$file")"
  printf '%s/.agent0/.runtime-state/deliberation/%s' "$root" "$key"
}

# _insert_block <file> <block_file> — splice a block in just before '## Synthesis'
# (keeps synthesis last); fall back to EOF if there is no Synthesis header.
_insert_block() {
  local file=$1 block=$2 tmp; tmp="$(mktemp)"
  awk -v bf="$block" '
    /^## Synthesis[[:space:]]*$/ && !done { while ((getline ln < bf) > 0) print ln; close(bf); done=1 }
    { print }
    END { if (!done) { while ((getline ln < bf) > 0) print ln; close(bf) } }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# model speakers = roster minus `human`
_model_speakers() {
  local roster=$1 x out=""
  IFS=',' read -ra _a <<< "$roster"
  for x in "${_a[@]}"; do x="${x// /}"; [ "$x" = "human" ] && continue; [ -n "$x" ] && out="$out $x"; done
  printf '%s' "${out# }"
}

cmd_commit() {
  # commit <file> --speaker <id> --text-file <opening>
  # Seals the opening (gitignored) + records a commitment row; the opening text
  # is NOT written to the transcript, so a peer prompt built from the transcript
  # cannot see it before its own commit.
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "commit: file not found: $file"
  local speaker="" text=""
  while [ $# -gt 0 ]; do case "$1" in
    --speaker)   speaker=$2; shift 2;;
    --text-file) text=$2; shift 2;;
    *) die "commit: unknown arg: $1";; esac; done
  [ -n "$speaker" ] || die "commit: --speaker required"
  [ -f "$text" ]   || die "commit: --text-file not found: $text"
  local roster; roster="$(get_field "$file" roster)"
  csv_has "$roster" "$speaker" || { errln "commit: '$speaker' not in roster ($roster)"; return 3; }
  local phase; phase="$(get_field "$file" blind_phase)"
  [ "$phase" = "revealed" ] && { errln "commit: blind phase already revealed; no new commitments"; return 1; }
  local sd; sd="$(_state_dir "$file")"; mkdir -p "$sd/openings"
  local hash bytes
  hash="$(sha256sum "$text" | cut -d' ' -f1)"
  bytes="$(wc -c < "$text" | tr -d ' ')"
  cp "$text" "$sd/openings/$speaker.txt"
  printf '%s\n' "$hash" > "$sd/openings/$speaker.hash"
  set_field "$file" blind_phase "open"
  # audit row in a managed Blind-submissions section (create once)
  if ! grep -q '^## Blind submissions' "$file"; then
    local hdr; hdr="$(mktemp)"
    printf '## Blind submissions (commit/reveal)\n\n_Commitments recorded before any opening is revealed — de-anchors round 1 (spec 149)._\n\n' > "$hdr"
    _insert_block "$file" "$hdr"; rm -f "$hdr"
  fi
  local row; row="$(mktemp)"
  printf -- '- commit %s — `sha256:%s` (%s bytes)\n' "$speaker" "${hash:0:16}" "$bytes" > "$row"
  _insert_block "$file" "$row"; rm -f "$row"
  echo "committed $speaker (sha256:${hash:0:12}…, $bytes bytes)"
}

cmd_reveal() {
  # reveal <file> --label-<id> "<runtime label>"... (labels optional)
  # Requires ALL model speakers to have committed; verifies each sealed opening's
  # hash against its recorded commitment; publishes each opening as a turn; flips
  # blind_phase=revealed (unlocks critique). Refuses if any model speaker has not
  # committed (the mechanical blindness guard).
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "reveal: file not found: $file"
  local roster; roster="$(get_field "$file" roster)"
  local sd; sd="$(_state_dir "$file")"
  local models; models="$(_model_speakers "$roster")"
  [ -n "$models" ] || die "reveal: no model speakers in roster"
  local sp
  for sp in $models; do
    [ -f "$sd/openings/$sp.hash" ] || { errln "reveal: '$sp' has not committed — refusing (blind phase needs all commitments first)"; return 1; }
  done
  # verify + publish each
  for sp in $models; do
    local want got
    want="$(cat "$sd/openings/$sp.hash")"
    got="$(sha256sum "$sd/openings/$sp.txt" | cut -d' ' -f1)"
    [ "$want" = "$got" ] || { errln "reveal: hash mismatch for '$sp' — sealed opening was tampered after commit"; return 1; }
  done
  set_field "$file" blind_phase "revealed"
  for sp in $models; do
    cmd_append_turn "$file" --speaker "$sp" --label "$sp (blind opening)" --body-file "$sd/openings/$sp.txt" >/dev/null
  done
  echo "revealed ${models// /, } — hashes verified; critique unlocked"
}

cmd_ab_map() {
  # ab-map <file> — print a randomized Proposal-A/B ↔ model-speaker mapping and
  # record it as an attributed audit line (durable transcript stays attributed;
  # the critique VIEW uses the A/B labels). Two model speakers (the common case).
  local file=${1:-}
  [ -f "$file" ] || die "ab-map: file not found: $file"
  local roster; roster="$(get_field "$file" roster)"
  local models; models="$(_model_speakers "$roster")"
  # shellcheck disable=SC2206
  local arr=($models)
  [ "${#arr[@]}" -ge 2 ] || die "ab-map: needs >= 2 model speakers"
  # randomized order without Date/RANDOM determinism concerns: shuf if present, else awk-hash of nonce
  local order
  if command -v shuf >/dev/null 2>&1; then
    order="$(printf '%s\n' "${arr[@]}" | shuf)"
  else
    order="$(printf '%s\n' "${arr[@]}" | awk '{print rand()"\t"$0}' | sort | cut -f2-)"
  fi
  local labels=(A B C D E F G H) i=0 out=""
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    out="$out Proposal ${labels[$i]}=$sp"
    i=$((i + 1))
  done <<< "$order"
  out="${out# }"
  local row; row="$(mktemp)"
  printf -- '- ab-map: %s _(judgment-surface labels; transcript stays attributed)_\n' "$out" > "$row"
  _insert_block "$file" "$row"; rm -f "$row"
  printf '%s\n' "$out"
}

cmd_ledger_add() {
  # ledger-add <file> --claim "<text>" --tag <supported|contradicted|unresolved|assertion-only> --anchor "<ref>"
  local file=${1:-}; shift || true
  [ -f "$file" ] || die "ledger-add: file not found: $file"
  local claim="" tag="" anchor=""
  while [ $# -gt 0 ]; do case "$1" in
    --claim)  claim=$2; shift 2;;
    --tag)    tag=$2; shift 2;;
    --anchor) anchor=$2; shift 2;;
    *) die "ledger-add: unknown arg: $1";; esac; done
  [ -n "$claim" ] || die "ledger-add: --claim required"
  case "$tag" in
    supported|contradicted|unresolved|assertion-only) ;;
    *) die "ledger-add: --tag must be supported|contradicted|unresolved|assertion-only";;
  esac
  [ -n "$anchor" ] || anchor="(none)"
  # Sanitize: a literal '|' in claim/anchor would corrupt the markdown table's
  # column split (read back by ledger-check / check-anchors). Replace with '/'.
  claim="${claim//|//}"
  anchor="${anchor//|//}"
  if ! grep -q '^## Claim/evidence ledger' "$file"; then
    local hdr; hdr="$(mktemp)"
    printf '## Claim/evidence ledger\n\n_Convergence GATE: a point with only `assertion-only` claims is NOT resolved, regardless of agreement (spec 149)._\n\n| claim | tag | anchor |\n| --- | --- | --- |\n' > "$hdr"
    _insert_block "$file" "$hdr"; rm -f "$hdr"
  fi
  # append the row directly under the table header (after the |---| separator line)
  local tmp; tmp="$(mktemp)"
  awk -v c="$claim" -v t="$tag" -v a="$anchor" '
    { print }
    /^\| --- \| --- \| --- \|[[:space:]]*$/ && !done { printf "| %s | %s | %s |\n", c, t, a; done=1 }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
  echo "ledger-add: [$tag] $claim"
}

cmd_ledger_check() {
  # ledger-check <file> — the convergence gate. Exit 0 if every ledger row is
  # supported/contradicted/unresolved; exit 1 if ANY row is assertion-only
  # (those points are NOT resolved by agreement). Prints a summary.
  local file=${1:-}
  [ -f "$file" ] || die "ledger-check: file not found: $file"
  grep -q '^## Claim/evidence ledger' "$file" || { echo "ledger-check: no ledger present"; return 0; }
  local total assertion
  total="$(awk -F'|' '/^\| / && $3 !~ /---/ && $3 !~ /^[[:space:]]*tag[[:space:]]*$/ {n++} END{print n+0}' "$file")"
  assertion="$(awk -F'|' '/^\| / { t=$3; gsub(/[[:space:]]/,"",t); if (t=="assertion-only") n++ } END{print n+0}' "$file")"
  printf 'ledger: %s claim(s), %s assertion-only\n' "$total" "$assertion"
  if [ "$assertion" -gt 0 ]; then
    errln "ledger-check: $assertion claim(s) are assertion-only — those convergence points are UNRESOLVED regardless of agreement"
    return 1
  fi
  echo "ledger-check: all claims have an external anchor"
  return 0
}

cmd_check_anchors() {
  # check-anchors <file> — deterministic v1 verification of cheap anchors in the
  # ledger's anchor column: a `path:<p>` anchor must exist on disk; a
  # `test:<id>` anchor must appear in the test tree. Anything else is reported
  # `unverified` (trusted-as-cited; not failed). Re-running tests is v2.
  local file=${1:-}
  [ -f "$file" ] || die "check-anchors: file not found: $file"
  grep -q '^## Claim/evidence ledger' "$file" || { echo "check-anchors: no ledger"; return 0; }
  local root; root="$(_repo_root "$file")"
  local bad=0 line anchor
  while IFS= read -r line; do
    anchor="$(printf '%s' "$line" | awk -F'|' '{a=$4; gsub(/^[[:space:]]+|[[:space:]]+$/,"",a); print a}')"
    case "$anchor" in
      path:*)
        local p="${anchor#path:}"
        if [ -e "$root/$p" ] || [ -e "$p" ]; then printf 'ok   path %s\n' "$p"; else printf 'FAIL path %s (not found)\n' "$p"; bad=$((bad+1)); fi;;
      test:*)
        local t="${t:-}"; t="${anchor#test:}"
        if grep -rqs -- "$t" "$root/.agent0/tests" "$root/.claude/skills/product/scripts" 2>/dev/null; then printf 'ok   test %s\n' "$t"; else printf 'FAIL test %s (not found in test tree)\n' "$t"; bad=$((bad+1)); fi;;
      ""|"(none)"|"anchor"|"---"|---*) : ;;
      *) printf 'unverified %s (trusted-as-cited)\n' "$anchor";;
    esac
  done < <(grep -E '^\| ' "$file")
  if [ "$bad" -gt 0 ]; then errln "check-anchors: $bad anchor(s) failed deterministic verification"; return 1; fi
  return 0
}

# ── dispatch ─────────────────────────────────────────────────────────────────
main() {
  local sub=${1:-}
  [ -n "$sub" ] || die "usage: meeting.sh <init|state|friction|next|check|resolve-speaker|advance|append-turn> ..."
  shift
  case "$sub" in
    init)            cmd_init "$@";;
    state)           cmd_state "$@";;
    friction)        cmd_friction "$@";;
    next)            cmd_next "$@";;
    check)           cmd_check "$@";;
    resolve-speaker) cmd_resolve_speaker "$@";;
    advance)         cmd_advance "$@";;
    append-turn)     cmd_append_turn "$@";;
    commit)          cmd_commit "$@";;
    reveal)          cmd_reveal "$@";;
    ab-map)          cmd_ab_map "$@";;
    ledger-add)      cmd_ledger_add "$@";;
    ledger-check)    cmd_ledger_check "$@";;
    check-anchors)   cmd_check_anchors "$@";;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
