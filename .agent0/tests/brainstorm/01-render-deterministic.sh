#!/usr/bin/env bash
# .agent0/tests/brainstorm/01-render-deterministic.sh
#
# brainstorm `done` renderer is a pure function of the state JSON. Asserts:
#   (a) exit 0 and an output path printed
#   (b) zero unsubstituted {{PLACEHOLDER}} tokens left in the HTML
#   (c) counts header matches array lengths (4 ideas / 2 questions / 2 lenses)
#   (d) mindmap source is populated: tag buckets + a `↳ via <lens>` provenance node
#   (e) mermaid timeline replaces the field-delimiter colon (no broken `summary:`)
#   (f) one lens tab + panel + kanban host per applied lens (slug-matched)
#   (g) Six Thinking Hats renders its per-hat sub-section
#   (h) STATE_JSON embed escapes `</` so a string can't break out of <script>
#   (i) byte-for-byte deterministic across two runs (no clock/random in output)

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
RENDER="$AGENT0_ROOT/.agent0/skills/brainstorm/scripts/render.py"
FIXTURE="$AGENT0_ROOT/.agent0/tests/brainstorm/fixtures/sample-state.json"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

OUT="$TMPDIR/out.html"

# (a) exit 0 + path printed
PRINTED="$(python3 "$RENDER" "$FIXTURE" --out "$OUT")" || { echo "FAIL (a): non-zero exit"; exit 1; }
[ "$PRINTED" = "$OUT" ] || { echo "FAIL (a): printed path '$PRINTED' != '$OUT'"; exit 1; }
[ -s "$OUT" ] || { echo "FAIL (a): output is empty"; exit 1; }

# (b) no leftover placeholders
if grep -oE '\{\{[A-Z_]+\}\}' "$OUT"; then
  echo "FAIL (b): unsubstituted placeholders above"; exit 1
fi

# (c) counts
grep -q '<strong>4</strong> ideas' "$OUT"           || { echo "FAIL (c): ideas count"; exit 1; }
grep -q '<strong>2</strong> open questions' "$OUT"  || { echo "FAIL (c): questions count"; exit 1; }
grep -q '<strong>2</strong> lenses applied' "$OUT"  || { echo "FAIL (c): lenses count"; exit 1; }

# (d) mindmap buckets + provenance
grep -q '^## easy' "$OUT"   || { echo "FAIL (d): no easy bucket in mindmap"; exit 1; }
grep -q '^## wild' "$OUT"   || { echo "FAIL (d): no wild bucket in mindmap"; exit 1; }
grep -q '↳ via SCAMPER' "$OUT" || { echo "FAIL (d): no derived-from provenance node"; exit 1; }

# (e) mermaid colon replaced — the summary 'opened: user...' must not keep 'opened:'
grep -q 'opened — user named the topic' "$OUT" || { echo "FAIL (e): colon not replaced in mermaid"; exit 1; }
if grep -qE 'turn 1 : opened:' "$OUT"; then echo "FAIL (e): raw colon survived in mermaid"; exit 1; fi

# (f) lens tab + panel + kanban host (SCAMPER -> scamper; Six Thinking Hats -> six-thinking-hats)
for slug in scamper six-thinking-hats; do
  grep -q "data-tab=\"lens-$slug\""   "$OUT" || { echo "FAIL (f): missing tab lens-$slug"; exit 1; }
  grep -q "data-panel=\"lens-$slug\"" "$OUT" || { echo "FAIL (f): missing panel lens-$slug"; exit 1; }
  grep -q "id=\"kanban-$slug\""       "$OUT" || { echo "FAIL (f): missing kanban-$slug"; exit 1; }
done
# badge css-slug alias: six-thinking-hats -> six-hats
grep -q 'lens-badge six-hats' "$OUT" || { echo "FAIL (f): six-hats badge alias missing"; exit 1; }

# (g) Six Thinking Hats per-hat sub-section
grep -q '<h3>black hat</h3>' "$OUT" || { echo "FAIL (g): black-hat sub-section missing"; exit 1; }
grep -q 'the load-bearing assumption could be wrong' "$OUT" || { echo "FAIL (g): hat capture missing"; exit 1; }

# (h) </ escaped in the embedded STATE_JSON (no literal </script> from a string value)
grep -q '<\\/script>' "$OUT" || { echo "FAIL (h): STATE_JSON did not escape </"; exit 1; }

# (i) deterministic across two runs
OUT2="$TMPDIR/out2.html"
python3 "$RENDER" "$FIXTURE" --out "$OUT2" >/dev/null
if ! cmp -s "$OUT" "$OUT2"; then echo "FAIL (i): render is not byte-stable across runs"; exit 1; fi

echo "PASS: brainstorm render is deterministic, complete, and breakout-safe"
