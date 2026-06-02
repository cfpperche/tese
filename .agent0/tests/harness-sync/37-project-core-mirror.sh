#!/usr/bin/env bash
# Scenario: spec 131 — consumer-source project-core mirror.
# Asserts the consumer-owned .agent0/project-core.md is mirrored into an always-on
# AGENT0:PROJECT region of BOTH CLAUDE.md and AGENTS.md, with create / idempotent /
# stale / customized-refuse / --force / source-never-written / index-untouched /
# synthetic-baseline-keys / absent-source-no-op semantics.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-131-37-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC" "$CONSUMER/.agent0"

SENTINEL="SENTINEL-PROJECT-CORE-7f3a9b"

fail() { printf 'FAIL (37): %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2"; exit 1; }

# --- fixtures: identical entrypoints in SRC and CONSUMER (paired index block) ---
make_entrypoint() {
  # $1 = path, $2 = title
  printf '# %s\n\n## Overview\n\nproject narrative.\n\n<!-- AGENT0:BEGIN -->\n\n## Spec-driven development\n\nindex body.\n\n## Compact Instructions\n\ncompact body.\n\n<!-- AGENT0:END -->\n' "$2" > "$1"
}
mkdir -p "$SRC/.claude"
make_entrypoint "$SRC/CLAUDE.md" "Agent0"
make_entrypoint "$SRC/AGENTS.md" "Agent0 Codex"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"

cp "$SRC/CLAUDE.md" "$CONSUMER/CLAUDE.md"
cp "$SRC/AGENTS.md" "$CONSUMER/AGENTS.md"
mkdir -p "$CONSUMER/.claude"; printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"

# consumer-owned project core (NOT shipped by Agent0)
printf '# Cognix project core\n\n%s the always-on shared core.\n\nVoice: precise, pragmatic.\n' "$SENTINEL" > "$CONSUMER/.agent0/project-core.md"
SRC_CORE_SHA_BEFORE="$(sha256sum "$CONSUMER/.agent0/project-core.md" | awk '{print $1}')"

index_block() { awk '/^<!-- AGENT0:END -->$/{f=0} f; /^<!-- AGENT0:BEGIN -->$/{f=1}' "$1"; }
SRC_INDEX="$(index_block "$SRC/CLAUDE.md")"

# ========================= Phase 1: create =========================
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || fail "apply-1 nonzero exit" "$out"

grep -q "$SENTINEL" "$CONSUMER/CLAUDE.md" || fail "sentinel not mirrored into CLAUDE.md" "$out"
grep -q "$SENTINEL" "$CONSUMER/AGENTS.md" || fail "sentinel not mirrored into AGENTS.md" "$out"
grep -qF '<!-- AGENT0:PROJECT:BEGIN -->' "$CONSUMER/CLAUDE.md" || fail "no PROJECT markers in CLAUDE.md"
grep -qF '<!-- AGENT0:PROJECT:BEGIN -->' "$CONSUMER/AGENTS.md" || fail "no PROJECT markers in AGENTS.md"
echo "  ok: phase1 sentinel mirrored into BOTH entrypoints"

# index block must be byte-untouched in both
[ "$(index_block "$CONSUMER/CLAUDE.md")" = "$SRC_INDEX" ] || fail "CLAUDE.md index block changed"
[ "$(index_block "$CONSUMER/AGENTS.md")" = "$SRC_INDEX" ] || fail "AGENTS.md index block changed"
echo "  ok: phase1 AGENT0:BEGIN/END index block untouched"

# synthetic baseline keys recorded
BL="$CONSUMER/.agent0/harness-sync-baseline.json"
grep -qF 'CLAUDE.md#PROJECT' "$BL" || fail "baseline missing CLAUDE.md#PROJECT" "$(cat "$BL")"
grep -qF 'AGENTS.md#PROJECT' "$BL" || fail "baseline missing AGENTS.md#PROJECT" "$(cat "$BL")"
echo "  ok: phase1 synthetic keys recorded in baseline"

# ========================= Phase 2: idempotent =========================
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || fail "apply-2 (idempotent) nonzero exit" "$out"
printf '%s' "$out" | grep -qE '!! customized.*AGENTS\.md' && fail "AGENTS.md falsely reported customized on re-apply (strip failed)" "$out"
printf '%s' "$out" | grep -q 'up to date.*project-core' || fail "project-core not reported up-to-date on re-apply" "$out"
echo "  ok: phase2 idempotent — AGENTS.md NOT falsely customized (strip works)"

# ========================= Phase 3: stale auto-update (source changed) =========================
printf '# Cognix project core\n\n%s v2 the always-on shared core.\n\nVoice: precise.\n' "$SENTINEL" > "$CONSUMER/.agent0/project-core.md"
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)" || fail "apply-3 (stale) nonzero exit" "$out"
grep -q "$SENTINEL v2" "$CONSUMER/CLAUDE.md" || fail "stale re-render did not update CLAUDE.md" "$out"
grep -q "$SENTINEL v2" "$CONSUMER/AGENTS.md" || fail "stale re-render did not update AGENTS.md" "$out"
echo "  ok: phase3 source change re-renders both regions without --force"

# ========================= Phase 4: customized region refused =========================
# Hand-edit the PROJECT region inside AGENTS.md (diverge from source + baseline).
sed -i 's/'"$SENTINEL"' v2.*/HAND-EDITED-DERIVED-REGION/' "$CONSUMER/AGENTS.md"
set +e
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "apply with edited derived region should exit nonzero" "$out"
printf '%s' "$out" | grep -qE 'project-core.*AGENTS\.md.*refused' || fail "edited derived region not refused" "$out"
grep -q 'HAND-EDITED-DERIVED-REGION' "$CONSUMER/AGENTS.md" || fail "refused region was wrongly modified" "$out"
echo "  ok: phase4 consumer-edited derived region refused, left untouched"

# source file never written
[ "$(sha256sum "$CONSUMER/.agent0/project-core.md" | awk '{print $1}')" != "$SRC_CORE_SHA_BEFORE" ] || true  # (it changed in phase3 intentionally)
SRC_CORE_SHA_NOW="$(sha256sum "$CONSUMER/.agent0/project-core.md" | awk '{print $1}')"

# ========================= Phase 5: --force re-renders =========================
out="$(bash "$TOOL" --apply --force --agent0-path="$SRC" "$CONSUMER" 2>&1)" || fail "apply --force nonzero exit" "$out"
grep -q 'HAND-EDITED-DERIVED-REGION' "$CONSUMER/AGENTS.md" && fail "--force did not discard the derived edit" "$out"
grep -q "$SENTINEL v2" "$CONSUMER/AGENTS.md" || fail "--force did not re-render from source" "$out"
# source still never written by sync
[ "$(sha256sum "$CONSUMER/.agent0/project-core.md" | awk '{print $1}')" = "$SRC_CORE_SHA_NOW" ] || fail "sync overwrote the consumer-owned source"
echo "  ok: phase5 --force re-renders from source; source never written"

# ========================= Phase 6: absent source = no-op =========================
CONSUMER2="$TMPDIR/consumer2"
mkdir -p "$CONSUMER2/.claude"
cp "$SRC/CLAUDE.md" "$CONSUMER2/CLAUDE.md"
cp "$SRC/AGENTS.md" "$CONSUMER2/AGENTS.md"
printf '{"hooks":{}}\n' > "$CONSUMER2/.claude/settings.json"
out="$(bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER2" 2>&1)" || fail "apply on no-core consumer nonzero exit" "$out"
grep -qF '<!-- AGENT0:PROJECT:BEGIN -->' "$CONSUMER2/CLAUDE.md" && fail "PROJECT region created without a source"
printf '%s' "$out" | grep -q 'project-core' && fail "project-core pass acted with no source" "$out"
echo "  ok: phase6 absent source is a clean no-op"

echo "PASS: 37-project-core-mirror"
