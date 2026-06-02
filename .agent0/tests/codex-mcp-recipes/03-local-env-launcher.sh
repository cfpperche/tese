#!/usr/bin/env bash
# Scenario: shipped Codex launcher loads project-local .codex/.env.local.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$AGENT0_ROOT/.agent0/tools/codex-local-env.sh"

if [ ! -f "$TOOL" ]; then
  printf 'FAIL: missing %s\n' "$TOOL"
  exit 1
fi

TMPDIR="$(mktemp -d -t codex-local-env-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

ROOT="$TMPDIR/project"
mkdir -p "$ROOT/.agent0/tools" "$ROOT/.codex" "$TMPDIR/bin"
cp "$TOOL" "$ROOT/.agent0/tools/codex-local-env.sh"
chmod +x "$ROOT/.agent0/tools/codex-local-env.sh"

cat > "$ROOT/.codex/.env.local" <<'EOF'
FAL_KEY=LOCAL-FAL-MARKER
DATABASE_URL=LOCAL-DB-MARKER
EOF

cat > "$TMPDIR/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'pwd=%s\n' "$(pwd)" > "$CODEX_CAPTURE"
printf 'args=%s\n' "$*" >> "$CODEX_CAPTURE"
printf 'FAL_KEY=%s\n' "${FAL_KEY:-}" >> "$CODEX_CAPTURE"
printf 'DATABASE_URL=%s\n' "${DATABASE_URL:-}" >> "$CODEX_CAPTURE"
EOF
chmod +x "$TMPDIR/bin/codex"

CODEX_CAPTURE="$TMPDIR/capture.txt" PATH="$TMPDIR/bin:$PATH" "$ROOT/.agent0/tools/codex-local-env.sh" exec "probe"

if ! grep -Fxq "args=-C $ROOT exec probe" "$TMPDIR/capture.txt"; then
  printf 'FAIL: launcher did not exec codex with repo root -C\n'
  cat "$TMPDIR/capture.txt"
  exit 1
fi

if ! grep -Fxq 'FAL_KEY=LOCAL-FAL-MARKER' "$TMPDIR/capture.txt"; then
  printf 'FAIL: FAL_KEY was not loaded from .codex/.env.local\n'
  cat "$TMPDIR/capture.txt"
  exit 1
fi

if ! grep -Fxq 'DATABASE_URL=LOCAL-DB-MARKER' "$TMPDIR/capture.txt"; then
  printf 'FAIL: DATABASE_URL was not loaded from .codex/.env.local\n'
  cat "$TMPDIR/capture.txt"
  exit 1
fi

echo "PASS: 03-local-env-launcher"
