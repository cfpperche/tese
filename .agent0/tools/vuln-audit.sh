#!/usr/bin/env bash
# .agent0/tools/vuln-audit.sh
#
# vuln-audit — runtime-neutral detector for known-vulnerable INSTALLED dependencies.
# Spec: docs/specs/120-vuln-audit/. Engine: osv-scanner (osv-scanner-only for v1).
#
# Philosophy (spec 112 → 120): do NOT gate install or commit. Detect vulnerable
# locked deps on demand, report + propose, never auto-fix. Human-in-loop.
#
# Usage:
#   vuln-audit.sh [path] [--json] [--exit-code] [--severity <low|moderate|high|critical>]
#
#   path           directory to scan (default: .)
#   --json         emit a deterministic structured doc on stdout (shape-only
#                  convenience, NOT a versioned wire contract — field set may evolve)
#   --exit-code    map result status -> process exit code (consumer-owned CI opt-in):
#                  clean=0 findings=1 unavailable=2 failed=3. WITHOUT this flag the
#                  process ALWAYS exits 0 (advisory family — never a gate).
#   --severity L   report only findings at severity >= L (default: report all)
#
# Result statuses (first-class, decoupled from exit code):
#   clean       engine ran, no known-vulnerable deps in its corpus
#   findings    engine ran, >=1 known-vulnerable dep
#   unavailable engine binary (osv-scanner) not installed
#   failed      engine ran but errored / produced unparseable output
#
# Source-completeness caveat: reports "known vulnerabilities found by the selected
# OSV-backed engine", NOT "all vulnerabilities known anywhere". Coverage buckets
# prove which lockfiles were parsed, not advisory-corpus completeness.

set -uo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
SCAN_PATH="."
OUT_JSON=0
USE_EXIT_CODE=0
SEVERITY_FLOOR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUT_JSON=1 ;;
    --exit-code) USE_EXIT_CODE=1 ;;
    --severity)
      shift
      SEVERITY_FLOOR="${1:-}"
      case "$SEVERITY_FLOOR" in
        low|moderate|high|critical) ;;
        *) echo "vuln-audit: --severity must be one of: low moderate high critical" >&2; exit 64 ;;
      esac
      ;;
    --severity=*) SEVERITY_FLOOR="${1#*=}" ;;
    -h|--help)
      sed -n '3,32p' "$0"
      exit 0
      ;;
    -*) echo "vuln-audit: unknown flag: $1" >&2; exit 64 ;;
    *) SCAN_PATH="$1" ;;
  esac
  shift
done

# ENGINE override hook (tests inject a fake binary name; default real engine).
ENGINE="${VULN_AUDIT_ENGINE:-osv-scanner}"

# severity rank for floor comparisons
sev_rank() {
  case "$1" in
    critical) echo 4 ;;
    high) echo 3 ;;
    moderate|medium) echo 2 ;;
    low) echo 1 ;;
    *) echo 0 ;;   # unknown/none
  esac
}

# ---------------------------------------------------------------------------
# Thin lockfile -> ecosystem map (coverage-report aid only; NOT a matcher).
# value: "<ecosystem>|<supported 0/1>|<skip-reason when unsupported>"
# ---------------------------------------------------------------------------
lockfile_meta() {
  case "$1" in
    package-lock.json|npm-shrinkwrap.json) echo "npm|1|" ;;
    yarn.lock)        echo "npm (yarn)|1|" ;;
    pnpm-lock.yaml)   echo "npm (pnpm)|1|" ;;
    bun.lock)         echo "npm (bun)|1|" ;;
    bun.lockb)        echo "npm (bun)|0|binary lockfile not parsed by osv-scanner; regenerate as text bun.lock via 'bun install' on Bun >=1.2" ;;
    composer.lock)    echo "Packagist|1|" ;;
    Cargo.lock)       echo "crates.io|1|" ;;
    go.mod|go.sum)    echo "Go|1|" ;;
    poetry.lock)      echo "PyPI|1|" ;;
    Pipfile.lock)     echo "PyPI|1|" ;;
    requirements.txt) echo "PyPI|1|" ;;
    Gemfile.lock)     echo "RubyGems|1|" ;;
    gradle.lockfile)  echo "Maven|1|" ;;
    packages.lock.json) echo "NuGet|1|" ;;
    *) echo "" ;;
  esac
}

KNOWN_LOCKFILES="package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb composer.lock Cargo.lock go.mod go.sum poetry.lock Pipfile.lock requirements.txt Gemfile.lock gradle.lockfile packages.lock.json"

# ---------------------------------------------------------------------------
# Render an advisory + status doc and exit. $1=status $2=message
# ---------------------------------------------------------------------------
emit_exit() {
  local status="$1"
  case "$status" in
    clean) [ "$USE_EXIT_CODE" -eq 1 ] && exit 0 || exit 0 ;;
    findings) [ "$USE_EXIT_CODE" -eq 1 ] && exit 1 || exit 0 ;;
    unavailable) [ "$USE_EXIT_CODE" -eq 1 ] && exit 2 || exit 0 ;;
    failed) [ "$USE_EXIT_CODE" -eq 1 ] && exit 3 || exit 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# Build the FOUND lockfile list (relative to SCAN_PATH), skipping vendor dirs.
# ---------------------------------------------------------------------------
declare -a FOUND=()
if [ -d "$SCAN_PATH" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && FOUND+=("$f")
  done < <(
    find "$SCAN_PATH" \
      \( -name node_modules -o -name .git -o -name vendor -o -name .venv -o -name target -o -name dist \) -prune -o \
      -type f -print 2>/dev/null \
    | while IFS= read -r p; do
        b="$(basename "$p")"
        case " $KNOWN_LOCKFILES " in
          *" $b "*)
            rel="${p#"$SCAN_PATH"/}"
            [ "$rel" = "$p" ] && rel="$(basename "$p")"
            echo "$rel"
            ;;
        esac
      done | sort -u
  )
fi

# ecosystems present (from found lockfiles)
ecosystems_list() {
  local b eco
  for rel in "${FOUND[@]:-}"; do
    [ -z "$rel" ] && continue
    b="$(basename "$rel")"
    eco="$(lockfile_meta "$b" | cut -d'|' -f1)"
    [ -n "$eco" ] && echo "$eco"
  done | sort -u
}

# ---------------------------------------------------------------------------
# jq present?
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "vuln-audit: jq not found on PATH — cannot parse engine output. Install jq and re-run. (advisory; exit 0)" >&2
  emit_exit failed
fi

# ---------------------------------------------------------------------------
# Engine present?
# ---------------------------------------------------------------------------
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  eco_str="$(ecosystems_list | paste -sd', ' -)"
  [ -z "$eco_str" ] && eco_str="(no recognised lockfiles found)"
  if [ "$OUT_JSON" -eq 1 ]; then
    jq -n --arg path "$SCAN_PATH" --arg eco "$eco_str" \
      '{status:"unavailable", scanned_path:$path, coverage:{found:[],covered:[],skipped:[]}, findings:[], ecosystems_present:$eco, advisory:("osv-scanner not installed; would have scanned: "+$eco)}'
  else
    echo "vuln-audit: status=unavailable"
    echo "  osv-scanner is not installed. Install it: https://google.github.io/osv-scanner/installation/"
    echo "  (e.g. 'go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest' or brew/scoop)"
    echo "  Would have scanned ecosystems: $eco_str"
  fi
  emit_exit unavailable
fi

# ---------------------------------------------------------------------------
# Run the engine.
# ---------------------------------------------------------------------------
RAW="$("$ENGINE" scan --format json --recursive "$SCAN_PATH" 2>/dev/null)"
ENGINE_EXIT=$?

# osv-scanner exit codes: 0=no vulns, 1=vulns, 128=no packages, others=error.
STATUS=""
case "$ENGINE_EXIT" in
  0) STATUS="clean" ;;
  1) STATUS="findings" ;;
  128) STATUS="clean" ;;   # no packages found to scan; not an error
  *) STATUS="failed" ;;
esac

# Validate JSON parseability (a non-error exit with garbage => failed).
if [ "$STATUS" != "failed" ]; then
  if ! printf '%s' "$RAW" | jq -e . >/dev/null 2>&1; then
    # exit 128 commonly emits no JSON body — treat empty as empty-results clean.
    if [ "$ENGINE_EXIT" -eq 128 ] && [ -z "${RAW//[[:space:]]/}" ]; then
      RAW='{"results":[]}'
    else
      STATUS="failed"
    fi
  fi
fi

if [ "$STATUS" = "failed" ]; then
  if [ "$OUT_JSON" -eq 1 ]; then
    jq -n --arg path "$SCAN_PATH" --argjson ec "$ENGINE_EXIT" \
      '{status:"failed", scanned_path:$path, engine_exit:$ec, coverage:{found:[],covered:[],skipped:[]}, findings:[]}'
  else
    echo "vuln-audit: status=failed"
    echo "  osv-scanner exited $ENGINE_EXIT and did not produce parseable results."
    echo "  Re-run manually for diagnostics: $ENGINE scan --recursive \"$SCAN_PATH\""
  fi
  emit_exit failed
fi

# ---------------------------------------------------------------------------
# Coverage buckets: covered = basenames of results[].source.path; skipped = found - covered.
# ---------------------------------------------------------------------------
declare -a COVERED_BASENAMES=()
while IFS= read -r b; do
  [ -n "$b" ] && COVERED_BASENAMES+=("$b")
done < <(printf '%s' "$RAW" | jq -r '[.results[]?.source.path | select(.) ] | .[]' 2>/dev/null \
            | while IFS= read -r sp; do basename "$sp"; done | sort -u)

is_covered() {
  local target="$1"
  for c in "${COVERED_BASENAMES[@]:-}"; do
    [ "$c" = "$target" ] && return 0
  done
  return 1
}

# Build covered/skipped relpaths.
declare -a COVERED=()
declare -a SKIPPED_JSON=()    # json objects {lockfile,reason}
for rel in "${FOUND[@]:-}"; do
  [ -z "$rel" ] && continue
  b="$(basename "$rel")"
  if is_covered "$b"; then
    COVERED+=("$rel")
  else
    reason="$(lockfile_meta "$b" | cut -d'|' -f3)"
    [ -z "$reason" ] && reason="not parsed by osv-scanner in this run"
    SKIPPED_JSON+=("$(jq -n --arg lf "$rel" --arg r "$reason" '{lockfile:$lf, reason:$r}')")
  fi
done

# ---------------------------------------------------------------------------
# Direct-dependency name set (npm only, cheap honest enrichment): union of
# dependencies/devDependencies/optionalDependencies/peerDependencies keys across
# every package.json in the tree.
# ---------------------------------------------------------------------------
DIRECT_NPM_NAMES=""
if [ -d "$SCAN_PATH" ]; then
  while IFS= read -r pj; do
    [ -z "$pj" ] && continue
    names="$(jq -r '[(.dependencies//{}),(.devDependencies//{}),(.optionalDependencies//{}),(.peerDependencies//{})] | add // {} | keys[]?' "$pj" 2>/dev/null)"
    DIRECT_NPM_NAMES="$DIRECT_NPM_NAMES
$names"
  done < <(find "$SCAN_PATH" \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f -name package.json -print 2>/dev/null)
fi
is_direct_npm() {
  printf '%s\n' "$DIRECT_NPM_NAMES" | grep -qxF "$1"
}

# ---------------------------------------------------------------------------
# Normalize findings via jq -> compact JSON lines, then enrich kind/path in bash.
# Severity: prefer database_specific.severity (word); else bucket groups.maxSeverity
# (CVSS numeric); else UNKNOWN. Fixed: first affected fixed event.
# ---------------------------------------------------------------------------
FINDINGS_NDJSON="$(printf '%s' "$RAW" | jq -c '
  def sev_word(v):
    (v.database_specific.severity // empty) as $w
    | if $w then ($w|ascii_downcase)
      else null end;
  def sev_from_cvss($pkg; $vid):
    ([ $pkg.groups[]? | select(.ids[]? == $vid) | .maxSeverity? // empty ] | map(tonumber? // empty) | max) as $s
    | if $s == null then "unknown"
      elif $s >= 9.0 then "critical"
      elif $s >= 7.0 then "high"
      elif $s >= 4.0 then "moderate"
      elif $s > 0 then "low"
      else "unknown" end;
  [ .results[]? as $r
    | $r.packages[]? as $p
    | $p.vulnerabilities[]? as $v
    | {
        package: $p.package.name,
        version: $p.package.version,
        ecosystem: ($p.package.ecosystem // "unknown"),
        id: $v.id,
        cve: ([ $v.aliases[]? | select(startswith("CVE-")) ] | first // null),
        severity: ( sev_word($v) // sev_from_cvss($p; $v.id) ),
        fixed_version: ([ $v.affected[]?.ranges[]?.events[]?.fixed // empty ] | first // null),
        source: ($r.source.path // null)
      }
  ] | .[]
' 2>/dev/null)"

# Assemble enriched findings JSON array + count after severity floor.
FLOOR_RANK=0
[ -n "$SEVERITY_FLOOR" ] && FLOOR_RANK="$(sev_rank "$SEVERITY_FLOOR")"

declare -a FINDING_OBJS=()
FINDINGS_COUNT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  name="$(printf '%s' "$line" | jq -r '.package')"
  eco="$(printf '%s' "$line" | jq -r '.ecosystem')"
  sev="$(printf '%s' "$line" | jq -r '.severity')"
  # severity floor
  if [ "$FLOOR_RANK" -gt 0 ]; then
    r="$(sev_rank "$sev")"
    [ "$r" -lt "$FLOOR_RANK" ] && continue
  fi
  # dependency kind + remediation path
  kind="unknown"
  path="no direct remediation path known"
  case "$eco" in
    npm*)
      if is_direct_npm "$name"; then
        kind="direct"; path="$name"
      else
        kind="transitive"
      fi
      ;;
  esac
  obj="$(printf '%s' "$line" | jq -c --arg k "$kind" --arg p "$path" \
        'del(.source) + {dependency_kind:$k, remediation_path:$p}')"
  FINDING_OBJS+=("$obj")
  FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
done <<< "$FINDINGS_NDJSON"

# Status after floor: if floor removed all findings, status becomes clean.
if [ "$STATUS" = "findings" ] && [ "$FINDINGS_COUNT" -eq 0 ]; then
  STATUS="clean"
fi

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------
# helper: arrays -> json
arr_to_json() { if [ "$#" -eq 0 ]; then echo "[]"; else printf '%s\n' "$@" | jq -R . | jq -s .; fi; }
objs_to_json() { if [ "$#" -eq 0 ]; then echo "[]"; else printf '%s\n' "$@" | jq -s .; fi; }

FOUND_JSON="$(arr_to_json "${FOUND[@]:-}")"
COVERED_JSON="$(arr_to_json "${COVERED[@]:-}")"
SKIPPED_ARR_JSON="$(objs_to_json "${SKIPPED_JSON[@]:-}")"
FINDINGS_JSON="$(objs_to_json "${FINDING_OBJS[@]:-}")"
ECO_PRESENT="$(ecosystems_list | paste -sd', ' -)"

if [ "$OUT_JSON" -eq 1 ]; then
  jq -n \
    --arg status "$STATUS" \
    --arg path "$SCAN_PATH" \
    --arg eco "$ECO_PRESENT" \
    --argjson found "$FOUND_JSON" \
    --argjson covered "$COVERED_JSON" \
    --argjson skipped "$SKIPPED_ARR_JSON" \
    --argjson findings "$FINDINGS_JSON" \
    '{status:$status, scanned_path:$path, ecosystems_present:$eco,
      coverage:{found:$found, covered:$covered, skipped:$skipped},
      findings:$findings}'
else
  echo "vuln-audit: status=$STATUS"
  echo "  scanned: $SCAN_PATH"
  echo "  coverage: found=$(echo "$FOUND_JSON" | jq 'length') covered=$(echo "$COVERED_JSON" | jq 'length') skipped=$(echo "$SKIPPED_ARR_JSON" | jq 'length')"
  if [ "$(echo "$SKIPPED_ARR_JSON" | jq 'length')" -gt 0 ]; then
    echo "  skipped/unsupported:"
    echo "$SKIPPED_ARR_JSON" | jq -r '.[] | "    - \(.lockfile): \(.reason)"'
  fi
  if [ "$STATUS" = "clean" ]; then
    echo "  no known-vulnerable dependencies found in: ${ECO_PRESENT:-(nothing scanned)}"
  elif [ "$STATUS" = "findings" ]; then
    echo "  findings ($FINDINGS_COUNT):"
    echo "$FINDINGS_JSON" | jq -r '.[] |
      "    - [\(.severity)] \(.package)@\(.version) (\(.ecosystem), \(.dependency_kind))\n        \(.id)\(if .cve then " / "+.cve else "" end)\n        fix: \(.fixed_version // "no fix published")  path: \(.remediation_path)"'
  fi
fi

emit_exit "$STATUS"
