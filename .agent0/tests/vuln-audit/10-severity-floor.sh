#!/usr/bin/env bash
# Scenario: --severity high filters out moderate findings; status reflects survivors.
source "$(dirname "$0")/_lib.sh"
echo "10-severity-floor"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

FIX="$(fixture <<JSON
{ "results": [ {
  "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" },
  "packages": [
    { "package": { "name": "hi-sev", "version": "1.0.0", "ecosystem": "npm" },
      "vulnerabilities": [ { "id": "GHSA-high", "aliases": [], "database_specific": { "severity": "HIGH" }, "affected": [] } ],
      "groups": [ { "ids": ["GHSA-high"], "maxSeverity": "8.1" } ] },
    { "package": { "name": "mod-sev", "version": "1.0.0", "ecosystem": "npm" },
      "vulnerabilities": [ { "id": "GHSA-mod", "aliases": [], "database_specific": { "severity": "MODERATE" }, "affected": [] } ],
      "groups": [ { "ids": ["GHSA-mod"], "maxSeverity": "5.0" } ] }
  ]
} ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=1

OUT_ALL="$(bash "$TOOL" --json "$WORK/proj")"
assert_eq "$(echo "$OUT_ALL" | jq -r '.findings | length')" "2" "no floor: both findings present"

OUT_HIGH="$(bash "$TOOL" --json --severity high "$WORK/proj")"
assert_eq "$(echo "$OUT_HIGH" | jq -r '.findings | length')" "1" "--severity high keeps only the high finding"
assert_eq "$(echo "$OUT_HIGH" | jq -r '.findings[0].package')" "hi-sev" "survivor is the high one"

finish
