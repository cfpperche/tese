#!/usr/bin/env bash
# .agent0/tools/fal-rest.sh
#
# Shared, runtime-neutral primitives for fal.ai's async QUEUE REST API
# (https://fal.ai/docs/model-endpoints/queue). Deliberately NON-discoverable
# (lives under .agent0/tools/, not a skill dir) and carries ZERO image- or
# video-specific fields — callers pass the model id + a JSON body and get back
# raw fal responses. Spec 132 extracted this from the /image generation path so
# /video's generative mode can reuse it; a follow-up spec migrates /image onto
# it. See docs/specs/132-video-skill/ and debate.md § R4.
#
# Subcommands (all require FAL_KEY; REST auth is 'Key', NOT 'Bearer'):
#   run      --model=<id> (--body=<json> | --body-file=<path> | stdin)
#            POST https://fal.run/<model> → model output JSON (SYNCHRONOUS; no
#            request_id, no polling). Used by /image (spec 133).
#   submit   --model=<id> (--body=<json> | --body-file=<path> | stdin)
#            POST https://queue.fal.run/<model> → {request_id,status_url,response_url,...}
#   status   --model=<id> --request-id=<id>
#            GET  .../requests/<id>/status → {status: IN_QUEUE|IN_PROGRESS|COMPLETED, ...}
#   result   --model=<id> --request-id=<id>
#            GET  .../requests/<id>/response → model-specific output JSON
#   download --url=<url> --output=<abs-path>
#            Fetch a CDN asset URL to disk (two-hop: result JSON carries URLs).
#
# Each subcommand prints the raw fal JSON (submit/status/result) or a small
# status JSON (download) to stdout and exits 0 on HTTP 200; non-zero otherwise
# with the fal error body on stderr. No polling loop here — the caller owns
# cadence (the /video ledger drives submit→status→result as separate calls).

set -uo pipefail

QUEUE_BASE="https://queue.fal.run"
SYNC_BASE="https://fal.run"

die() { printf 'fal-rest: %s\n' "$1" >&2; exit "${2:-2}"; }

require_key() {
  [ -n "${FAL_KEY:-}" ] || die "FAL_KEY is not set (REST auth requires it)" 2
}

# read_body: resolve a JSON body from --body / --body-file / stdin
read_body() {
  local body="$1" body_file="$2"
  if [ -n "$body" ]; then printf '%s' "$body"; return 0; fi
  if [ -n "$body_file" ]; then cat "$body_file"; return 0; fi
  if [ ! -t 0 ]; then cat; return 0; fi
  printf '{}'
}

sub_submit() {
  local model="" body="" body_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model=*)     model="${1#--model=}"; shift ;;
      --body=*)      body="${1#--body=}"; shift ;;
      --body-file=*) body_file="${1#--body-file=}"; shift ;;
      --model)       model="${2:-}"; shift 2 ;;
      --body)        body="${2:-}"; shift 2 ;;
      --body-file)   body_file="${2:-}"; shift 2 ;;
      *) die "submit: unknown arg: $1" ;;
    esac
  done
  require_key
  [ -n "$model" ] || die "submit: --model=<id> required"
  local payload resp_file http_code
  payload="$(read_body "$body" "$body_file")"
  resp_file="$(mktemp)"
  http_code="$(curl -sS -o "$resp_file" -w '%{http_code}' \
    -X POST "$QUEUE_BASE/$model" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$payload" \
    --max-time 60 || printf '000')"
  if [ "$http_code" != "200" ]; then
    cat "$resp_file" >&2; printf '\n' >&2; rm -f "$resp_file"
    die "submit: HTTP $http_code" 1
  fi
  cat "$resp_file"; printf '\n'; rm -f "$resp_file"
}

sub_run() {
  # Synchronous fal endpoint (fal.run/<model>) — returns the model output
  # directly (no request_id, no polling). Used by /image (sync, ~1 min). Model-
  # agnostic: caller owns the request body and the response shape.
  local model="" body="" body_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model=*)     model="${1#--model=}"; shift ;;
      --body=*)      body="${1#--body=}"; shift ;;
      --body-file=*) body_file="${1#--body-file=}"; shift ;;
      --model)       model="${2:-}"; shift 2 ;;
      --body)        body="${2:-}"; shift 2 ;;
      --body-file)   body_file="${2:-}"; shift 2 ;;
      *) die "run: unknown arg: $1" ;;
    esac
  done
  require_key
  [ -n "$model" ] || die "run: --model=<id> required"
  local payload resp_file http_code
  payload="$(read_body "$body" "$body_file")"
  resp_file="$(mktemp)"
  http_code="$(curl -sS -o "$resp_file" -w '%{http_code}' \
    -X POST "$SYNC_BASE/$model" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$payload" \
    --max-time 300 || printf '000')"
  if [ "$http_code" != "200" ]; then
    cat "$resp_file" >&2; printf '\n' >&2; rm -f "$resp_file"
    die "run: HTTP $http_code" 1
  fi
  cat "$resp_file"; printf '\n'; rm -f "$resp_file"
}

sub_status() {
  local model="" rid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model=*)      model="${1#--model=}"; shift ;;
      --request-id=*) rid="${1#--request-id=}"; shift ;;
      --model)        model="${2:-}"; shift 2 ;;
      --request-id)   rid="${2:-}"; shift 2 ;;
      *) die "status: unknown arg: $1" ;;
    esac
  done
  require_key
  [ -n "$model" ] || die "status: --model required"
  [ -n "$rid" ] || die "status: --request-id required"
  local resp_file http_code
  resp_file="$(mktemp)"
  http_code="$(curl -sS -o "$resp_file" -w '%{http_code}' \
    "$QUEUE_BASE/$model/requests/$rid/status" \
    -H "Authorization: Key $FAL_KEY" --max-time 30 || printf '000')"
  if [ "$http_code" != "200" ]; then
    cat "$resp_file" >&2; printf '\n' >&2; rm -f "$resp_file"
    die "status: HTTP $http_code" 1
  fi
  cat "$resp_file"; printf '\n'; rm -f "$resp_file"
}

sub_result() {
  local model="" rid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model=*)      model="${1#--model=}"; shift ;;
      --request-id=*) rid="${1#--request-id=}"; shift ;;
      --model)        model="${2:-}"; shift 2 ;;
      --request-id)   rid="${2:-}"; shift 2 ;;
      *) die "result: unknown arg: $1" ;;
    esac
  done
  require_key
  [ -n "$model" ] || die "result: --model required"
  [ -n "$rid" ] || die "result: --request-id required"
  local resp_file http_code
  resp_file="$(mktemp)"
  http_code="$(curl -sS -o "$resp_file" -w '%{http_code}' \
    "$QUEUE_BASE/$model/requests/$rid/response" \
    -H "Authorization: Key $FAL_KEY" --max-time 60 || printf '000')"
  if [ "$http_code" != "200" ]; then
    cat "$resp_file" >&2; printf '\n' >&2; rm -f "$resp_file"
    die "result: HTTP $http_code" 1
  fi
  cat "$resp_file"; printf '\n'; rm -f "$resp_file"
}

sub_download() {
  local url="" output=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --url=*)    url="${1#--url=}"; shift ;;
      --output=*) output="${1#--output=}"; shift ;;
      --url)      url="${2:-}"; shift 2 ;;
      --output)   output="${2:-}"; shift 2 ;;
      *) die "download: unknown arg: $1" ;;
    esac
  done
  [ -n "$url" ] || die "download: --url required"
  [ -n "$output" ] || die "download: --output required"
  mkdir -p "$(dirname "$output")"
  if ! curl -sS -o "$output" --max-time 300 "$url"; then
    die "download: fetch failed from $url" 1
  fi
  [ -s "$output" ] || die "download: empty file at $output" 1
  printf '{"status":"success","output":"%s"}\n' "$output"
}

case "${1:-}" in
  run)      shift; sub_run      "$@" ;;
  submit)   shift; sub_submit "$@" ;;
  status)   shift; sub_status "$@" ;;
  result)   shift; sub_result "$@" ;;
  download) shift; sub_download "$@" ;;
  ""|-h|--help)
    cat <<'EOF'
fal-rest.sh — shared fal.ai REST primitives (runtime-neutral, curl+jq)

  run      --model=<id> [--body=<json> | --body-file=<path> | stdin]   (sync fal.run)
  submit   --model=<id> [--body=<json> | --body-file=<path> | stdin]   (async queue.fal.run)
  status   --model=<id> --request-id=<id>
  result   --model=<id> --request-id=<id>
  download --url=<url> --output=<abs-path>

Requires FAL_KEY. Auth header is 'Authorization: Key $FAL_KEY' (REST, not Bearer).
`run` is synchronous (returns model output directly); `submit`/`status`/`result`
drive the async queue. No polling loop — callers drive cadence.
EOF
    [ -z "${1:-}" ] && exit 0 || exit 0 ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
