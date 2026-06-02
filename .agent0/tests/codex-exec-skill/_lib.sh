#!/usr/bin/env bash
set -uo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  ✓ $1"
}

no() {
  FAIL=$((FAIL + 1))
  echo "  ✗ $1"
}

assert_file() {
  [ -f "$1" ] && ok "$2" || { no "$2"; echo "      missing file: $1"; }
}

assert_no_path() {
  [ ! -e "$1" ] && ok "$2" || { no "$2"; echo "      unexpected path: $1"; }
}

assert_contains() {
  local file=$1
  local needle=$2
  local label=$3
  if grep -Fq -- "$needle" "$file"; then
    ok "$label"
  else
    no "$label"
    echo "      missing: $needle"
    [ -f "$file" ] && sed -n '1,120p' "$file"
  fi
}

assert_arg_order() {
  local file=$1
  local left=$2
  local right=$3
  local label=$4
  local left_line right_line
  left_line=$(grep -nFx -- "<$left>" "$file" | head -1 | cut -d: -f1)
  right_line=$(grep -nFx -- "<$right>" "$file" | head -1 | cut -d: -f1)
  if [ -n "$left_line" ] && [ -n "$right_line" ] && [ "$left_line" -lt "$right_line" ]; then
    ok "$label"
  else
    no "$label"
    echo "      expected <$left> before <$right>"
    sed -n '1,160p' "$file"
  fi
}

make_fake_codex() {
  local bin_dir=$1
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_CODEX_ARGS:?}"
: "${FAKE_CODEX_STDIN:?}"

for arg in "$@"; do
  printf '<%s>\n' "$arg" >> "$FAKE_CODEX_ARGS"
done
cat > "$FAKE_CODEX_STDIN"

out=""
json=0
prev=""
for arg in "$@"; do
  if [ "$prev" = "--output-last-message" ] || [ "$prev" = "-o" ]; then
    out=$arg
  fi
  if [ "$arg" = "--json" ]; then
    json=1
  fi
  prev=$arg
done

if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  printf 'fake codex last message\n' > "$out"
fi

if [ "$json" -eq 1 ]; then
  printf '{"event":"fake"}\n'
else
  printf 'fake codex stdout\n'
fi

exit "${FAKE_CODEX_EXIT:-0}"
FAKE
  chmod +x "$bin_dir/codex"
}

finish() {
  echo "  -- $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
