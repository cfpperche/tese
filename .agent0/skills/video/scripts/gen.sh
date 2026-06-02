#!/usr/bin/env bash
# .agent0/skills/video/scripts/gen.sh
#
# Generative mode of /video. Paid, async (fal.ai queue). Fire-and-forget
# LEDGER model (debate R2): submit returns a request_id persisted to a
# gitignored ledger; a separate `poll` invocation reaps terminal jobs. NEVER a
# blocking loop. Tier→model resolves from references/video-tiers.yaml (no model
# IDs baked here). Cost gate is HARD: --confirm-cost-usd must cover the estimate
# (debate R1/Q3) — a passive print is insufficient at 100-1000x image cost.
#
# Subcommands:
#   prepare --tier=<draft|standard|premium> --duration=<sec> [--image-url=<u>]
#           [--name=<slug>] --confirm-cost-usd=<max> "<prompt>"
#   submit  --envelope=<prepare-json>
#   poll    [--all | --id=<request_id>]
#   record  --model --cost-estimate --cost-actual --prompt --output --request-id --status
#
# Shared fal REST primitives: .agent0/tools/fal-rest.sh (no model IDs there).
# Capacity rule: .agent0/context/rules/video-gen.md

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIERS_FILE="$SKILL_DIR/references/video-tiers.yaml"
FAL_REST="$PROJECT_DIR/.agent0/tools/fal-rest.sh"
LEDGER="$PROJECT_DIR/.agent0/.runtime-state/video-jobs/ledger.jsonl"
MANIFEST="$PROJECT_DIR/assets/generated/.video-manifest.jsonl"
OUT_DIR="assets/generated/videos"   # repo-relative; gitignored

die() { printf '/video gen: %s\n' "$1" >&2; exit "${2:-2}"; }

die_no_mode_args() {
  cat >&2 <<'EOF'
/video --mode=generative error: required args missing. Shape:
  /video --mode=generative --tier=<draft|standard|premium> --duration=<sec> \
         --confirm-cost-usd=<max> [--image-url=<url>] [--name=<slug>] "<prompt>"

Tiers (see references/video-tiers.yaml — refreshable):
  draft     ~$0.10/s  Wan-class, 720p, fast iteration
  standard  ~$0.11/s  Kling-class, 1080p, subject consistency
  premium   ~$0.40/s  Veo-class, up to 4K + audio
EOF
  exit 2
}

die_no_fal_key() {
  cat >&2 <<'EOF'
/video --mode=generative error: FAL_KEY is not set.
  1. Mint a key at https://fal.ai → Dashboard → API Keys
  2. export FAL_KEY="<uuid>:<secret>"
See .agent0/context/rules/video-gen.md § Activation.
EOF
  exit 2
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])'
}

# resolve_tier_field <tier> <field> — read tiers.<tier>.<field> from the YAML.
# Targeted line-parse for the fixed 2-space/4-space structure (no yq dependency).
resolve_tier_field() {
  local tier="$1" field="$2"
  awk -v tier="$tier" -v field="$field" '
    /^tiers:/        { intiers=1; next }
    intiers && /^[A-Za-z]/ { intiers=0 }              # left the tiers: block
    intiers && $0 ~ ("^  " tier ":")  { found=1; next }
    found && /^  [A-Za-z]/ && $0 !~ /^    / { found=0 } # next sibling tier
    found && $0 ~ ("^    " field ":") {
      line=$0; sub("^    " field ": *","",line); gsub(/"/,"",line); print line; exit
    }
  ' "$TIERS_FILE"
}

yaml_top() {  # read a top-level scalar key
  local key="$1"
  awk -v key="$key" '$0 ~ ("^" key ":") { sub("^" key ": *",""); gsub(/"/,""); print; exit }' "$TIERS_FILE"
}

staleness_advisory() {
  local snap stale today snap_s today_s age
  snap="$(yaml_top snapshot_date)"; stale="$(yaml_top stale_after_days)"
  [ -n "$snap" ] && [ -n "$stale" ] || return 0
  snap_s="$(date -u -d "$snap" +%s 2>/dev/null)" || return 0
  today_s="$(date -u +%s)"
  age=$(( (today_s - snap_s) / 86400 ))
  if [ "$age" -gt "$stale" ]; then
    printf 'video-advisory: video-tiers.yaml snapshot is %sd old (> %sd); refresh model IDs/prices before trusting the estimate\n' \
      "$age" "$stale" >&2
  fi
}

sub_prepare() {
  local tier="" duration="" image_url="" name="" confirm="" prompt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier=*)             tier="${1#--tier=}"; shift ;;
      --duration=*)         duration="${1#--duration=}"; shift ;;
      --image-url=*)        image_url="${1#--image-url=}"; shift ;;
      --name=*)             name="${1#--name=}"; shift ;;
      --confirm-cost-usd=*) confirm="${1#--confirm-cost-usd=}"; shift ;;
      --tier)             tier="${2:-}"; shift 2 ;;
      --duration)         duration="${2:-}"; shift 2 ;;
      --image-url)        image_url="${2:-}"; shift 2 ;;
      --name)             name="${2:-}"; shift 2 ;;
      --confirm-cost-usd) confirm="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) die "prepare: unknown flag: $1" ;;
      *) prompt="$1"; shift ;;
    esac
  done
  [ $# -gt 0 ] && prompt="$prompt $*"
  prompt="${prompt# }"

  [ -z "$tier" ] || [ -z "$duration" ] && die_no_mode_args
  [ -z "$prompt" ] && die_no_mode_args
  [ -z "${FAL_KEY:-}" ] && die_no_fal_key

  staleness_advisory

  local model price maxdur
  model="$(resolve_tier_field "$tier" model)"
  price="$(resolve_tier_field "$tier" price_usd_per_second)"
  maxdur="$(resolve_tier_field "$tier" max_duration_seconds)"
  [ -n "$model" ] || die "prepare: unknown --tier=$tier (valid: draft|standard|premium)"

  case "$duration" in (*[!0-9.]*|"") die "prepare: --duration must be numeric seconds";; esac
  if [ -n "$maxdur" ] && awk -v d="$duration" -v m="$maxdur" 'BEGIN{exit !(d>m)}'; then
    printf 'video-advisory: duration %ss exceeds tier max %ss; fal may clamp or reject\n' "$duration" "$maxdur" >&2
  fi

  # estimate = price * duration  (2dp)
  local estimate
  estimate="$(awk -v p="$price" -v d="$duration" 'BEGIN{printf "%.2f", p*d}')"

  # HARD cost gate — refuse unless --confirm-cost-usd covers the estimate.
  if [ -z "$confirm" ]; then
    printf '/video gen: estimated $%s for %s (%ss @ $%s/s).\n' "$estimate" "$model" "$duration" "$price" >&2
    printf '/video gen: REFUSED — pass --confirm-cost-usd=%s (or higher) to authorize this paid generation.\n' "$estimate" >&2
    exit 2
  fi
  if awk -v c="$confirm" -v e="$estimate" 'BEGIN{exit !(c<e)}'; then
    printf '/video gen: REFUSED — --confirm-cost-usd=%s is below the estimate $%s for %s.\n' "$confirm" "$estimate" "$model" >&2
    exit 2
  fi

  local slug
  slug="${name:-$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ' | awk '{n=(NF<5)?NF:5; o=""; for(i=1;i<=n;i++){if($i=="")continue; o=(o=="")?$i:o"-"$i} print o}')}"
  [ -z "$slug" ] && slug="clip"
  local output_path="$OUT_DIR/$(date -u +%Y-%m-%d)-$slug.mp4"

  printf 'estimated: $%s for %s (%ss) — confirmed ceiling $%s\n' "$estimate" "$model" "$duration" "$confirm"
  # Envelope: model + a generic fal body (prompt/duration/image_url) + bookkeeping
  local image_field=""
  [ -n "$image_url" ] && image_field="$(printf ',"image_url":"%s"' "$(json_escape "$image_url")")"
  printf '{"mode":"generative","tier":"%s","model":"%s","duration":%s,"cost_estimate_usd":%s,"confirm_cost_usd":%s,"output_path":"%s","prompt":"%s","body":{"prompt":"%s","duration":%s%s}}\n' \
    "$tier" "$model" "$duration" "$estimate" "$confirm" "$output_path" \
    "$(json_escape "$prompt")" "$(json_escape "$prompt")" "$duration" "$image_field"
}

sub_submit() {
  local envelope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --envelope=*) envelope="${1#--envelope=}"; shift ;;
      --envelope)   envelope="${2:-}"; shift 2 ;;
      *) die "submit: unknown arg: $1" ;;
    esac
  done
  [ -z "$envelope" ] && { [ -t 0 ] && die "submit: --envelope=<json> required"; envelope="$(cat)"; }
  [ -z "${FAL_KEY:-}" ] && die_no_fal_key

  local model body output_path estimate confirm prompt tier
  model="$(printf '%s' "$envelope" | jq -r '.model // ""')"
  body="$(printf '%s' "$envelope" | jq -c '.body // {}')"
  output_path="$(printf '%s' "$envelope" | jq -r '.output_path // ""')"
  estimate="$(printf '%s' "$envelope" | jq -r '.cost_estimate_usd // 0')"
  confirm="$(printf '%s' "$envelope" | jq -r '.confirm_cost_usd // 0')"
  prompt="$(printf '%s' "$envelope" | jq -r '.prompt // ""')"
  tier="$(printf '%s' "$envelope" | jq -r '.tier // ""')"
  [ -n "$model" ] || die "submit: envelope missing model"

  local resp request_id
  resp="$(bash "$FAL_REST" submit --model="$model" --body="$body")" || die "submit: fal-rest submit failed" 1
  request_id="$(printf '%s' "$resp" | jq -r '.request_id // ""')"
  [ -n "$request_id" ] || die "submit: no request_id in fal response" 1

  mkdir -p "$(dirname "$LEDGER")"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","request_id":"%s","model":"%s","tier":"%s","status":"submitted","output_path":"%s","cost_estimate_usd":%s,"confirm_cost_usd":%s,"prompt":"%s"}\n' \
    "$ts" "$request_id" "$model" "$tier" "$output_path" "$estimate" "$confirm" "$(json_escape "$prompt")" >> "$LEDGER"

  printf 'submitted: request_id=%s model=%s — reap with: /video poll --id=%s (or --all)\n' "$request_id" "$model" "$request_id"
}

# reap_one <request_id> — drives status→result→download→manifest for one job.
reap_one() {
  local rid="$1" model output_path estimate prompt
  model="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .model' "$LEDGER" | tail -1)"
  output_path="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .output_path' "$LEDGER" | tail -1)"
  estimate="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .cost_estimate_usd' "$LEDGER" | tail -1)"
  prompt="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .prompt' "$LEDGER" | tail -1)"
  [ -n "$model" ] || { printf 'poll: %s not found in ledger\n' "$rid" >&2; return 1; }

  local status_json status
  status_json="$(bash "$FAL_REST" status --model="$model" --request-id="$rid" 2>/dev/null)" || {
    printf 'poll: %s status check failed\n' "$rid" >&2; return 1; }
  status="$(printf '%s' "$status_json" | jq -r '.status // "UNKNOWN"')"

  case "$status" in
    COMPLETED)
      local result_json url abs_out
      result_json="$(bash "$FAL_REST" result --model="$model" --request-id="$rid")" || return 1
      url="$(printf '%s' "$result_json" | jq -r '.video.url // .video // (.videos[0].url // "") // ""')"
      [ -n "$url" ] && [ "$url" != "null" ] || { printf 'poll: %s completed but no video url in result\n' "$rid" >&2; return 1; }
      abs_out="$PROJECT_DIR/$output_path"
      bash "$FAL_REST" download --url="$url" --output="$abs_out" >/dev/null || { sub_record_internal "$model" "$estimate" "" "$prompt" "$output_path" "$rid" failure; return 1; }
      sub_record_internal "$model" "$estimate" "$estimate" "$prompt" "$output_path" "$rid" success
      printf 'reaped: %s -> %s\n' "$rid" "$output_path"
      ;;
    IN_QUEUE|IN_PROGRESS) printf 'pending: %s is %s\n' "$rid" "$status" ;;
    *) printf 'poll: %s status=%s (treating as failure)\n' "$rid" "$status" >&2
       sub_record_internal "$model" "$estimate" "" "$prompt" "$output_path" "$rid" failure ;;
  esac
}

sub_poll() {
  local all=0 id=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1; shift ;;
      --id=*) id="${1#--id=}"; shift ;;
      --id)   id="${2:-}"; shift 2 ;;
      *) die "poll: unknown arg: $1" ;;
    esac
  done
  [ -z "${FAL_KEY:-}" ] && die_no_fal_key
  [ -f "$LEDGER" ] || { printf 'poll: no jobs ledger yet (%s)\n' "$LEDGER"; return 0; }

  if [ -n "$id" ]; then reap_one "$id"; return $?; fi
  [ "$all" -eq 1 ] || die "poll: pass --all or --id=<request_id>"

  # Reap every request_id whose latest ledger status is 'submitted'.
  local rids
  rids="$(jq -r '.request_id' "$LEDGER" | awk '!seen[$0]++')"
  local any=0
  while IFS= read -r rid; do
    [ -z "$rid" ] && continue
    local last; last="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .status' "$LEDGER" | tail -1)"
    [ "$last" = "submitted" ] && { any=1; reap_one "$rid"; }
  done <<< "$rids"
  [ "$any" -eq 0 ] && printf 'poll: no pending (submitted) jobs to reap\n'
}

# sub_record_internal model estimate actual prompt output request_id status
sub_record_internal() {
  local model="$1" estimate="$2" actual="$3" prompt="$4" output="$5" rid="$6" status="$7"
  mkdir -p "$(dirname "$MANIFEST")"
  local ts session session_field actual_field
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  session="${CLAUDE_SESSION_ID:-null}"
  if [ "$session" = "null" ]; then session_field='null'; else session_field="\"$(json_escape "$session")\""; fi
  if [ -z "$actual" ]; then actual_field='null'; else actual_field="$actual"; fi
  printf '{"ts":"%s","session_id":%s,"mode":"generative","model":"%s","cost_estimate_usd":%s,"cost_actual_usd":%s,"prompt":"%s","output_path":"%s","request_id":"%s","status":"%s"}\n' \
    "$ts" "$session_field" "$model" "${estimate:-0}" "$actual_field" "$(json_escape "$prompt")" "$(json_escape "$output")" "$rid" "$status" >> "$MANIFEST"
  # advisory if actual exceeded ceiling — record-and-warn, never un-bill (debate R3)
  if [ -n "$actual" ] && [ "$status" = "success" ]; then
    local confirm; confirm="$(jq -r --arg r "$rid" 'select(.request_id==$r) | .confirm_cost_usd' "$LEDGER" 2>/dev/null | tail -1)"
    if [ -n "$confirm" ] && awk -v a="$actual" -v c="$confirm" 'BEGIN{exit !(a>c)}'; then
      printf 'video-advisory: actual cost $%s exceeded confirmed ceiling $%s (job already billed)\n' "$actual" "$confirm" >&2
    fi
  fi
}

case "${1:-}" in
  prepare) shift; sub_prepare "$@" ;;
  submit)  shift; sub_submit "$@" ;;
  poll)    shift; sub_poll "$@" ;;
  record)  shift; die "record is internal to poll in v1" ;;
  ""|-h|--help)
    cat <<'EOF'
/video gen.sh — generative mode (paid, async fal.ai queue, ledger-based)

  prepare --tier=<draft|standard|premium> --duration=<sec> --confirm-cost-usd=<max>
          [--image-url=<url>] [--name=<slug>] "<prompt>"
  submit  --envelope=<prepare-json>
  poll    [--all | --id=<request_id>]

Cost gate is HARD: prepare REFUSES without --confirm-cost-usd >= estimate.
Async is fire-and-forget: submit persists a request_id; poll reaps it later.
See .agent0/context/rules/video-gen.md.
EOF
    [ -z "${1:-}" ] && exit 0 || exit 0 ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
