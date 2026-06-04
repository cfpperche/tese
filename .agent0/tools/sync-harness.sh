#!/usr/bin/env bash
# .agent0/tools/sync-harness.sh
# One-way sync of upstream harness state into a consumer project.
# See .agent0/context/rules/harness-sync.md for the full discipline.

set -euo pipefail

# Capture the original invocation args before the parse loop consumes them —
# the self-rebootstrap re-exec forwards them verbatim.
ORIGINAL_ARGS=("$@")

# ---------------------------------------------------------------------------
# usage / arg parsing
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
sync-harness.sh — one-way Agent0 -> consumer project harness sync

Usage:
  sync-harness.sh [--check|--apply] [--dry-run] [--force]
                  [--force-except=GLOB[,GLOB...]]
                  [--agent0-path=PATH] <consumer-path>

Modes:
  --check                read-only drift listing (default)
  --apply                write changes
  --dry-run              with --apply, emit decisions without writing
  --force                overwrite consumer-customized files (warned)
  --force-except=GLOB    comma-separated globs; matching files keep their
                         customization (refused) even under --force

Source:
  --agent0-path=PATH   absolute path to Agent0 source repo
  AGENT0_HARNESS_PATH  env-var fallback

Target:
  <consumer-path>          positional, required

Exit codes:
  0  clean (check: no drift; apply: success)
  1  drift detected (check) or customizations refused (apply without --force)
  2  usage error (missing source path, bad flags, etc.)
EOF
}

MODE="check"
DRY_RUN=0
FORCE=0
FORCE_EXCEPT=""
AGENT0_ARG=""
CONSUMER_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --force-except=*) FORCE_EXCEPT="${1#--force-except=}" ;;
    --force-except)
      shift
      FORCE_EXCEPT="${1:-}"
      ;;
    --agent0-path=*)  AGENT0_ARG="${1#--agent0-path=}" ;;
    --agent0-path)
      shift
      AGENT0_ARG="${1:-}"
      ;;
    -h|--help) usage; exit 0 ;;
    --*)
      printf 'sync-harness: unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$CONSUMER_ARG" ]; then
        CONSUMER_ARG="$1"
      else
        printf 'sync-harness: unexpected extra positional arg: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
  shift
done

if [ -z "$CONSUMER_ARG" ]; then
  printf 'sync-harness: missing <consumer-path>\n' >&2
  usage >&2
  exit 2
fi

# Resolve Agent0 source: explicit arg wins, then env var, then refuse.
if [ -n "$AGENT0_ARG" ]; then
  AGENT0_ROOT="$AGENT0_ARG"
elif [ -n "${AGENT0_HARNESS_PATH:-}" ]; then
  AGENT0_ROOT="$AGENT0_HARNESS_PATH"
else
  printf 'sync-harness: must specify --agent0-path=PATH or set AGENT0_HARNESS_PATH\n' >&2
  usage >&2
  exit 2
fi

CONSUMER_ROOT="$CONSUMER_ARG"

# Sanity: Agent0 looks like an Agent0 repo
if [ ! -d "$AGENT0_ROOT/.claude" ] || [ ! -f "$AGENT0_ROOT/CLAUDE.md" ]; then
  printf 'sync-harness: --agent0-path=%s does not look like an Agent0 repo (no .claude/ or CLAUDE.md)\n' "$AGENT0_ROOT" >&2
  exit 2
fi
if [ ! -d "$CONSUMER_ROOT" ]; then
  printf 'sync-harness: consumer project path does not exist: %s\n' "$CONSUMER_ROOT" >&2
  exit 2
fi

SYNC_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGED_BLOCK_LIB="$SYNC_HARNESS_DIR/lib/managed-block.sh"
if [ ! -f "$MANAGED_BLOCK_LIB" ] && [ -f "$AGENT0_ROOT/.agent0/tools/lib/managed-block.sh" ]; then
  MANAGED_BLOCK_LIB="$AGENT0_ROOT/.agent0/tools/lib/managed-block.sh"
fi
if [ ! -f "$MANAGED_BLOCK_LIB" ]; then
  printf 'sync-harness: missing managed-block helper library: %s\n' "$MANAGED_BLOCK_LIB" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$MANAGED_BLOCK_LIB"

# ---------------------------------------------------------------------------
# sync baseline
# ---------------------------------------------------------------------------

# The recorded sync baseline lives in the consumer project at
# .agent0/harness-sync-baseline.json and captures Agent0's managed-file sha-set
# as of the consumer project's last --apply. It is the third reference point that lets the
# plain-file path tell *stale* (auto-update) apart from *customized* (refuse),
# and lets the deletion pass propagate upstream removals safely. Git-tracked in
# the consumer project (travels on clone); never shipped by Agent0 itself.
# Spec 130 relocated it from .claude/ to .agent0/ (the harness-home for runtime-neutral
# artifacts); LEGACY_BASELINE_FILE is the pre-130 path, read as a fallback and removed
# on the migrating --apply.
BASELINE_TOOL_VERSION=1
BASELINE_FILE="$CONSUMER_ROOT/.agent0/harness-sync-baseline.json"
LEGACY_BASELINE_FILE="$CONSUMER_ROOT/.claude/harness-sync-baseline.json"
BASELINE_PRESENT=0
# spec 131 — consumer-owned project core, mirrored into both entrypoints.
# Deliberately NOT in any COPY_CHECK_* array: the source is consumer-owned and
# outside the sync manifest, so Agent0 never ships or overwrites it.
PROJECT_SOURCE_REL=".agent0/project-core.md"
PROJECT_MARKER="AGENT0:PROJECT"
BASELINE_TSV=""          # temp: sorted "relpath<TAB>sha" of the recorded baseline
MANIFEST_RAW=""          # temp: unsorted "relpath<TAB>sha" of Agent0's current set
MANIFEST_TSV=""          # temp: sorted+uniq MANIFEST_RAW
# Temp copy this process was re-exec'd from (self-rebootstrap path); empty
# in a normal run. Cleaned up here so the re-exec'd process removes its own
# source on exit — no separate trap needed.
REBOOTSTRAP_TMP="${AGENT0_SYNC_REBOOTSTRAP_TMP:-}"

_sync_cleanup() {
  rm -f "$BASELINE_TSV" "$MANIFEST_RAW" "$MANIFEST_TSV" "$REBOOTSTRAP_TMP" 2>/dev/null || true
}
trap _sync_cleanup EXIT

MANIFEST_RAW="$(mktemp -t sync-manifest-raw-XXXXXX)"
MANIFEST_TSV="$(mktemp -t sync-manifest-XXXXXX)"

# ---------------------------------------------------------------------------
# manifest
# ---------------------------------------------------------------------------

# Project-local paths — MUST NOT be added to any COPY_CHECK array below.
# .agent0/.browser-state/  session credentials (cookies/localStorage); project-specific,
#                           gitignored *.json, only .gitkeep sentinel travels via git.
# .agent0/memory/           project knowledge; content is project-local.
#                           The empty .gitkeep IS in COPY_CHECK_FILES — content is not.
# .agent0/routines/         project-scoped routine definitions; content is
#                           project-local. Only .gitkeep travels via git so a fresh
#                           consumer project has the empty directory ready for /routine new.
# .agent0/meetings/         project-scoped /meeting transcripts; content is
#                           project-local (a meeting is a durable deliberation record,
#                           not harness machinery). Only .gitkeep travels via git so a
#                           fresh consumer project has the empty directory ready.

# Recursive globs (find -type f under base dir) — encoded as "base/**"
COPY_CHECK_RECURSIVE=(
  ".claude/skills"
  ".agent0/context"
  ".agent0/skills"
  ".agent0/tests"
  ".claude/agents"
)

# Single-level globs (find -maxdepth 1 with name pattern) — encoded as "dir|pattern"
COPY_CHECK_GLOBS=(
  ".claude/hooks|*.sh"
  ".agent0/validators|*.sh"
  ".agent0/hooks|*.sh"
  ".agent0/tools|*.sh"
  ".agent0/tools|memory-*"
  ".agent0/tools|context-retrieve-*"
)

# Literal files
COPY_CHECK_FILES=(
  "AGENTS.md"
  ".mcp.json.example"
  ".codex/hooks.json"
  ".codex/config.toml.example"
  ".gitleaks.toml"
  ".githooks/pre-commit"
  ".agent0/tools/lib/managed-block.sh"
  ".agent0/memory/.gitkeep"
  ".agent0/skills/.gitkeep"
  ".agents/skills/.gitkeep"
  ".agent0/memory.config.json"
  ".agent0/.browser-state/.gitkeep"
  ".agent0/routines/.gitkeep"
  ".agent0/meetings/.gitkeep"
  ".agent0/.runtime-state/README.md"
  "assets/.gitkeep"
  "assets/brand/.gitkeep"
  "assets/generated/.gitkeep"
  "assets/generated/mockups/.gitkeep"
  "assets/video/.gitkeep"
  "assets/video/compositions/.gitkeep"
  "assets/generated/videos/.gitkeep"
)

# Path patterns excluded from propagation. Bash `case` globs anchored against
# the per-file relpath. Used for upstream-maintainer-bound capacities whose
# enforcement should not ship to leaf consumer projects — same posture as `.agent0/memory/`
# (content stays project-local). A path matching here is silently dropped from
# both the manifest record AND the per-file process: no copy, no baseline entry,
# no advisory. Companion filter in `merge_settings_json` drops the matching
# hook command from the settings merge so the registration is invisible too.
COPY_CHECK_EXCLUDE=(
  ".agent0/hooks/propagation-advise.sh"
  ".agent0/context/rules/propagation-advisory.md"
  ".agent0/tests/propagation-advisory/*"
  # Ephemeral OD-engine tarball-extraction cache (gitignored via
  # .../runtime/od-sync/.gitignore → extracted-*/). The git-aware walk already
  # excludes it (it is untracked); this entry is the always-applied backstop
  # that keeps a non-git source's degraded find() from re-leaking the cache.
  # See spec 144 (sync-harness-gitignore-aware-walk).
  "*/runtime/od-sync/extracted-*"
)

# Structured merge handled by dedicated functions below
# - .claude/settings.json
# - CLAUDE.md
# - .gitignore

# ---------------------------------------------------------------------------
# counters
# ---------------------------------------------------------------------------

COPIED=0
UP_TO_DATE=0
CUSTOMIZED_REFUSED=0
OVERWRITTEN=0
MERGED=0
DRIFT=0
STALE_UPDATED=0   # stale plain files auto-updated (consumer project == baseline, upstream moved)
REMOVED=0         # upstream-removed files deleted from the consumer project
CACHE_ORPHANS=0   # runtime-cache orphans removed (summarized, not listed per-file — spec 144)
LOCAL_ONLY=0      # consumer gitignores the .agent0/ harness tree; skip tracked-file writes
SKIPPED_TRACKED=0 # tracked write sites skipped under local-only mode

# Git-source detection + one-shot advisories for the git-aware walk (spec 144).
AGENT0_GIT_SOURCE=0
DIRTY_SOURCE_ADVISED=0
NONGIT_ADVISED=0

# ---------------------------------------------------------------------------
# copy / check
# ---------------------------------------------------------------------------

sha_of() {
  if [ -f "$1" ]; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

# Returns 0 if `rel` matches any glob in FORCE_EXCEPT (comma-separated), else 1.
matches_force_except() {
  local rel="$1"
  [ -z "$FORCE_EXCEPT" ] && return 1
  local IFS=','
  local pat
  for pat in $FORCE_EXCEPT; do
    [ -z "$pat" ] && continue
    case "$rel" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Returns 0 if `rel` matches any pattern in COPY_CHECK_EXCLUDE, else 1.
# Excluded paths are silently skipped by both record_manifest and process_file.
matches_exclude() {
  local rel="$1" pat
  for pat in "${COPY_CHECK_EXCLUDE[@]}"; do
    case "$rel" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Is this relpath an OD-engine runtime-cache file (spec 144)? Used by the
# deletion pass to summarize the one-time cleanup of over-propagated caches
# instead of emitting thousands of per-file removal lines.
is_runtime_cache() {
  case "$1" in
    */runtime/od-sync/extracted-*) return 0 ;;
  esac
  return 1
}

_is_local_only() {
  local root="$1" rel
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  for rel in ".agent0/skills" ".agent0/context" ".agent0/tools"; do
    git -C "$root" check-ignore -q -- "$rel" 2>/dev/null || return 1
  done
}

_consumer_tracks() {
  ! git -C "$CONSUMER_ROOT" check-ignore -q -- "$1" 2>/dev/null
}

_skip_tracked_local_only() {
  local rel="$1"
  if [ "$LOCAL_ONLY" -eq 1 ] && _consumer_tracks "$rel"; then
    SKIPPED_TRACKED=$((SKIPPED_TRACKED + 1))
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# baseline load + lookup
# ---------------------------------------------------------------------------

# Load the consumer project's recorded sync baseline (if present) into a sorted TSV temp
# file. One jq call dumps the .files map to "relpath<TAB>sha" lines; per-file
# lookup is then a Bash-3.2-safe awk scan (no declare -A). A malformed or
# unreadable baseline fails open — treated as no baseline.
load_baseline() {
  # Read the new location; fall back to the pre-130 legacy path when the new
  # one is absent (read-side migration — the next --apply rewrites at the new
  # path and removes the legacy file).
  local src="$BASELINE_FILE"
  if [ ! -f "$src" ] && [ -f "$LEGACY_BASELINE_FILE" ]; then
    src="$LEGACY_BASELINE_FILE"
  fi
  if [ ! -f "$src" ]; then
    BASELINE_PRESENT=0
    return
  fi
  BASELINE_TSV="$(mktemp -t sync-baseline-XXXXXX)"
  if jq -r '.files // {} | to_entries[] | "\(.key)\t\(.value)"' "$src" 2>/dev/null \
       | sort > "$BASELINE_TSV"; then
    BASELINE_PRESENT=1
  else
    printf '!! harness-sync-baseline.json unreadable/malformed — treating as no baseline\n' >&2
    BASELINE_PRESENT=0
  fi
}

# Echo the baseline sha recorded for a relpath, or empty string if absent.
# Exact-match the first tab-delimited field — no prefix-match footgun.
baseline_sha_for() {
  local rel="$1"
  if [ "$BASELINE_PRESENT" -ne 1 ]; then
    echo ""
    return
  fi
  awk -F'\t' -v k="$rel" '$1 == k { print $2; exit }' "$BASELINE_TSV"
}

# ---------------------------------------------------------------------------
# self-rebootstrap
# ---------------------------------------------------------------------------

# sync-harness.sh is itself in the propagation manifest, so an --apply against a
# consumer project whose copy is stale overwrites the very file bash is executing. Bash
# reads scripts incrementally; an in-place whole-file overwrite mid-run
# misaligns the read offset and corrupts execution. Guard: before any write, if
# this run WILL overwrite the consumer project's sync-harness.sh, re-exec from a stable temp
# copy of Agent0's current script — the re-exec'd process executes from the temp
# file, so overwriting the consumer project copy can no longer corrupt it. Must run after
# load_baseline (stale-vs-customized needs the baseline loaded).
_self_rebootstrap() {
  # Already re-exec'd from a stable copy — never loop.
  [ -n "${AGENT0_SYNC_REBOOTSTRAPPED:-}" ] && return 0
  # Only a real --apply writes; --check and --apply --dry-run never overwrite.
  [ "$MODE" = "apply" ] && [ "$DRY_RUN" -eq 0 ] || return 0

  local rel=".agent0/tools/sync-harness.sh"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"
  # No source, or consumer project has no copy → no in-place self-overwrite to guard.
  [ -f "$src" ] && [ -f "$dst" ] || return 0

  local src_sha dst_sha
  src_sha="$(sha_of "$src")"
  dst_sha="$(sha_of "$dst")"
  # Identical → the run leaves sync-harness.sh untouched.
  [ "$src_sha" = "$dst_sha" ] && return 0

  # Differs — will the run actually write it? stale auto-updates; customized is
  # written only under --force and not shielded by --force-except. A customized
  # self that will be refused is never overwritten, so it needs no rebootstrap.
  local baseline_sha will_overwrite=0
  baseline_sha="$(baseline_sha_for "$rel")"
  if [ -n "$baseline_sha" ] && [ "$baseline_sha" = "$dst_sha" ]; then
    will_overwrite=1
  elif [ "$FORCE" -eq 1 ] && ! matches_force_except "$rel"; then
    will_overwrite=1
  fi
  [ "$will_overwrite" -eq 1 ] || return 0

  # The run WILL overwrite our own running file — re-exec from a stable copy.
  local tmp
  tmp="$(mktemp -t sync-harness-rebootstrap-XXXXXX)" || return 0
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  printf 'sync-harness: self-update detected — re-executing from a stable copy\n' >&2
  export AGENT0_SYNC_REBOOTSTRAPPED=1
  export AGENT0_SYNC_REBOOTSTRAP_TMP="$tmp"
  exec bash "$tmp" "${ORIGINAL_ARGS[@]}"
}

# Entrypoints that may carry the consumer-owned AGENT0:PROJECT mirror region.
# (CLAUDE.md is handled by merge_claude_md, never process_file; AGENTS.md is the
# only plain-tracked entrypoint, but the set is kept general/future-proof.)
_is_project_target() {
  case "$1" in
    CLAUDE.md|AGENTS.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit a file's content with the AGENT0:PROJECT region (markers inclusive) and
# the single blank line immediately after END removed — the exact inverse of the
# insert in _mirror_project_region. Lets process_file compare AGENTS.md without
# counting the consumer-owned project-core region as Agent0-divergence. A file
# with no PROJECT region passes through byte-for-byte.
_strip_project_region() {
  local file="$1"
  awk '
    $0 == "<!-- AGENT0:PROJECT:BEGIN -->" { in_p=1; next }
    $0 == "<!-- AGENT0:PROJECT:END -->"   { in_p=0; skip_blank=1; next }
    in_p { next }
    skip_blank == 1 { skip_blank=0; if ($0 == "") next }
    { print }
  ' "$file"
}

process_file() {
  local rel="$1"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"

  if [ ! -f "$src" ]; then
    return
  fi
  if _skip_tracked_local_only "$rel"; then
    return
  fi

  if [ ! -f "$dst" ]; then
    # Missing in consumer project: copy.
    if [ "$MODE" = "check" ]; then
      printf '+ would copy %s\n' "$rel"
      DRIFT=1
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        printf '+ copied %s (dry-run)\n' "$rel"
      else
        mkdir -p "$(dirname "$dst")"
        cp -p "$src" "$dst"
        printf '+ copied %s\n' "$rel"
      fi
      COPIED=$((COPIED + 1))
    fi
    return
  fi

  local src_sha dst_sha
  if _is_project_target "$rel"; then
    # AGENTS.md may carry the consumer-owned AGENT0:PROJECT region (injected by
    # sync_project_core later in this same apply). Strip it before comparing so
    # the consumer-owned region never reads as Agent0-divergence. The write
    # paths below are unchanged: if a stale/force cp lands the region-less src,
    # sync_project_core re-injects the region afterward in the same run.
    src_sha="$(_strip_project_region "$src" | sha256sum | awk '{print $1}')"
    dst_sha="$(_strip_project_region "$dst" | sha256sum | awk '{print $1}')"
  else
    src_sha="$(sha_of "$src")"
    dst_sha="$(sha_of "$dst")"
  fi

  if [ "$src_sha" = "$dst_sha" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  # Hash mismatch — 3-way reconciliation: consumer project vs baseline vs Agent0.
  local baseline_sha
  baseline_sha="$(baseline_sha_for "$rel")"

  if [ -n "$baseline_sha" ] && [ "$baseline_sha" = "$dst_sha" ]; then
    # STALE: consumer project never touched this file since last sync; Agent0 moved on.
    # Auto-update — no --force needed.
    if [ "$MODE" = "check" ]; then
      printf '~ stale %s (would update)\n' "$rel"
      DRIFT=1
      return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '~ stale %s -> updated (dry-run)\n' "$rel"
    else
      cp -p "$src" "$dst"
      printf '~ stale %s -> updated\n' "$rel"
    fi
    STALE_UPDATED=$((STALE_UPDATED + 1))
    return
  fi

  # CUSTOMIZED: consumer project edited the file (baseline present but != consumer project copy), OR no
  # baseline entry exists (first sync / file added to manifest after the consumer project's
  # last sync — the genuine pre-baseline ambiguity). Refuse; --force overrides.
  local nobaseline=""
  if [ -z "$baseline_sha" ]; then
    nobaseline=" (no baseline)"
  fi

  if [ "$MODE" = "check" ]; then
    printf '!! customized %s%s\n' "$rel" "$nobaseline"
    DRIFT=1
    return
  fi

  if [ "$FORCE" -eq 1 ] && ! matches_force_except "$rel"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '! overwritten %s (dry-run)\n' "$rel" >&2
    else
      cp -p "$src" "$dst"
      printf '! overwritten %s\n' "$rel" >&2
    fi
    OVERWRITTEN=$((OVERWRITTEN + 1))
  else
    printf '!! customized %s%s\n' "$rel" "$nobaseline" >&2
    CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
  fi
}

# Append a managed file + its current Agent0 sha to the running manifest
#. The accumulated MANIFEST_TSV is consumed by the deletion pass
# (orphan detection) and the baseline write.
record_manifest() {
  local rel="$1"
  local src="$AGENT0_ROOT/$rel"
  if [ -f "$src" ]; then
    printf '%s\t%s\n' "$rel" "$(sha_of "$src")" >> "$MANIFEST_RAW"
  fi
}

# Is the Agent0 source a git work-tree? When it is, the two find-based manifest
# expansions filter to git-tracked files ("managed = tracked in Agent0"), which
# is what keeps gitignored runtime caches from propagating. When it is not (a
# tarball / archive export with no .git), the walk falls back to a guarded find
# — never blind: the COPY_CHECK_EXCLUDE runtime-cache backstop still applies.
# See spec 144. Sets AGENT0_GIT_SOURCE once per run.
detect_git_source() {
  if git -C "$AGENT0_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    AGENT0_GIT_SOURCE=1
  else
    AGENT0_GIT_SOURCE=0
  fi
}

# One-shot degraded-mode advisory for a non-git Agent0 source.
advise_nongit_once() {
  if [ "$NONGIT_ADVISED" -eq 0 ]; then
    printf 'harness-sync: advisory — Agent0 source is not a git work-tree; degraded walk (static runtime-cache exclusion only)\n' >&2
    NONGIT_ADVISED=1
  fi
}

# One-shot dirty-source advisory. The git-aware walk uses the git INDEX for the
# file-set but the WORKING TREE for content (consistent with the existing
# baseline, where sha_of reads disk and agent0_commit is a provenance
# breadcrumb, not a reproducibility contract). When the source is dirty under a
# managed root, that file-set/content pairing can diverge from HEAD — surface it
# (an unstaged deletion silently propagating a removal must be visible).
advise_dirty_once() {
  if [ "$DIRTY_SOURCE_ADVISED" -eq 0 ] && [ "$AGENT0_GIT_SOURCE" -eq 1 ]; then
    local -a paths=("${COPY_CHECK_RECURSIVE[@]}")
    local entry
    for entry in "${COPY_CHECK_GLOBS[@]}"; do
      paths+=("${entry%|*}")
    done
    if [ -n "$(git -C "$AGENT0_ROOT" status --porcelain -- "${paths[@]}" 2>/dev/null)" ]; then
      printf 'harness-sync: advisory — Agent0 source work-tree is dirty under managed roots; manifest uses the git index file-set with working-tree content\n' >&2
    fi
  fi
  DIRTY_SOURCE_ADVISED=1
  return 0
}

# Emit the file-set under a recursive base, NUL-delimited, relative to AGENT0_ROOT.
# git source → tracked files only; non-git source → guarded find.
emit_recursive_files() {
  local base="$1"
  if [ "$AGENT0_GIT_SOURCE" -eq 1 ]; then
    git -C "$AGENT0_ROOT" ls-files --cached -z -- "$base" 2>/dev/null
  else
    advise_nongit_once
    ( cd "$AGENT0_ROOT" && find "$base" -type f -print0 2>/dev/null )
  fi
}

# Emit maxdepth-1 files in `dir` whose basename matches shell `pattern`,
# NUL-delimited. git source → tracked files only (post-filtered to dir depth +
# pattern, no second find); non-git source → guarded find.
emit_glob_files() {
  local dir="$1" pattern="$2" f bn
  if [ "$AGENT0_GIT_SOURCE" -eq 1 ]; then
    while IFS= read -r -d '' f; do
      [ "$(dirname "$f")" = "$dir" ] || continue
      bn="$(basename "$f")"
      # shellcheck disable=SC2254 — pattern is an intentional glob from COPY_CHECK_GLOBS
      case "$bn" in
        $pattern) printf '%s\0' "$f" ;;
      esac
    done < <(git -C "$AGENT0_ROOT" ls-files --cached -z -- "$dir" 2>/dev/null)
  else
    advise_nongit_once
    ( cd "$AGENT0_ROOT" && find "$dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null )
  fi
}

walk_copy_check() {
  local base pattern dir relfile entry
  : > "$MANIFEST_RAW"

  detect_git_source
  advise_dirty_once

  for base in "${COPY_CHECK_RECURSIVE[@]}"; do
    if [ -d "$AGENT0_ROOT/$base" ]; then
      while IFS= read -r -d '' relfile; do
        [ -n "$relfile" ] || continue
        matches_exclude "$relfile" && continue
        record_manifest "$relfile"
        process_file "$relfile"
      done < <(emit_recursive_files "$base")
    fi
  done

  for entry in "${COPY_CHECK_GLOBS[@]}"; do
    dir="${entry%|*}"
    pattern="${entry#*|}"
    if [ -d "$AGENT0_ROOT/$dir" ]; then
      while IFS= read -r -d '' relfile; do
        [ -n "$relfile" ] || continue
        matches_exclude "$relfile" && continue
        record_manifest "$relfile"
        process_file "$relfile"
      done < <(emit_glob_files "$dir" "$pattern")
    fi
  done

  for relfile in "${COPY_CHECK_FILES[@]}"; do
    if matches_exclude "$relfile"; then
      continue
    fi
    record_manifest "$relfile"
    process_file "$relfile"
  done

  sort -u "$MANIFEST_RAW" > "$MANIFEST_TSV"
}

# ---------------------------------------------------------------------------
# deletion reconciliation
# ---------------------------------------------------------------------------

# Remove now-empty parent directories of a just-deleted file, bottom-up,
# stopping at the first non-empty dir. Never ascends past the consumer project root.
prune_empty_parents() {
  local rel="$1"
  local dir
  dir="$(dirname "$rel")"
  while [ -n "$dir" ] && [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -d "$CONSUMER_ROOT/$dir" ] && [ -z "$(ls -A "$CONSUMER_ROOT/$dir" 2>/dev/null)" ]; then
      rmdir "$CONSUMER_ROOT/$dir" 2>/dev/null || break
      dir="$(dirname "$dir")"
    else
      break
    fi
  done
}

# For every path in the recorded baseline NOT in Agent0's current manifest,
# propagate the upstream removal: delete clean orphans (consumer project copy still matches
# baseline), refuse consumer-customized ones (unless --force). Requires a baseline;
# first-sync consumer projects (no baseline) skip this pass entirely.
reconcile_deletions() {
  if [ "$BASELINE_PRESENT" -ne 1 ]; then
    return
  fi

  local manifest_paths
  manifest_paths="$(mktemp -t sync-mpaths-XXXXXX)"
  cut -f1 "$MANIFEST_TSV" | sort -u > "$manifest_paths"

  local rel baseline_sha dst dst_sha
  while IFS=$'\t' read -r rel baseline_sha; do
    if [ -z "$rel" ]; then
      continue
    fi
    # Still in Agent0's current manifest — not an orphan, handled by the walk.
    if grep -Fxq "$rel" "$manifest_paths"; then
      continue
    fi
    dst="$CONSUMER_ROOT/$rel"
    # Consumer project no longer has it — nothing to delete.
    if [ ! -f "$dst" ]; then
      continue
    fi
    if _skip_tracked_local_only "$rel"; then
      continue
    fi
    dst_sha="$(sha_of "$dst")"

    if [ "$dst_sha" = "$baseline_sha" ]; then
      # Clean orphan: consumer project copy untouched since sync — safe to remove.
      # Runtime-cache orphans (the spec-144 over-propagated extracted-* trees can
      # number in the thousands) are removed but summarized, not listed per-file.
      if is_runtime_cache "$rel"; then
        if [ "$MODE" = "check" ]; then
          DRIFT=1
        elif [ "$DRY_RUN" -eq 1 ]; then
          REMOVED=$((REMOVED + 1))
        else
          rm -f "$dst"
          prune_empty_parents "$rel"
          REMOVED=$((REMOVED + 1))
        fi
        CACHE_ORPHANS=$((CACHE_ORPHANS + 1))
        continue
      fi
      if [ "$MODE" = "check" ]; then
        printf -- '- removed %s (would delete)\n' "$rel"
        DRIFT=1
      elif [ "$DRY_RUN" -eq 1 ]; then
        printf -- '- removed %s (dry-run)\n' "$rel"
        REMOVED=$((REMOVED + 1))
      else
        rm -f "$dst"
        prune_empty_parents "$rel"
        printf -- '- removed %s\n' "$rel"
        REMOVED=$((REMOVED + 1))
      fi
      continue
    fi

    # Consumer project customized a file Agent0 has since removed — never silently delete
    # consumer project work. Refuse and advise manual resolution; --force overrides.
    if [ "$MODE" = "check" ]; then
      printf '!! customized %s (upstream-removed)\n' "$rel"
      DRIFT=1
    elif [ "$FORCE" -eq 1 ] && ! matches_force_except "$rel"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        printf -- '! removed %s (customized, upstream-removed, --force, dry-run)\n' "$rel" >&2
      else
        rm -f "$dst"
        prune_empty_parents "$rel"
        printf -- '! removed %s (customized, upstream-removed, --force)\n' "$rel" >&2
      fi
      REMOVED=$((REMOVED + 1))
    else
      printf '!! customized %s (upstream-removed — resolve manually)\n' "$rel" >&2
      CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    fi
  done < "$BASELINE_TSV"

  # Summarize the runtime-cache orphan removals (spec 144) — one line, not N.
  if [ "$CACHE_ORPHANS" -gt 0 ]; then
    if [ "$MODE" = "check" ]; then
      printf -- '- removed %s runtime-cache orphans under runtime/od-sync/extracted-* (would delete)\n' "$CACHE_ORPHANS"
    elif [ "$DRY_RUN" -eq 1 ]; then
      printf -- '- removed %s runtime-cache orphans under runtime/od-sync/extracted-* (dry-run)\n' "$CACHE_ORPHANS"
    else
      printf -- '- removed %s runtime-cache orphans under runtime/od-sync/extracted-*\n' "$CACHE_ORPHANS"
    fi
  fi

  rm -f "$manifest_paths"
}

# ---------------------------------------------------------------------------
# baseline write
# ---------------------------------------------------------------------------

# Remove the pre-130 legacy baseline (.claude/) once the new (.agent0/) one is
# written or confirmed current. Apply-only (callers are already past the
# check/dry-run guard); safe no-op when the legacy file is already gone. The
# removal surfaces in the consumer's git diff as the migration record.
_remove_legacy_baseline() {
  if [ -f "$LEGACY_BASELINE_FILE" ]; then
    if _skip_tracked_local_only ".claude/harness-sync-baseline.json"; then
      return
    fi
    rm -f "$LEGACY_BASELINE_FILE"
    printf -- '- baseline migrated (removed legacy .claude/harness-sync-baseline.json)\n' >&2
  fi
}

# Record Agent0's current managed-file sha-set as the consumer project's new sync baseline.
# Runs only on --apply (not --check, not --dry-run). Skipped when the resulting
# files-map is byte-identical to the existing baseline's — a no-op re-sync must
# leave the file untouched (idempotency), so synced_at is not churned. Atomic
# write via mktemp + mv, mirroring merge_settings_json.
write_baseline() {
  if [ "$MODE" != "apply" ] || [ "$DRY_RUN" -eq 1 ]; then
    return
  fi
  if [ ! -f "$MANIFEST_TSV" ]; then
    return
  fi

  local files_obj
  files_obj="$(jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t") | {(.[0]): .[1]}) | add // {}
  ' "$MANIFEST_TSV" 2>/dev/null || echo '{}')"

  # Idempotency: if the existing baseline already records this exact files-map,
  # leave the file untouched (a rewrite would only bump synced_at).
  if [ -f "$BASELINE_FILE" ]; then
    local old_files new_files
    old_files="$(jq -S -c '.files // {}' "$BASELINE_FILE" 2>/dev/null || echo '')"
    new_files="$(printf '%s' "$files_obj" | jq -S -c '.' 2>/dev/null || echo '')"
    if [ -n "$old_files" ] && [ "$old_files" = "$new_files" ]; then
      printf '= baseline up-to-date .agent0/harness-sync-baseline.json\n' >&2
      _remove_legacy_baseline
      return
    fi
  fi

  local agent0_commit synced_at tmp files_tmp
  agent0_commit="$(cd "$AGENT0_ROOT" 2>/dev/null && git rev-parse HEAD 2>/dev/null || true)"
  synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp -t sync-baseline-write-XXXXXX)"
  # Pass the files-map through a temp file via --slurpfile, NOT a --argjson
  # command-line argument: a large consumer's files-map (~1000+ files) exceeds
  # Linux MAX_ARG_STRLEN (~128 KB per single argv string) and execve fails with
  # E2BIG ("Argument list too long"). --slurpfile reads from a file (no argv
  # limit). See harness-sync test 41. ($files is a 1-element array → $files[0].)
  files_tmp="$(mktemp -t sync-baseline-files-XXXXXX)"
  printf '%s' "$files_obj" > "$files_tmp"

  if jq -n \
       --slurpfile files "$files_tmp" \
       --arg commit "$agent0_commit" \
       --arg synced "$synced_at" \
       --argjson ver "$BASELINE_TOOL_VERSION" \
       '{
          agent0_commit: (if $commit == "" then null else $commit end),
          synced_at: $synced,
          tool_version: $ver,
          files: ($files[0] // {})
        }' > "$tmp" 2>/dev/null; then
    mkdir -p "$(dirname "$BASELINE_FILE")"
    mv "$tmp" "$BASELINE_FILE"
    printf '~ baseline recorded .agent0/harness-sync-baseline.json\n' >&2
    _remove_legacy_baseline
  else
    rm -f "$tmp"
    printf '!! failed to write .agent0/harness-sync-baseline.json (jq error)\n' >&2
  fi
  rm -f "$files_tmp"
}

# ---------------------------------------------------------------------------
# settings.json structured merge
# ---------------------------------------------------------------------------

merge_settings_json() {
  local rel=".claude/settings.json"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"

  if [ ! -f "$src" ]; then
    return
  fi
  if _skip_tracked_local_only "$rel"; then
    return
  fi

  # The dev-only propagation-advise.sh registration must never reach a consumer.
  # strip_excluded (in the jq below) drops it — but the strip lives INSIDE the
  # merge, so EVERY path to settings.json must flow through that jq, including a
  # first sync where the consumer has no file yet. Two earlier short-circuits
  # bypassed it: a missing consumer file fell back to a verbatim process_file
  # copy, and a sha-identical file returned "up to date" before the jq ran. Both
  # leaked (then permanently persisted) the registration. Now the consumer side
  # is always normalized through jq — an absent file becomes an empty base ({}) —
  # and the only up-to-date test is merged-vs-consumer, so a previously leaked
  # registration self-heals on the next resync.
  local first_sync=0 consumer_base
  consumer_base="$(mktemp -t sync-settings-base-XXXXXX)"
  if [ -f "$dst" ]; then
    cp "$dst" "$consumer_base"
  else
    first_sync=1
    printf '{}' > "$consumer_base"
  fi

  # Compute merged JSON.
  # Consumer project (consumer_base) is the BASE — preserves permissions/env/model/statusLine/consumer-only top-level keys.
  # Agent0-owned top-level keys ($schema) overwrite when Agent0 has them.
  # hooks: union per-event, dedup by (matcher, ordered list of inner commands).
  # Excluded hook commands (matched as substring on any inner .command) are dropped
  # from BOTH sides — companion to COPY_CHECK_EXCLUDE, makes propagation-advise.sh
  # registration invisible to consumer projects even if a prior sync leaked it. Substring match
  # is anchored only by hook-file basename, so command shape (`bash $CLAUDE_PROJECT_DIR/...`)
  # variants all match.
  local tmp merged
  tmp="$(mktemp -t sync-settings-XXXXXX)"
  if ! jq -s '
    def dedup_key:
      (.matcher // "") + "|" + ((.hooks // []) | map(.command // "") | join("##"));

    def is_excluded:
      any(.hooks[]?; (.command // "") | contains("propagation-advise.sh"));

    def strip_excluded:
      map(select(is_excluded | not));

    . as $arr |
    ($arr[0] // {}) as $consumer |
    ($arr[1] // {}) as $agent0 |
    $consumer
    | (if ($agent0 | has("$schema"))    then .["$schema"]  = $agent0["$schema"]  else . end)
    | .hooks = (
        ((($consumer.hooks // {}) | keys) + (($agent0.hooks // {}) | keys))
        | unique
        | map(. as $k | {
            ($k): (((($consumer.hooks[$k]) // []) | strip_excluded)
                 + ((($agent0.hooks[$k]) // []) | strip_excluded)
                 | unique_by(dedup_key))
          })
        | add // {}
      )
  ' "$consumer_base" "$src" > "$tmp" 2>/dev/null; then
    printf '!! settings.json merge failed (jq error)\n' >&2
    rm -f "$tmp" "$consumer_base"
    DRIFT=1
    return
  fi
  rm -f "$consumer_base"

  # Up-to-date test: merged result vs current consumer content. dst_sha is empty
  # when the consumer has no settings.json (first sync) — never equals merged.
  local merged_sha dst_sha
  merged_sha="$(sha_of "$tmp")"
  dst_sha="$(sha_of "$dst")"
  if [ "$merged_sha" = "$dst_sha" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    rm -f "$tmp"
    return
  fi

  if [ "$MODE" = "check" ]; then
    if [ "$first_sync" -eq 1 ]; then
      printf '+ would copy %s\n' "$rel"
    else
      printf '~ would merge %s\n' "$rel"
    fi
    DRIFT=1
    rm -f "$tmp"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$first_sync" -eq 1 ]; then
      printf '+ copied %s (dry-run)\n' "$rel"
    else
      printf '~ merged %s (dry-run)\n' "$rel"
    fi
    rm -f "$tmp"
  else
    mkdir -p "$(dirname "$dst")"
    mv "$tmp" "$dst"
    if [ "$first_sync" -eq 1 ]; then
      printf '+ copied %s\n' "$rel"
    else
      printf '~ merged %s\n' "$rel"
    fi
  fi
  if [ "$first_sync" -eq 1 ]; then
    COPIED=$((COPIED + 1))
  else
    MERGED=$((MERGED + 1))
  fi
}

# ---------------------------------------------------------------------------
# CLAUDE.md capacity-section append
# ---------------------------------------------------------------------------

# Extract section headings ("^## <Title>") from a file, one per line.
extract_h2() {
  grep -E '^## ' "$1" || true
}

# Extract the body of a specific section (from "## Title" through to next "## " or EOF).
extract_section() {
  local file="$1"
  local title="$2"
  awk -v t="$title" '
    BEGIN { in_sec = 0 }
    /^## / {
      if (in_sec) exit
      if ($0 == t) in_sec = 1
    }
    { if (in_sec) print }
  ' "$file"
}

# Record CLAUDE.md's Agent0-managed block (between AGENT0:BEGIN/END) as a
# baseline-tracked unit under the synthetic key "CLAUDE.md#managed-block" — `#`
# cannot appear in a real managed relpath, so no collision. Appended to the
# running manifest so write_baseline persists it and reconcile_deletions, which
# only acts on baseline entries ABSENT from the manifest, never orphans it.
record_managed_block_manifest() {
  local src="$AGENT0_ROOT/CLAUDE.md"
  # return 0 on the skip paths — a bare `return` propagates the failed test's
  # exit code, which under `set -e` would abort main mid-run.
  [ -f "$src" ] || return 0
  [ "$(detect_marker_state "$src")" = "paired" ] || return 0
  printf '%s\t%s\n' "CLAUDE.md#managed-block" "$(_region_sha "$(_extract_region "$src")")" >> "$MANIFEST_RAW"
  sort -u "$MANIFEST_RAW" > "$MANIFEST_TSV"
}

# For each H2 heading in BOTH files (intersection), compare section bodies.
# Outputs diverged section titles, one per line.
_check_section_divergence() {
  local src="$1"
  local dst="$2"
  local src_h2 dst_h2 src_sorted dst_sorted common title src_body dst_body
  src_h2="$(extract_h2 "$src")"
  dst_h2="$(extract_h2 "$dst")"
  src_sorted="$(mktemp -t sync-srch2-XXXXXX)"
  dst_sorted="$(mktemp -t sync-dsth2-XXXXXX)"
  printf '%s\n' "$src_h2" | sort -u > "$src_sorted"
  printf '%s\n' "$dst_h2" | sort -u > "$dst_sorted"
  common="$(comm -12 "$src_sorted" "$dst_sorted")"
  rm -f "$src_sorted" "$dst_sorted"

  while IFS= read -r title; do
    [ -z "$title" ] && continue
    src_body="$(extract_section "$src" "$title")"
    dst_body="$(extract_section "$dst" "$title")"
    if [ "$src_body" != "$dst_body" ]; then
      printf '%s\n' "$title"
    fi
  done <<EOF
$common
EOF
}

# Section divergence scoped to the AGENT0 region (between markers) in both files.
_check_region_divergence() {
  local src="$1"
  local dst="$2"
  local src_tmp dst_tmp out
  src_tmp="$(mktemp -t sync-srcrgn-XXXXXX)"
  dst_tmp="$(mktemp -t sync-dstrgn-XXXXXX)"
  _extract_region "$src" > "$src_tmp"
  _extract_region "$dst" > "$dst_tmp"
  out="$(_check_section_divergence "$src_tmp" "$dst_tmp")"
  rm -f "$src_tmp" "$dst_tmp"
  printf '%s' "$out"
}

# Write a unified diff of consumer project region vs Agent0 region to .claude/CLAUDE.md.diverged-region.md.
_write_region_divergence_report() {
  local src="$1"
  local dst="$2"
  local diverged_titles="$3"
  local out="$CONSUMER_ROOT/.claude/CLAUDE.md.diverged-region.md"
  local title
  mkdir -p "$(dirname "$out")"
  {
    printf '# CLAUDE.md managed region divergence\n\n'
    printf '_Generated by sync-harness.sh on %s — consumer project region differs from Agent0 source._\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Body of one or more Agent0-titled sections in the managed region differs\n'
    printf 'between consumer project and Agent0 source. Resolve by either:\n\n'
    printf '1. Moving project customizations OUTSIDE the markers (above `<!-- AGENT0:BEGIN -->`).\n'
    printf '2. Accepting Agent0 replacement via `--force` (consumer project region overwritten wholesale).\n\n'
    if [ -n "$diverged_titles" ]; then
      printf '## Diverged sections\n\n'
      while IFS= read -r title; do
        [ -z "$title" ] && continue
        printf -- '- `%s`\n' "$title"
      done <<EOF
$diverged_titles
EOF
      printf '\n'
    fi
    printf '## Unified diff (consumer project → Agent0)\n\n'
    printf '```diff\n'
    diff -u <(_extract_region "$dst") <(_extract_region "$src") || true
    printf '```\n'
  } > "$out"
}

# Generate `.claude/CLAUDE.md.migration-candidate.md` showing the wrapped layout,
# OR `.claude/CLAUDE.md.diverged-sections.md` if section bodies diverged.
# No-op when Agent0 source is not wrapped (markers are the "Agent0-managed namespace"
# delimiter — without them, we can't tell project-narrative from capacity sections).
# Respects MODE=check (no writes) and DRY_RUN=1 (no writes, advisory only).
_generate_migration_candidate() {
  local rel="CLAUDE.md"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"
  local src_state diverged_titles count title

  # Candidate generation requires Agent0 source to be wrapped — the markers
  # define what's Agent0-managed vs project-narrative. Without them, every
  # H2 in src would be treated as Agent0-owned and project headings like
  # `## Overview` would falsely trip the divergence check.
  src_state="$(detect_marker_state "$src")"
  if [ "$src_state" != "paired" ]; then
    return
  fi

  # Compare consumer project sections against Agent0's REGION (managed namespace only).
  local src_region_tmp
  src_region_tmp="$(mktemp -t sync-srcrgn-XXXXXX)"
  _extract_region "$src" > "$src_region_tmp"
  diverged_titles="$(_check_section_divergence "$src_region_tmp" "$dst")"

  if [ -n "$diverged_titles" ]; then
    count="$(printf '%s\n' "$diverged_titles" | grep -c . || true)"
    if [ "$MODE" = "check" ] || [ "$DRY_RUN" -eq 1 ]; then
      printf 'claude-md-migration-blocked: %s sections diverged (drift only, --check/--dry-run: no report written)\n' "$count" >&2
      rm -f "$src_region_tmp"
      DRIFT=1
      return
    fi

    local report="$CONSUMER_ROOT/.claude/CLAUDE.md.diverged-sections.md"
    mkdir -p "$(dirname "$report")"
    {
      printf '# CLAUDE.md section divergence — migration blocked\n\n'
      printf '_Generated by sync-harness.sh on %s._\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'The consumer project rewrote the body of one or more Agent0-titled sections. Migration\n'
      printf 'to managed-block layout is blocked until these are resolved.\n\n'
      printf '## Diverged sections\n\n'
      while IFS= read -r title; do
        [ -z "$title" ] && continue
        printf -- '- `%s`\n' "$title"
      done <<EOF
$diverged_titles
EOF
      printf '\n## Resolution\n\n'
      printf '1. Per section: keep the consumer project edit (rename heading so it is no longer Agent0-titled),\n'
      printf '   OR accept the Agent0 body (overwrite consumer project edit).\n'
      printf '2. Apply the decisions in `CLAUDE.md` directly.\n'
      printf '3. Re-run sync; a fresh migration candidate is generated once divergences are gone.\n'
    } > "$report"
    printf 'claude-md-migration-blocked: %s sections diverged — see .claude/CLAUDE.md.diverged-sections.md\n' "$count" >&2
    rm -f "$src_region_tmp"
    return
  fi

  # No body divergence — generate candidate (or report-would in check/dry-run).
  if [ "$MODE" = "check" ] || [ "$DRY_RUN" -eq 1 ]; then
    printf 'claude-md-migration-advisory: would write candidate to .claude/CLAUDE.md.migration-candidate.md (--check/--dry-run: no file written)\n' >&2
    rm -f "$src_region_tmp"
    DRIFT=1
    return
  fi

  local candidate="$CONSUMER_ROOT/.claude/CLAUDE.md.migration-candidate.md"
  mkdir -p "$(dirname "$candidate")"

  local src_region_h2 dst_h2 project_only_titles src_sha_short
  src_region_h2="$(extract_h2 "$src_region_tmp")"
  dst_h2="$(extract_h2 "$dst")"
  # Project-only sections = headings in dst NOT in Agent0's region, preserving dst order.
  if [ -z "$src_region_h2" ]; then
    project_only_titles="$dst_h2"
  else
    project_only_titles="$(printf '%s\n' "$dst_h2" | grep -Fxv -f <(printf '%s\n' "$src_region_h2") || true)"
  fi
  src_sha_short="$(sha_of "$src" | cut -c1-12)"

  {
    printf '%s\n' '<!--'
    printf 'Migration candidate generated by sync-harness.sh on %s.\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Source: Agent0 CLAUDE.md (sha %s)\n' "$src_sha_short"
    printf '\n'
    printf 'Review this layout. If it matches your intent, run:\n'
    printf '  mv .claude/CLAUDE.md.migration-candidate.md CLAUDE.md\n'
    printf '\n'
    printf 'After ratification, subsequent syncs use the managed-block merge path: the\n'
    printf 'region between AGENT0:BEGIN and AGENT0:END is replaced wholesale on each\n'
    printf 'sync, propagating Agent0 ADDs and REMOVALs symmetrically.\n'
    printf '%s\n\n' '-->'

    # Preamble: lines before the first ## heading in consumer project (file H1, intro paragraphs).
    awk '/^## / {exit} {print}' "$dst"

    # Project-only sections from consumer project (preserving consumer project's order).
    while IFS= read -r title; do
      [ -z "$title" ] && continue
      extract_section "$dst" "$title"
      printf '\n'
    done <<EOF
$project_only_titles
EOF

    # AGENT0 region (sourced from Agent0's wrapped CLAUDE.md).
    printf '%s\n' '<!-- AGENT0:BEGIN -->'
    cat "$src_region_tmp"
    printf '%s\n' '<!-- AGENT0:END -->'
  } > "$candidate"

  rm -f "$src_region_tmp"
  printf 'claude-md-migration-advisory: candidate written to .claude/CLAUDE.md.migration-candidate.md — review and `mv` to ratify\n' >&2
}

# Handle paired-marker state: replace region wholesale, refuse on body divergence.
_merge_claude_md_managed_block() {
  local rel="CLAUDE.md"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"

  if matches_force_except "$rel"; then
    printf '!! force-except %s (merge skipped)\n' "$rel" >&2
    CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    return
  fi

  # Source must also be wrapped — fallback to legacy if not.
  local src_state
  src_state="$(detect_marker_state "$src")"
  if [ "$src_state" != "paired" ]; then
    printf '!! claude-md: Agent0 source CLAUDE.md is not wrapped (state=%s) — falling back to legacy merge\n' "$src_state" >&2
    _merge_claude_md_legacy
    return
  fi

  local src_region dst_region
  src_region="$(_extract_region "$src")"
  dst_region="$(_extract_region "$dst")"

  if [ "$src_region" = "$dst_region" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  # Region differs — 3-way reconciliation of the managed block as a single
  # baseline-tracked unit, reusing the per-file baseline machinery.
  # The AGENT0:BEGIN/END contract makes the whole block upstream-owned, so any
  # edit inside it is customization — no per-section granularity is needed.
  local region_baseline_sha dst_region_sha is_stale=0
  region_baseline_sha="$(baseline_sha_for "CLAUDE.md#managed-block")"
  dst_region_sha="$(_region_sha "$dst_region")"
  if [ -n "$region_baseline_sha" ] && [ "$region_baseline_sha" = "$dst_region_sha" ]; then
    is_stale=1
  fi

  if [ "$is_stale" -ne 1 ] && { [ "$FORCE" -ne 1 ] || matches_force_except "$rel"; }; then
    # CUSTOMIZED: consumer project edited its managed block (baseline present but != consumer project
    # region), OR no baseline entry yet (a pre-071 consumer project's first sync — the
    # genuine pre-baseline ambiguity). Refuse; --force overrides.
    local nobaseline=""
    [ -z "$region_baseline_sha" ] && nobaseline=" (no baseline)"
    if [ "$MODE" = "check" ]; then
      printf '!! customized %s (managed block%s)\n' "$rel" "$nobaseline"
      DRIFT=1
      return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '!! claude-md: managed block customized%s — refused (dry-run: no report written)\n' "$nobaseline" >&2
      CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
      return
    fi
    _write_region_divergence_report "$src" "$dst" "$(_check_region_divergence "$src" "$dst")"
    printf '!! claude-md: managed block customized%s — refused (see .claude/CLAUDE.md.diverged-region.md)\n' "$nobaseline" >&2
    printf '   Move project customizations OUTSIDE the markers, or accept Agent0 replacement via --force\n' >&2
    CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    return
  fi

  if [ "$MODE" = "check" ]; then
    if [ "$is_stale" -eq 1 ]; then
      printf '~ stale %s (managed block — would update)\n' "$rel"
    else
      printf '~ would merge %s (managed block)\n' "$rel"
    fi
    DRIFT=1
    return
  fi

  # Build new content: (pre-BEGIN incl marker) + src_region + (END marker onwards).
  local tmp begin_line end_line
  tmp="$(mktemp -t sync-claude-md-XXXXXX)"
  begin_line="$(grep -nE '^<!-- AGENT0:BEGIN -->$' "$dst" | head -1 | cut -d: -f1)"
  end_line="$(grep -nE '^<!-- AGENT0:END -->$' "$dst" | head -1 | cut -d: -f1)"

  head -n "$begin_line" "$dst" > "$tmp"
  if [ -n "$src_region" ]; then
    printf '%s\n' "$src_region" >> "$tmp"
  fi
  tail -n +"$end_line" "$dst" >> "$tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    rm -f "$tmp"
    if [ "$is_stale" -eq 1 ]; then
      printf '~ stale %s (managed block -> updated, dry-run)\n' "$rel"
      STALE_UPDATED=$((STALE_UPDATED + 1))
    else
      printf '! overwritten %s (managed block replaced under --force, dry-run)\n' "$rel" >&2
      OVERWRITTEN=$((OVERWRITTEN + 1))
    fi
    return
  fi

  mv "$tmp" "$dst"
  if [ "$is_stale" -eq 1 ]; then
    printf '~ stale %s (managed block -> updated)\n' "$rel"
    STALE_UPDATED=$((STALE_UPDATED + 1))
  else
    printf '! overwritten %s (managed block replaced under --force)\n' "$rel" >&2
    OVERWRITTEN=$((OVERWRITTEN + 1))
  fi
}

# Legacy heading-set append merge. Fallback for unmigrated consumer projects.
_merge_claude_md_legacy() {
  local rel="CLAUDE.md"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"

  if [ ! -f "$src" ]; then
    return
  fi

  if [ ! -f "$dst" ]; then
    process_file "$rel"
    return
  fi

  local src_sha dst_sha
  src_sha="$(sha_of "$src")"
  dst_sha="$(sha_of "$dst")"
  if [ "$src_sha" = "$dst_sha" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  local src_headings dst_headings missing_titles
  src_headings="$(extract_h2 "$src")"
  dst_headings="$(extract_h2 "$dst")"
  # Lines in src not in dst — preserve src ordering (don't sort), so inserted
  # sections appear in the same order as Agent0's CLAUDE.md.
  if [ -z "$dst_headings" ]; then
    missing_titles="$src_headings"
  else
    missing_titles="$(printf '%s\n' "$src_headings" | grep -Fxv -f <(printf '%s\n' "$dst_headings") || true)"
  fi

  if [ -z "$missing_titles" ]; then
    # CLAUDE.md is expected to diverge in consumer-authored content (Overview, Stack, etc).
    # The sync's only job is to ensure capacity sections from Agent0 are present.
    # If all Agent0 sections are present, treat as up-to-date regardless of other-body drift.
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  # We have missing sections to append. Build the new content.
  local tmp anchor anchor_line
  tmp="$(mktemp -t sync-claude-md-XXXXXX)"
  anchor="## Compact Instructions"
  anchor_line="$(grep -nF "$anchor" "$dst" | head -1 | cut -d: -f1 || true)"

  if [ -z "$anchor_line" ]; then
    printf '!! claude-md: missing "%s" anchor — appending at EOF\n' "$anchor" >&2
    cp "$dst" "$tmp"
    # Append each missing section
    while IFS= read -r title; do
      [ -z "$title" ] && continue
      printf '\n' >> "$tmp"
      extract_section "$src" "$title" >> "$tmp"
    done <<EOF
$missing_titles
EOF
  else
    # Split consumer project file: pre-anchor + anchor-onwards
    head -n $((anchor_line - 1)) "$dst" > "$tmp"
    while IFS= read -r title; do
      [ -z "$title" ] && continue
      extract_section "$src" "$title" >> "$tmp"
      printf '\n' >> "$tmp"
    done <<EOF
$missing_titles
EOF
    tail -n +$anchor_line "$dst" >> "$tmp"
  fi

  if [ "$MODE" = "check" ]; then
    printf '~ would merge %s\n' "$rel"
    DRIFT=1
    rm -f "$tmp"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '~ merged %s (dry-run)\n' "$rel"
    rm -f "$tmp"
  else
    mv "$tmp" "$dst"
    printf '~ merged %s\n' "$rel"
  fi
  MERGED=$((MERGED + 1))
}

# Dispatcher: routes by marker state in consumer project's CLAUDE.md.
merge_claude_md() {
  local rel="CLAUDE.md"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"

  if [ ! -f "$src" ]; then
    return
  fi
  if _skip_tracked_local_only "$rel"; then
    return
  fi

  if [ ! -f "$dst" ]; then
    process_file "$rel"
    return
  fi

  local src_sha dst_sha
  src_sha="$(sha_of "$src")"
  dst_sha="$(sha_of "$dst")"
  if [ "$src_sha" = "$dst_sha" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  local state
  state="$(detect_marker_state "$dst")"
  case "$state" in
    paired)
      _merge_claude_md_managed_block
      ;;
    mismatched)
      printf '!! claude-md: markers mismatched — both BEGIN and END must be paired, or both absent\n' >&2
      CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
      ;;
    nested-invalid)
      printf '!! claude-md: nested or out-of-order markers — exactly one BEGIN before exactly one END required\n' >&2
      CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
      ;;
    absent|*)
      _merge_claude_md_legacy
      _generate_migration_candidate
      ;;
  esac
}

# ---------------------------------------------------------------------------
# .gitignore additive merge
# ---------------------------------------------------------------------------

# Agent0's .gitignore carries harness-runtime entries (audit logs, state dirs,
# lock files) that MUST exist in any consumer project for the harness to run cleanly. Consumer project's
# .gitignore is typically stack-canonical (Laravel's vendor/, Next's node_modules/,
# etc.) and conflicts with Agent0's stack-agnostic template if overwritten. This
# function appends Agent0 entries the consumer project is missing, preserving consumer-specific
# lines untouched. Idempotent: re-runs add nothing once the consumer project has all Agent0
# entries. Comments and blank lines are NOT membership-keyed (entries are the
# semantic unit).

merge_gitignore() {
  local rel=".gitignore"
  local src="$AGENT0_ROOT/$rel"
  local dst="$CONSUMER_ROOT/$rel"
  local marker="# === Agent0 harness sync — additions ==="

  if [ ! -f "$src" ]; then
    return
  fi
  if _skip_tracked_local_only "$rel"; then
    return
  fi

  # Honor --force-except for the canonical .gitignore case (documented in
  # harness-sync.md). Even though merge is additive, the operator's intent in
  # passing --force-except='.gitignore' is "do not touch the consumer project's .gitignore".
  if matches_force_except "$rel"; then
    printf '!! force-except %s (merge skipped)\n' "$rel" >&2
    CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    return
  fi

  if [ ! -f "$dst" ]; then
    process_file "$rel"
    return
  fi

  local src_sha dst_sha
  src_sha="$(sha_of "$src")"
  dst_sha="$(sha_of "$dst")"
  if [ "$src_sha" = "$dst_sha" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  # Extract entries: non-comment, non-empty, trimmed. Sort for comm.
  local tmp_src_entries tmp_consumer_entries tmp_missing
  tmp_src_entries="$(mktemp -t sync-gi-src-XXXXXX)"
  tmp_consumer_entries="$(mktemp -t sync-gi-consumer-XXXXXX)"
  tmp_missing="$(mktemp -t sync-gi-miss-XXXXXX)"

  grep -v '^[[:space:]]*#' "$src" | grep -v '^[[:space:]]*$' | awk '{$1=$1;print}' | sort -u > "$tmp_src_entries"
  grep -v '^[[:space:]]*#' "$dst" | grep -v '^[[:space:]]*$' | awk '{$1=$1;print}' | sort -u > "$tmp_consumer_entries"

  # Lines in src but not in dst — these are the additions.
  comm -23 "$tmp_src_entries" "$tmp_consumer_entries" > "$tmp_missing"

  if [ ! -s "$tmp_missing" ]; then
    printf '= up to date %s\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    rm -f "$tmp_src_entries" "$tmp_consumer_entries" "$tmp_missing"
    return
  fi

  local missing_count
  missing_count="$(wc -l < "$tmp_missing" | awk '{print $1}')"

  if [ "$MODE" = "check" ]; then
    printf '~ would merge %s (%d entries to add)\n' "$rel" "$missing_count"
    DRIFT=1
    rm -f "$tmp_src_entries" "$tmp_consumer_entries" "$tmp_missing"
    return
  fi

  # Build merged content: consumer project's current content + marker (if new) + missing entries.
  local tmp_merged
  tmp_merged="$(mktemp -t sync-gi-merged-XXXXXX)"
  cat "$dst" > "$tmp_merged"

  if ! grep -Fq "$marker" "$tmp_merged"; then
    {
      printf '\n%s\n' "$marker"
    } >> "$tmp_merged"
  else
    printf '\n' >> "$tmp_merged"
  fi

  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$tmp_merged"
  done < "$tmp_missing"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '~ merged %s (%d entries, dry-run)\n' "$rel" "$missing_count"
    rm -f "$tmp_src_entries" "$tmp_consumer_entries" "$tmp_missing" "$tmp_merged"
  else
    mv "$tmp_merged" "$dst"
    printf '~ merged %s (%d entries appended)\n' "$rel" "$missing_count"
    rm -f "$tmp_src_entries" "$tmp_consumer_entries" "$tmp_missing"
  fi
  MERGED=$((MERGED + 1))
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

if _is_local_only "$CONSUMER_ROOT"; then
  LOCAL_ONLY=1
  printf 'local-only: consumer ignores the .agent0/ harness tree — refreshing gitignored harness, skipping all tracked-file writes\n' >&2
fi

load_baseline
# ---------------------------------------------------------------------------
# skill discovery-link pass (spec 121 — multi-runtime skills)
# ---------------------------------------------------------------------------
# The canonical skill source is .agent0/skills/<slug>/ (propagated as plain files
# by walk_copy_check). Each runtime discovers via a relative symlink into it:
#   .claude/skills/<slug> -> ../../.agent0/skills/<slug>   (Claude)
#   .agents/skills/<slug> -> ../../.agent0/skills/<slug>   (Codex)
# Runs only on a real --apply. Probes symlink capability once; on a symlink-hostile
# checkout (Windows without core.symlinks) it materializes copies + emits a
# skills-advisory: instead of leaving a broken text-file stub. Idempotent: an
# already-correct symlink is left untouched.
sync_skill_discovery_links() {
  [ "$MODE" = "apply" ] && [ "$DRY_RUN" -eq 0 ] || return 0
  local src_skills="$AGENT0_ROOT/.agent0/skills"
  [ -d "$src_skills" ] || return 0

  # Probe: can this consumer checkout create a real symlink?
  local symlinks_ok=1 probe="$CONSUMER_ROOT/.agent0/skills/.symlink-probe-$$"
  mkdir -p "$CONSUMER_ROOT/.agent0/skills" 2>/dev/null || true
  if ln -s .probe-target "$probe" 2>/dev/null && [ -L "$probe" ]; then
    symlinks_ok=1
  else
    symlinks_ok=0
  fi
  rm -f "$probe" 2>/dev/null || true

  local slug src linkrel dst rt
  for src in "$src_skills"/*/; do
    [ -d "$src" ] || continue
    slug="$(basename "$src")"
    case "$slug" in .*) continue ;; esac   # skip dotfiles / .gitkeep dir-likes
    for rt in ".claude/skills" ".agents/skills"; do
      dst="$CONSUMER_ROOT/$rt/$slug"
      linkrel="../../.agent0/skills/$slug"
      if _skip_tracked_local_only "$rt/$slug"; then
        continue
      fi
      mkdir -p "$CONSUMER_ROOT/$rt" 2>/dev/null || true
      if [ "$symlinks_ok" -eq 1 ]; then
        # idempotent: correct symlink already present?
        if [ -L "$dst" ] && [ "$(readlink "$dst" 2>/dev/null)" = "$linkrel" ]; then
          continue
        fi
        rm -rf "$dst" 2>/dev/null || true
        if ln -s "$linkrel" "$dst" 2>/dev/null; then
          printf '~ skill-link %s/%s -> %s\n' "$rt" "$slug" "$linkrel" >&2
        else
          printf 'skills-advisory: failed to link %s/%s; skill may be undiscoverable in that runtime\n' "$rt" "$slug" >&2
        fi
      else
        # symlink-hostile fallback: materialize a copy from the canonical source
        rm -rf "$dst" 2>/dev/null || true
        mkdir -p "$dst" 2>/dev/null || true
        if cp -R "$src". "$dst"/ 2>/dev/null; then
          printf 'skills-advisory: symlinks unavailable on this checkout — materialized copy at %s/%s; edit .agent0/skills/%s and re-sync (copy is regenerated each --apply)\n' "$rt" "$slug" "$slug" >&2
        else
          printf 'skills-advisory: symlinks unavailable AND copy failed for %s/%s\n' "$rt" "$slug" >&2
        fi
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# project-core mirror (spec 131 — consumer-source mirror)
# ---------------------------------------------------------------------------
# The consumer authors .agent0/project-core.md ONCE (consumer-owned, outside the
# sync manifest so Agent0 never overwrites it). On --apply its content renders
# verbatim into an always-on AGENT0:PROJECT region of BOTH entrypoints
# (CLAUDE.md + AGENTS.md) so Claude and Codex see the same project core. This is
# a NEW merge direction — consumer-source -> the consumer's own two entrypoints,
# not Agent0 -> consumer. Per-region rendered sha is recorded under synthetic
# keys "<rel>#PROJECT" (mirroring CLAUDE.md#managed-block). No-op when the source
# is absent: the feature is opt-in and backward-compatible.

# Mirror the rendered project core into one entrypoint's AGENT0:PROJECT region.
# Args: rel (CLAUDE.md|AGENTS.md), rendered (source content), rendered_sha.
_mirror_project_region() {
  local rel="$1" rendered="$2" rendered_sha="$3"
  local dst="$CONSUMER_ROOT/$rel"
  local synth="$rel#PROJECT"
  local state cur_region cur_sha base_sha is_stale tmp begin_line end_line nobaseline

  [ -f "$dst" ] || return 0
  if _skip_tracked_local_only "$rel"; then
    return 0
  fi

  state="$(detect_marker_state "$dst" "$PROJECT_MARKER")"
  if [ "$state" = "mismatched" ] || [ "$state" = "nested-invalid" ]; then
    if [ "$MODE" = "check" ]; then
      printf '!! project-core %s (markers %s)\n' "$rel" "$state"
      DRIFT=1
    else
      printf '!! project-core: %s has %s AGENT0:PROJECT markers — refused (fix manually)\n' "$rel" "$state" >&2
      CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    fi
    return
  fi

  # Record the rendered (source) sha under the synthetic key on every non-error
  # path so write_baseline persists it and stale-detection works next run.
  printf '%s\t%s\n' "$synth" "$rendered_sha" >> "$MANIFEST_RAW"
  sort -u "$MANIFEST_RAW" > "$MANIFEST_TSV"

  if [ "$state" = "absent" ]; then
    if [ "$MODE" = "check" ]; then
      printf '~ project-core %s (region would be created)\n' "$rel"
      DRIFT=1
      return
    fi
    tmp="$(mktemp -t sync-project-core-XXXXXX)"
    begin_line="$(grep -Fxn '<!-- AGENT0:BEGIN -->' "$dst" | head -1 | cut -d: -f1 || true)"
    if [ -n "$begin_line" ]; then
      head -n "$((begin_line - 1))" "$dst" > "$tmp"
      printf '<!-- AGENT0:PROJECT:BEGIN -->\n%s\n<!-- AGENT0:PROJECT:END -->\n\n' "$rendered" >> "$tmp"
      tail -n +"$begin_line" "$dst" >> "$tmp"
    else
      printf 'project-core: %s has no AGENT0:BEGIN anchor — appending PROJECT region at EOF\n' "$rel" >&2
      cat "$dst" > "$tmp"
      printf '\n<!-- AGENT0:PROJECT:BEGIN -->\n%s\n<!-- AGENT0:PROJECT:END -->\n' "$rendered" >> "$tmp"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      rm -f "$tmp"
      printf '~ project-core %s (region created, dry-run)\n' "$rel"
    else
      mv "$tmp" "$dst"
      printf '~ project-core %s (region created)\n' "$rel"
    fi
    STALE_UPDATED=$((STALE_UPDATED + 1))
    return
  fi

  # state == paired
  cur_region="$(_extract_region "$dst" "$PROJECT_MARKER")"
  cur_sha="$(_region_sha "$cur_region")"
  if [ "$cur_sha" = "$rendered_sha" ]; then
    printf '= up to date %s (project-core)\n' "$rel"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  base_sha="$(baseline_sha_for "$synth")"
  is_stale=0
  if [ -n "$base_sha" ] && [ "$base_sha" = "$cur_sha" ]; then
    is_stale=1
  fi

  if [ "$is_stale" -ne 1 ] && { [ "$FORCE" -ne 1 ] || matches_force_except "$rel"; }; then
    nobaseline=""
    if [ -z "$base_sha" ]; then nobaseline=" (no baseline)"; fi
    if [ "$MODE" = "check" ]; then
      printf '!! customized %s (project-core region%s)\n' "$rel" "$nobaseline"
      DRIFT=1
      return
    fi
    printf '!! project-core: %s region edited away from source%s — refused; edit the source .agent0/project-core.md, or --force to re-render\n' "$rel" "$nobaseline" >&2
    CUSTOMIZED_REFUSED=$((CUSTOMIZED_REFUSED + 1))
    return
  fi

  if [ "$MODE" = "check" ]; then
    if [ "$is_stale" -eq 1 ]; then
      printf '~ stale %s (project-core — would re-render)\n' "$rel"
    else
      printf '~ would re-render %s (project-core, --force)\n' "$rel"
    fi
    DRIFT=1
    return
  fi

  tmp="$(mktemp -t sync-project-core-XXXXXX)"
  begin_line="$(grep -Fxn '<!-- AGENT0:PROJECT:BEGIN -->' "$dst" | head -1 | cut -d: -f1)"
  end_line="$(grep -Fxn '<!-- AGENT0:PROJECT:END -->' "$dst" | head -1 | cut -d: -f1)"
  head -n "$((begin_line - 1))" "$dst" > "$tmp"
  printf '<!-- AGENT0:PROJECT:BEGIN -->\n%s\n<!-- AGENT0:PROJECT:END -->\n' "$rendered" >> "$tmp"
  tail -n +"$((end_line + 1))" "$dst" >> "$tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    rm -f "$tmp"
    if [ "$is_stale" -eq 1 ]; then
      printf '~ stale %s (project-core re-rendered, dry-run)\n' "$rel"
      STALE_UPDATED=$((STALE_UPDATED + 1))
    else
      printf '! overwritten %s (project-core re-rendered under --force, dry-run)\n' "$rel" >&2
      OVERWRITTEN=$((OVERWRITTEN + 1))
    fi
    return
  fi

  mv "$tmp" "$dst"
  if [ "$is_stale" -eq 1 ]; then
    printf '~ stale %s (project-core re-rendered)\n' "$rel"
    STALE_UPDATED=$((STALE_UPDATED + 1))
  else
    printf '! overwritten %s (project-core re-rendered under --force)\n' "$rel" >&2
    OVERWRITTEN=$((OVERWRITTEN + 1))
  fi
}

# Read the consumer's project-core source (if any) and mirror it into both
# entrypoints. No-op when the source is absent.
sync_project_core() {
  local core_src rendered rendered_sha
  core_src="$CONSUMER_ROOT/$PROJECT_SOURCE_REL"
  [ -f "$core_src" ] || return 0
  rendered="$(cat "$core_src")"
  rendered_sha="$(_region_sha "$rendered")"
  _mirror_project_region "CLAUDE.md" "$rendered" "$rendered_sha"
  _mirror_project_region "AGENTS.md" "$rendered" "$rendered_sha"
}

_self_rebootstrap
walk_copy_check
record_managed_block_manifest
reconcile_deletions
sync_skill_discovery_links
merge_settings_json
merge_claude_md
merge_gitignore
sync_project_core
write_baseline

# Summary on stderr so stdout stays parseable per-file decisions.
{
  printf '\n'
  SUMMARY="$(printf 'synced: %d copied, %d stale-updated, %d removed, %d merged, %d up-to-date, %d customized-refused, %d overwritten' \
    "$COPIED" "$STALE_UPDATED" "$REMOVED" "$MERGED" "$UP_TO_DATE" "$CUSTOMIZED_REFUSED" "$OVERWRITTEN"
  )"
  if [ "$LOCAL_ONLY" -eq 1 ]; then
    SUMMARY="$SUMMARY, $SKIPPED_TRACKED tracked-skipped (local-only)"
  fi
  printf '%s\n' "$SUMMARY"
} >&2

# Exit code policy
if [ "$MODE" = "check" ]; then
  if [ "$DRIFT" -ne 0 ]; then
    exit 1
  fi
  exit 0
fi

# apply mode
if [ "$CUSTOMIZED_REFUSED" -gt 0 ]; then
  exit 1
fi

exit 0
