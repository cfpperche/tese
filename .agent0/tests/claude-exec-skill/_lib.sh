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

# Fake `claude` that records argv + stdin and emits the JSON shape the real
# CLI produces (verified 2026-05-30): a type=="result" record carrying
# .result and .session_id, as a single object for --output-format json and
# as the final JSONL line for --output-format stream-json.
make_fake_claude() {
  local bin_dir=$1
  mkdir -p "$bin_dir"
  cat > "$bin_dir/claude" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_CLAUDE_ARGS:?}"
: "${FAKE_CLAUDE_STDIN:?}"

for arg in "$@"; do
  printf '<%s>\n' "$arg" >> "$FAKE_CLAUDE_ARGS"
done
cat > "$FAKE_CLAUDE_STDIN"

fmt="text"
prev=""
for arg in "$@"; do
  if [ "$prev" = "--output-format" ]; then
    fmt=$arg
  fi
  prev=$arg
done

sid="${FAKE_CLAUDE_SESSION:-fake-session-0001}"
result_line=$(printf '{"type":"result","subtype":"success","is_error":false,"result":"fake claude review","session_id":"%s"}' "$sid")

if [ "$fmt" = "stream-json" ]; then
  printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$sid"
  printf '{"type":"assistant"}\n'
  printf '%s\n' "$result_line"
else
  printf '%s\n' "$result_line"
fi

exit "${FAKE_CLAUDE_EXIT:-0}"
FAKE
  chmod +x "$bin_dir/claude"
}

# Symlink the named real utilities into dir (used to build a PATH that
# deliberately omits a dependency such as jq).
link_utils() {
  local dir=$1
  shift
  mkdir -p "$dir"
  local u p
  for u in "$@"; do
    p=$(command -v "$u" 2>/dev/null) || continue
    ln -sf "$p" "$dir/$u"
  done
}

finish() {
  echo "  -- $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
