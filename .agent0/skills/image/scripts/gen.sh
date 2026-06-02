#!/usr/bin/env bash
# .agent0/skills/image/scripts/gen.sh
#
# Self-contained, runtime-neutral helper for the /image skill. The full
# pipeline runs from bash — no runtime tool surface required:
#   - prepare : validate inputs, derive output path, print cost estimate,
#               emit JSON envelope
#   - exec    : POST the envelope to the fal.run REST API, download the image,
#               reconcile dimensions (see spec 088 — generation does NOT use
#               the fal-ai MCP's run_model, which was diagnosed broken)
#   - record  : append a manifest line after exec success/failure
#
# Three-stage shape is deliberate — prepare is the cost-print contract surface,
# exec is the network-bound generation step, record is the audit step. The
# SKILL.md body coordinates the three calls; any agentskills.io runtime that
# can run bash + curl + jq drives it identically.
#
# Reference:
#   .agent0/context/rules/image-gen.md                       — capacity rule
#   .agent0/skills/image/SKILL.md                    — invocation surface
#   .agent0/skills/image/references/tier-pricing.md  — static cost table

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MANIFEST_PATH="$PROJECT_DIR/assets/generated/.manifest.jsonl"
# Shared fal REST primitives (spec 133 — one HTTP impl across /image + /video).
FAL_REST="$PROJECT_DIR/.agent0/tools/fal-rest.sh"

# ---------------------------------------------------------------------------
# Tier table — keep in sync with .agent0/skills/image/references/tier-pricing.md
# ---------------------------------------------------------------------------
# Format per tier: MODEL|DIR|COST_USD|EXT
#   EXT is the file extension matching fal.ai's default content-type per model
#   (verified empirically 2026-05-24 via fal.run REST API):
#     - FLUX schnell    → image/jpeg
#     - gpt-image-2     → image/png  (verify before first brand-text invocation)
#     - imagen4/ultra   → image/png  (verify before first brand-photo invocation)
# v1 bakes quality=high for brand-text; see references/tier-pricing.md § brand-text
TIER_TABLE='draft|fal-ai/flux/schnell|assets/generated/mockups|0.003|jpg
brand-text|fal-ai/gpt-image-2|assets/brand|0.200|png
brand-photo|fal-ai/imagen4/ultra|assets/brand|0.060|png'

# ---------------------------------------------------------------------------
# Aspect table — fal.ai image_size enum + resolved dimensions
# ---------------------------------------------------------------------------
# Format per aspect: ASPECT|IMAGE_SIZE_ENUM|DIMENSIONS
# Enum values per fal.ai docs (https://fal.ai/models/fal-ai/flux/schnell).
ASPECT_TABLE='square|square_hd|1024x1024
landscape|landscape_16_9|1024x576
portrait|portrait_16_9|576x1024'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die_no_tier() {
  cat >&2 <<'EOF'
/image error: --tier is required. Pick one:
  --tier=draft       cheap mockup       (~$0.003/img, FLUX schnell)
  --tier=brand-text  premium with text  ($0.04-0.20/img, gpt-image-2)
  --tier=brand-photo premium photo-real (~$0.06/img, Imagen 4 Ultra)
EOF
  exit 2
}

die_bad_tier() {
  printf '/image error: invalid --tier=%s. Valid: draft, brand-text, brand-photo.\n' "$1" >&2
  exit 2
}

die_bad_aspect() {
  printf '/image error: invalid --aspect=%s. Valid: square, landscape, portrait.\n' "$1" >&2
  exit 2
}

die_no_fal_key() {
  cat >&2 <<'EOF'
/image error: FAL_KEY environment variable is not set.

Activation steps:
  1. Sign up at https://fal.ai and mint an API key
  2. export FAL_KEY="<uuid>:<secret>" in your shell or .env
  3. cp .mcp.json.example .mcp.json (if not done) and uncomment the fal-ai block
  4. Restart the Claude Code session (MCPs load at session start)

See .agent0/context/rules/image-gen.md § Activation for the full workflow.
EOF
  exit 2
}

die_bad_name() {
  printf '/image error: --name=%s must be kebab-case (^[a-z][a-z0-9-]*$)\n' "$1" >&2
  exit 2
}

# kebab_slug "raw prompt text"
# → drops non-alphanumerics, lowercases, joins first 5 words with hyphens
kebab_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' ' ' \
    | awk '{
        n = (NF < 5) ? NF : 5
        out = ""
        for (i = 1; i <= n; i++) {
          if ($i == "") continue
          out = (out == "") ? $i : out "-" $i
        }
        print out
      }'
}

# resolve_tier <tier-key>
# → echoes "MODEL|DIR|COST|EXT" on hit (return 0), nothing on miss (return 1).
# Caller is responsible for translating return 1 → die. Cannot `exit` from here:
# resolvers are called via $() (command substitution) which spawns a subshell;
# `exit` inside the subshell only kills the subshell, leaving the parent to
# continue with empty stdout. Tested empirically 2026-05-24.
resolve_tier() {
  local key="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$key"\|*) printf '%s\n' "${line#"$key"|}"; return 0 ;;
    esac
  done <<<"$TIER_TABLE"
  return 1
}

# resolve_aspect <aspect-key>
# → echoes "IMAGE_SIZE_ENUM|DIMS" on hit (return 0), nothing on miss (return 1).
# Same subshell-exit caveat as resolve_tier above.
resolve_aspect() {
  local key="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$key"\|*) printf '%s\n' "${line#"$key"|}"; return 0 ;;
    esac
  done <<<"$ASPECT_TABLE"
  return 1
}

# collision_suffix <path>
# → echoes a free path (appending -2, -3, ... if needed). Extension-agnostic:
# splits on the LAST dot so .jpg / .png / .webp all work identically.
collision_suffix() {
  local base="$1" dir name ext candidate n
  dir="$(dirname "$base")"
  ext=".${base##*.}"
  name="$(basename "$base" "$ext")"
  candidate="$base"
  n=2
  while [ -e "$candidate" ]; do
    candidate="$dir/$name-$n$ext"
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

# json_escape <str> → echoes the input with quotes / backslashes / control chars escaped
json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])'
}

# ---------------------------------------------------------------------------
# Subcommand: prepare
# ---------------------------------------------------------------------------
sub_prepare() {
  local tier="" name="" prompt="" aspect="square"
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier=*)   tier="${1#--tier=}"; shift ;;
      --name=*)   name="${1#--name=}"; shift ;;
      --aspect=*) aspect="${1#--aspect=}"; shift ;;
      --tier)     tier="${2:-}"; shift 2 ;;
      --name)     name="${2:-}"; shift 2 ;;
      --aspect)   aspect="${2:-square}"; shift 2 ;;
      --) shift; break ;;
      -*) printf '/image error: unknown flag: %s\n' "$1" >&2; exit 2 ;;
      *) prompt="$1"; shift ;;
    esac
  done
  # remaining args concatenated as prompt (in case prompt was unquoted)
  if [ $# -gt 0 ]; then
    prompt="$prompt $*"
  fi
  prompt="${prompt# }"

  [ -z "$tier" ] && die_no_tier
  [ -z "${FAL_KEY:-}" ] && die_no_fal_key
  [ -z "$prompt" ] && { printf '/image error: prompt is required.\n' >&2; exit 2; }

  if [ -n "$name" ]; then
    case "$name" in
      [a-z]*) : ;;
      *) die_bad_name "$name" ;;
    esac
    case "$name" in
      *[!a-z0-9-]*) die_bad_name "$name" ;;
    esac
  fi

  local tier_row model dir cost ext
  tier_row="$(resolve_tier "$tier")" || die_bad_tier "$tier"
  model="${tier_row%%|*}"; tier_row="${tier_row#*|}"
  dir="${tier_row%%|*}";   tier_row="${tier_row#*|}"
  cost="${tier_row%%|*}";  tier_row="${tier_row#*|}"
  ext="$tier_row"

  local aspect_row image_size dims
  aspect_row="$(resolve_aspect "$aspect")" || die_bad_aspect "$aspect"
  image_size="${aspect_row%%|*}"; aspect_row="${aspect_row#*|}"
  dims="$aspect_row"

  local slug base_path output_path
  slug="${name:-$(kebab_slug "$prompt")}"
  [ -z "$slug" ] && slug="image"

  # draft tier prefixes with date; brand tiers don't (durable, history-tracked)
  if [ "$tier" = "draft" ]; then
    base_path="$PROJECT_DIR/$dir/$(date -u +%Y-%m-%d)-$slug.$ext"
  else
    base_path="$PROJECT_DIR/$dir/$slug.$ext"
  fi
  mkdir -p "$(dirname "$base_path")"
  output_path="$(collision_suffix "$base_path")"

  # Cost estimate to stdout BEFORE the JSON envelope so it reads naturally
  printf 'estimated: $%s for %s at %s (%s)\n' "$cost" "$model" "$dims" "$aspect"

  # JSON envelope for the agent — adds image_size + extension so the agent
  # passes the right param to the MCP and saves with the right extension.
  printf '{"tier":"%s","model":"%s","prompt":"%s","output_path":"%s","approx_cost_usd":%s,"dimensions":"%s","aspect":"%s","image_size":"%s","extension":"%s"}\n' \
    "$tier" \
    "$model" \
    "$(json_escape "$prompt")" \
    "${output_path#"$PROJECT_DIR/"}" \
    "$cost" \
    "$dims" \
    "$aspect" \
    "$image_size" \
    "$ext"
}

# ---------------------------------------------------------------------------
# Subcommand: exec
# ---------------------------------------------------------------------------
# Consumes a prepare-shape JSON envelope, POSTs to fal.run REST (NOT MCP — see
# spec 088 and image-gen.md § Gotchas for the diagnosis driving this split),
# downloads the returned image to output_path, reconciles dimensions if the
# model upsampled (gpt-image-2 min-pixel floor case), and emits a JSON receipt.
# Exit 0 on success, non-zero on failure; receipt is always one JSON line on
# stdout so the agent can parse it regardless of outcome.
sub_exec() {
  local envelope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --envelope=*) envelope="${1#--envelope=}"; shift ;;
      --envelope)   envelope="${2:-}"; shift 2 ;;
      *) printf '/image exec: unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
  done

  # Fall back to stdin if --envelope not supplied
  if [ -z "$envelope" ]; then
    if [ -t 0 ]; then
      printf '/image exec: --envelope=<json> required (or pipe JSON via stdin)\n' >&2
      exit 2
    fi
    envelope=$(cat)
  fi

  [ -z "${FAL_KEY:-}" ] && die_no_fal_key

  local tier model prompt output_path image_size expected_dims
  tier="$(printf '%s' "$envelope"          | jq -r '.tier          // ""')"
  model="$(printf '%s' "$envelope"         | jq -r '.model         // ""')"
  prompt="$(printf '%s' "$envelope"        | jq -r '.prompt        // ""')"
  output_path="$(printf '%s' "$envelope"   | jq -r '.output_path   // ""')"
  image_size="$(printf '%s' "$envelope"    | jq -r '.image_size    // ""')"
  expected_dims="$(printf '%s' "$envelope" | jq -r '.dimensions    // ""')"

  if [ -z "$tier" ] || [ -z "$model" ] || [ -z "$prompt" ] || [ -z "$output_path" ]; then
    printf '/image exec: envelope missing required fields (tier/model/prompt/output_path)\n' >&2
    exit 2
  fi

  local abs_output
  case "$output_path" in
    /*) abs_output="$output_path" ;;
    *)  abs_output="$PROJECT_DIR/$output_path" ;;
  esac
  mkdir -p "$(dirname "$abs_output")"

  # Build request body. gpt-image-2 takes a quality enum; FLUX + Imagen do not.
  local body
  case "$model" in
    *gpt-image-2*)
      body="$(jq -nc --arg p "$prompt" --arg s "$image_size" \
        '{prompt:$p, image_size:$s, quality:"high"}')"
      ;;
    *)
      body="$(jq -nc --arg p "$prompt" --arg s "$image_size" \
        '{prompt:$p, image_size:$s}')"
      ;;
  esac

  # POST via the shared fal REST lib (synchronous fal.run endpoint; spec 133).
  # The lib owns auth ('Key', not 'Bearer'), the --max-time ceiling, and HTTP-error
  # handling — it dies non-zero with the fal error body on stderr. Image-specific
  # response parsing (.images[0].url) stays here. http_code is 0 on a lib failure
  # (the precise upstream code + body are on stderr).
  local resp
  if ! resp="$(bash "$FAL_REST" run --model="$model" --body="$body")"; then
    printf '{"status":"failure","http_code":0,"output_path":"%s"}\n' \
      "$(json_escape "$output_path")"
    exit 1
  fi

  local image_url
  image_url="$(printf '%s' "$resp" | jq -r '.images[0].url // ""')"
  if [ -z "$image_url" ]; then
    printf 'unexpected response shape (no .images[0].url)\n' >&2
    printf '{"status":"failure","http_code":200,"output_path":"%s"}\n' \
      "$(json_escape "$output_path")"
    exit 1
  fi

  # Two-hop download — fal.run returns a fal.media CDN URL, not the bytes.
  # The shared lib handles fetch errors + empty-file detection (dies non-zero).
  if ! bash "$FAL_REST" download --url="$image_url" --output="$abs_output" >/dev/null; then
    printf '{"status":"failure","http_code":200,"output_path":"%s"}\n' \
      "$(json_escape "$output_path")"
    exit 1
  fi

  # Dimension reconciliation. PNG `file` output: "PNG image data, 1088 x 608, ...".
  # JPEG `file` output carries a density artifact (e.g. "density 1x1") BEFORE the
  # real image dims, so head -1 picks up "1x1" instead of "1024x1024". Two-tier
  # parse: prefer ffprobe (exact, ships with ffmpeg) → fall back to file with
  # tail -1 (real image dims come after density in JPEG; no spurious NxN after).
  local actual_dims final_dims
  if command -v ffprobe >/dev/null 2>&1; then
    actual_dims="$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0:s=x "$abs_output" 2>/dev/null)"
  fi
  if [ -z "${actual_dims:-}" ]; then
    actual_dims="$(file "$abs_output" 2>/dev/null \
      | grep -oE '[0-9]+ ?x ?[0-9]+' | tail -1 | tr -d ' ')"
  fi
  final_dims="$actual_dims"

  if [ -n "$actual_dims" ] && [ -n "$expected_dims" ] && [ "$actual_dims" != "$expected_dims" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      local w h tmp
      w="${expected_dims%x*}"
      h="${expected_dims#*x}"
      tmp="${abs_output}.tmp.${RANDOM}"
      if ffmpeg -y -loglevel error -i "$abs_output" -vf "scale=${w}:${h}" "$tmp" 2>/dev/null; then
        mv "$tmp" "$abs_output"
        final_dims="$expected_dims"
        printf 'returned: %s -> downscaled: %s (via ffmpeg)\n' "$actual_dims" "$expected_dims"
      else
        rm -f "$tmp"
        printf 'image-skill-advisory: ffmpeg downscale failed; left at %s\n' "$actual_dims" >&2
      fi
    else
      printf 'image-skill-advisory: returned %s, expected %s; install ffmpeg to auto-downscale\n' \
        "$actual_dims" "$expected_dims" >&2
    fi
  fi

  printf '{"status":"success","output_path":"%s","dimensions":"%s","http_code":200}\n' \
    "$(json_escape "$output_path")" "$final_dims"
}

# ---------------------------------------------------------------------------
# Subcommand: record
# ---------------------------------------------------------------------------
sub_record() {
  local tier="" model="" cost="" prompt="" output="" dims="" status="success"
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier=*)   tier="${1#--tier=}"; shift ;;
      --model=*)  model="${1#--model=}"; shift ;;
      --cost=*)   cost="${1#--cost=}"; shift ;;
      --prompt=*) prompt="${1#--prompt=}"; shift ;;
      --output=*) output="${1#--output=}"; shift ;;
      --dims=*)   dims="${1#--dims=}"; shift ;;
      --status=*) status="${1#--status=}"; shift ;;
      --tier|--model|--cost|--prompt|--output|--dims|--status)
        eval "${1#--}=\"${2:-}\""; shift 2 ;;
      *) printf '/image record: unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
  done

  for f in tier model prompt output; do
    eval "v=\$$f"
    if [ -z "${v:-}" ]; then
      printf '/image record: missing --%s\n' "$f" >&2
      exit 2
    fi
  done

  mkdir -p "$(dirname "$MANIFEST_PATH")"
  local ts session
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  session="${CLAUDE_SESSION_ID:-null}"

  # session_id needs to be quoted if non-null, bare null if absent
  local session_field
  if [ "$session" = "null" ]; then
    session_field='null'
  else
    session_field="\"$(json_escape "$session")\""
  fi

  printf '{"ts":"%s","session_id":%s,"tier":"%s","model":"%s","cost_usd":%s,"prompt":"%s","output_path":"%s","dimensions":"%s","status":"%s"}\n' \
    "$ts" \
    "$session_field" \
    "$tier" \
    "$model" \
    "${cost:-0}" \
    "$(json_escape "$prompt")" \
    "$(json_escape "$output")" \
    "${dims:-1024x1024}" \
    "$status" \
    >> "$MANIFEST_PATH"

  printf 'recorded: %s\n' "$output"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  prepare) shift; sub_prepare "$@" ;;
  exec)    shift; sub_exec    "$@" ;;
  record)  shift; sub_record  "$@" ;;
  ""|-h|--help)
    cat <<'EOF'
/image — AI image generation helper

Subcommands:
  prepare --tier=<draft|brand-text|brand-photo> [--name=<slug>] [--aspect=...] "<prompt>"
    Validate inputs, derive output path, print cost estimate, emit JSON
    envelope (stdout). Errors out on missing --tier, unset FAL_KEY, or
    invalid --name.

  exec --envelope=<prepare-shape-json>
    Consume the envelope, POST to fal.run REST (NOT MCP — see spec 088),
    download image to output_path, ffmpeg-downscale on dim drift if available.
    Emits a JSON receipt on stdout: {status, output_path, dimensions,
    http_code}.

  record --tier=X --model=Y --cost=Z --prompt="..." --output=path
         [--dims=1024x1024] [--status=success]
    Append a manifest line to assets/generated/.manifest.jsonl after exec
    finishes. Called by the agent post-exec, with envelope + exec-receipt
    values forwarded.

See .agent0/skills/image/SKILL.md for the full invocation flow and
.agent0/context/rules/image-gen.md for the capacity rule.
EOF
    [ -z "${1:-}" ] && exit 2 || exit 0
    ;;
  *)
    printf '/image error: unknown subcommand: %s\n' "$1" >&2
    printf 'Run with --help for usage.\n' >&2
    exit 2
    ;;
esac
