#!/usr/bin/env bash
# Scenario: project memory CONTENT does NOT propagate to consumer projects,
# but the empty scaffold (.gitkeep) DOES so each consumer project can use its own bucket.
# INVARIANT GUARD: protects sync-harness manifest from accidental inclusion
# of memory content files.
# Asserts:
#   (a) Upstream mock with .agent0/memory/{.gitkeep, MEMORY.md, foo.md} populated
#   (b) After sync: consumer project has .agent0/memory/.gitkeep (scaffold shipped)
#   (c) After sync: consumer project has NO MEMORY.md and NO foo.md (content stays upstream)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/sync-harness.sh"

TMPDIR="$(mktemp -d -t spec-019-02-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/agent0"
CONSUMER="$TMPDIR/consumer"
mkdir -p "$SRC/.agent0/memory" "$SRC/.claude/hooks" "$CONSUMER/.claude"

# Mock upstream source — minimal but with memory content populated
printf '#!/usr/bin/env bash\necho test\n' > "$SRC/.claude/hooks/test-hook.sh"
chmod +x "$SRC/.claude/hooks/test-hook.sh"
printf '{"hooks":{}}\n' > "$SRC/.claude/settings.json"
printf '# CLAUDE\n\n## Compact Instructions\n' > "$SRC/CLAUDE.md"

# Scaffold marker + upstream-internal content
touch "$SRC/.agent0/memory/.gitkeep"
cat > "$SRC/.agent0/memory/foo.md" <<'EOF'
---
name: foo
description: Upstream-only memory content that should NEVER ship to consumer projects
metadata:
  type: project
---
foo body
EOF
cat > "$SRC/.agent0/memory/MEMORY.md" <<'EOF'
- [Foo](foo.md) — Upstream-internal entry that should NOT appear in consumer project
EOF

# Empty consumer project target
printf '{"hooks":{}}\n' > "$CONSUMER/.claude/settings.json"
printf '# Consumer project CLAUDE\n\n## Compact Instructions\n' > "$CONSUMER/CLAUDE.md"

bash "$TOOL" --apply --agent0-path="$SRC" "$CONSUMER" >/dev/null 2>&1 || true

# Assert: empty scaffold shipped (consumer project has its own bucket to use)
if [ ! -f "$CONSUMER/.agent0/memory/.gitkeep" ]; then
  printf 'FAIL: .gitkeep scaffold did not ship to consumer project\n'
  ls -la "$CONSUMER/.agent0/memory/" 2>&1
  exit 1
fi

# Assert: content files did NOT ship
if [ -f "$CONSUMER/.agent0/memory/foo.md" ]; then
  printf 'FAIL: upstream content file foo.md leaked to consumer project\n'
  exit 1
fi
if [ -f "$CONSUMER/.agent0/memory/MEMORY.md" ]; then
  printf 'FAIL: upstream MEMORY.md leaked to consumer project (each consumer project must have its own)\n'
  exit 1
fi

echo "PASS: 02-no-consumer-propagation"
