#!/usr/bin/env bash
# Spec 130 — Scenario: a pre-130 legacy baseline at .claude/harness-sync-baseline.json
# auto-migrates to .agent0/harness-sync-baseline.json on --apply (read from legacy,
# write to new, remove legacy), with no spurious customized storm. --check mutates nothing.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-130-36-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.claude/hooks" "$CONSUMER/.claude/hooks"

# Agent0 source: one managed hook + minimal settings/CLAUDE.md.
printf '#!/usr/bin/env bash\necho hookA\n' > "$SRC/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"
chmod +x "$SRC/.claude/hooks/hookA.sh"

# Consumer: identical hook (up-to-date, no customization) + a LEGACY baseline at .claude/
# recording that hook's sha, so reconciliation reads it cleanly (no customized storm).
printf '#!/usr/bin/env bash\necho hookA\n' > "$CONSUMER/.claude/hooks/hookA.sh"
chmod +x "$CONSUMER/.claude/hooks/hookA.sh"
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# CLAUDE consumer\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"
HOOK_SHA="$(sha256sum "$SRC/.claude/hooks/hookA.sh" | cut -d' ' -f1)"
LEGACY="$CONSUMER/.claude/harness-sync-baseline.json"
NEW="$CONSUMER/.agent0/harness-sync-baseline.json"
cat > "$LEGACY" <<EOF
{
  "agent0_commit": null,
  "synced_at": "2026-01-01T00:00:00Z",
  "tool_version": 1,
  "files": { ".claude/hooks/hookA.sh": "$HOOK_SHA" }
}
EOF

# --- Sub-test A: --check on a legacy-only consumer mutates nothing ---
OUT_CHECK="$(bash "$TOOL" --agent0-path="$SRC" --check "$CONSUMER" 2>&1 || true)"
if [ -f "$NEW" ]; then
  printf 'FAIL: --check created the new .agent0/ baseline\n%s\n' "$OUT_CHECK"; exit 1
fi
if [ ! -f "$LEGACY" ]; then
  printf 'FAIL: --check removed the legacy baseline\n%s\n' "$OUT_CHECK"; exit 1
fi
printf 'ok: --check on legacy-only consumer mutated nothing\n'

# --- Sub-test B: --apply migrates legacy -> new and removes legacy ---
OUT_APPLY="$(bash "$TOOL" --agent0-path="$SRC" --apply "$CONSUMER" 2>&1 || true)"

if [ ! -f "$NEW" ]; then
  printf 'FAIL: --apply did not write the new .agent0/ baseline\n%s\n' "$OUT_APPLY"; exit 1
fi
printf 'ok: new .agent0/ baseline written\n'

if [ -f "$LEGACY" ]; then
  printf 'FAIL: legacy .claude/ baseline was not removed\n%s\n' "$OUT_APPLY"; exit 1
fi
printf 'ok: legacy .claude/ baseline removed\n'

if printf '%s' "$OUT_APPLY" | grep -q '!! customized'; then
  printf 'FAIL: spurious customized storm during migration\n%s\n' "$OUT_APPLY"; exit 1
fi
printf 'ok: no customized storm (legacy baseline was read for reconciliation)\n'

# New baseline carries the migrated files-map.
if ! jq -e '.files | has(".claude/hooks/hookA.sh")' "$NEW" >/dev/null 2>&1; then
  printf 'FAIL: new baseline missing the migrated files-map\n'; cat "$NEW"; exit 1
fi
printf 'ok: new baseline carries the files-map\n'

# --- Sub-test C: idempotent re-apply does not recreate the legacy file ---
bash "$TOOL" --agent0-path="$SRC" --apply "$CONSUMER" >/dev/null 2>&1 || true
if [ -f "$LEGACY" ]; then
  printf 'FAIL: re-apply recreated the legacy baseline\n'; exit 1
fi
printf 'ok: idempotent re-apply leaves no legacy file\n'

printf 'PASS: 36-baseline-legacy-migration\n'
