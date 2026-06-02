#!/usr/bin/env bash
# .agent0/skills/video/scripts/code.sh
#
# Deterministic mode of /video. Renders an HTML/CSS/JS composition to MP4 via
# the pinned HyperFrames npm ENGINE (debate R1: we depend on the engine, we OWN
# the authoring layer — we do NOT install the upstream agent-skill). Zero
# inference cost. Source is tracked; rendered MP4 is gitignored/regenerable; a
# render fingerprint lands in the manifest (debate R3 — fields only, no
# drift-checker tool in v1).
#
# Subcommands:
#   doctor               wrap `hyperframes doctor` (dep check: Node/ffmpeg/Chrome)
#   scaffold <slug>      copy the owned composition template → assets/video/compositions/<slug>/
#   render <slug> [--name=<out-slug>]
#                        render the composition → assets/generated/videos/<date>-<slug>.mp4
#                        + append a fingerprinted manifest line
#
# Capacity rule: .agent0/context/rules/video-gen.md

set -uo pipefail

HF_PIN="0.6.64"   # pinned HyperFrames engine (pre-1.0 — bump deliberately via refresh routine)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$SKILL_DIR/references/composition-template"
COMP_ROOT="$PROJECT_DIR/assets/video/compositions"
OUT_DIR="$PROJECT_DIR/assets/generated/videos"
MANIFEST="$PROJECT_DIR/assets/generated/.video-manifest.jsonl"

die() { printf '/video code: %s\n' "$1" >&2; exit "${2:-2}"; }

die_no_deps() {
  cat >&2 <<EOF
/video --mode=code error: $1

Code mode renders locally and needs:
  - Node.js 22+        (for npx hyperframes@$HF_PIN)
  - FFmpeg + FFprobe   (encode)
  - Headless Chrome    (capture; hyperframes manages a puppeteer copy)

Run \`bash .agent0/skills/video/scripts/code.sh doctor\` to diagnose.
See .agent0/context/rules/video-gen.md § Activation (code mode).
EOF
  exit 2
}

require_toolchain() {
  command -v node >/dev/null 2>&1 || die_no_deps "node not found on PATH"
  command -v npx  >/dev/null 2>&1 || die_no_deps "npx not found on PATH"
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])'
}

sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

sub_doctor() {
  require_toolchain
  printf '/video code: running hyperframes@%s doctor...\n' "$HF_PIN"
  npx --yes "hyperframes@$HF_PIN" doctor
}

sub_scaffold() {
  local slug="${1:-}"
  [ -n "$slug" ] || die "scaffold: <slug> required"
  case "$slug" in
    [a-z]*) : ;;
    *) die "scaffold: slug must be kebab-case (^[a-z][a-z0-9-]*$)" ;;
  esac
  case "$slug" in (*[!a-z0-9-]*) die "scaffold: slug must be kebab-case (^[a-z][a-z0-9-]*$)";; esac

  local dest="$COMP_ROOT/$slug"
  [ -e "$dest" ] && die "scaffold: $dest already exists (pick another slug or edit it)"
  [ -d "$TEMPLATE_DIR" ] || die "scaffold: owned template missing at $TEMPLATE_DIR"

  mkdir -p "$dest"
  cp "$TEMPLATE_DIR"/index.html "$TEMPLATE_DIR"/hyperframes.json "$TEMPLATE_DIR"/package.json "$dest/"
  # meta.json carries the slug (createdAt from bash date — scripts can't use Date.now)
  printf '{\n  "id": "%s",\n  "name": "%s",\n  "createdAt": "%s"\n}\n' \
    "$slug" "$slug" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dest/meta.json"

  printf 'scaffolded: %s\n' "${dest#"$PROJECT_DIR/"}"
  printf 'edit %s/index.html (see .agent0/skills/video/references/authoring.md), then:\n' "${dest#"$PROJECT_DIR/"}"
  printf '  /video --mode=code render %s\n' "$slug"
}

sub_render() {
  local slug="" out_slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name=*) out_slug="${1#--name=}"; shift ;;
      --name)   out_slug="${2:-}"; shift 2 ;;
      -*) die "render: unknown flag: $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "render: unexpected arg: $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "render: <slug> required"
  require_toolchain

  local comp_dir="$COMP_ROOT/$slug"
  local src="$comp_dir/index.html"
  [ -f "$src" ] || die "render: composition not found at ${src#"$PROJECT_DIR/"} (scaffold first)"

  out_slug="${out_slug:-$slug}"
  mkdir -p "$OUT_DIR"
  local out_rel="assets/generated/videos/$(date -u +%Y-%m-%d)-$out_slug.mp4"
  local out_abs="$PROJECT_DIR/$out_rel"

  printf '/video code: rendering %s via hyperframes@%s (no inference cost)...\n' "$slug" "$HF_PIN"
  local rc=0
  ( cd "$comp_dir" && npx --yes "hyperframes@$HF_PIN" render -o "$out_abs" ) || rc=$?

  if [ "$rc" -ne 0 ] || [ ! -s "$out_abs" ]; then
    sub_record_internal "$slug" "${src#"$PROJECT_DIR/"}" "$out_rel" "" "" failure
    die "render: hyperframes render failed (rc=$rc)" 1
  fi

  # Render fingerprint (debate R3 — fields, not a drift-checker). Captures the
  # render environment so a future reviewer can tell whether committed source
  # still matches the last MP4. Does NOT prevent cross-machine drift.
  local src_sha out_sha ffmpeg_v node_v vw vh viewport duration
  src_sha="$(sha256 "$src")"
  out_sha="$(sha256 "$out_abs")"
  ffmpeg_v="$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')"
  node_v="$(node --version 2>/dev/null)"
  # data-width / data-height may sit on separate lines — extract independently.
  vw="$(grep -oE 'data-width="[0-9]+"' "$src" | head -1 | grep -oE '[0-9]+')"
  vh="$(grep -oE 'data-height="[0-9]+"' "$src" | head -1 | grep -oE '[0-9]+')"
  viewport="${vw:-?}x${vh:-?}"
  duration="$(grep -oE 'data-duration="[0-9.]+"' "$src" | head -1 | grep -oE '[0-9.]+')"

  sub_record_internal "$slug" "${src#"$PROJECT_DIR/"}" "$out_rel" \
    "$(printf '{"hf_version":"%s","source_sha256":"%s","output_sha256":"%s","ffmpeg":"%s","node":"%s","viewport":"%s","duration":"%s","render_cmd":"npx hyperframes@%s render"}' \
        "$HF_PIN" "$src_sha" "$out_sha" "$ffmpeg_v" "$node_v" "${viewport:-unknown}" "${duration:-unknown}" "$HF_PIN")" \
    "" success

  printf 'rendered: %s\n' "$out_rel"
  printf 'source (tracked): %s\n' "${src#"$PROJECT_DIR/"}"
}

# sub_record_internal slug source_path output_path fingerprint_json prompt status
sub_record_internal() {
  local slug="$1" source_path="$2" output_path="$3" fingerprint="$4" prompt="$5" status="$6"
  mkdir -p "$(dirname "$MANIFEST")"
  local ts session session_field fp_field
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  session="${CLAUDE_SESSION_ID:-null}"
  if [ "$session" = "null" ]; then session_field='null'; else session_field="\"$(json_escape "$session")\""; fi
  if [ -z "$fingerprint" ]; then fp_field='null'; else fp_field="$fingerprint"; fi
  printf '{"ts":"%s","session_id":%s,"mode":"code","slug":"%s","source_path":"%s","output_path":"%s","fingerprint":%s,"status":"%s"}\n' \
    "$ts" "$session_field" "$slug" "$(json_escape "$source_path")" "$(json_escape "$output_path")" "$fp_field" "$status" >> "$MANIFEST"
}

case "${1:-}" in
  doctor)   shift; sub_doctor "$@" ;;
  scaffold) shift; sub_scaffold "$@" ;;
  render)   shift; sub_render "$@" ;;
  ""|-h|--help)
    cat <<EOF
/video code.sh — deterministic mode (HyperFrames engine, pinned @$HF_PIN)

  doctor               check local deps (Node/ffmpeg/Chrome)
  scaffold <slug>      create assets/video/compositions/<slug>/ from the owned template
  render <slug> [--name=<out>]
                       render → assets/generated/videos/<date>-<slug>.mp4 + fingerprint

Source is tracked; MP4 is gitignored/regenerable. See video-gen.md.
EOF
    [ -z "${1:-}" ] && exit 0 || exit 0 ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
