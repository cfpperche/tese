#!/usr/bin/env bash
# Scenario: --json emits a deterministic, jq-parseable doc with the expected keys.
source "$(dirname "$0")/_lib.sh"
echo "07-json-shape"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

FIX="$(fixture <<JSON
{ "results": [ {
  "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" },
  "packages": [ {
    "package": { "name": "minimist", "version": "1.2.0", "ecosystem": "npm" },
    "vulnerabilities": [ {
      "id": "GHSA-vh95-rmgr-6w4m", "aliases": ["CVE-2020-7598"],
      "database_specific": { "severity": "MODERATE" },
      "affected": [ { "ranges": [ { "type": "SEMVER", "events": [ {"introduced":"0"},{"fixed":"1.2.3"} ] } ] } ]
    } ],
    "groups": [ { "ids": ["GHSA-vh95-rmgr-6w4m"], "maxSeverity": "5.6" } ]
  } ]
} ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=1
OUT="$(bash "$TOOL" --json "$WORK/proj")"

assert_eq "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; echo $?)" "0" "output is valid JSON"
assert_eq "$(echo "$OUT" | jq -r '.status')" "findings" "status key present"
assert_eq "$(echo "$OUT" | jq -r 'has("coverage") and has("findings") and has("scanned_path")')" "true" "top-level keys present"
assert_eq "$(echo "$OUT" | jq -r '.findings[0].package')" "minimist" "finding package field"
assert_eq "$(echo "$OUT" | jq -r '.findings[0].severity')" "moderate" "finding severity field (lowercased)"
assert_eq "$(echo "$OUT" | jq -r '.findings[0].fixed_version')" "1.2.3" "finding fixed_version field"
assert_eq "$(echo "$OUT" | jq -r '.findings[0] | has("dependency_kind") and has("remediation_path")')" "true" "finding carries kind + path"

finish
