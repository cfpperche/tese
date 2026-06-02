#!/usr/bin/env bash
# Scenario: engine returns vulns -> status=findings, per-finding fields present, exit 0.
source "$(dirname "$0")/_lib.sh"
echo "01-findings-status"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

FIX="$(fixture <<JSON
{ "results": [ {
  "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" },
  "packages": [ {
    "package": { "name": "lodash", "version": "4.17.20", "ecosystem": "npm" },
    "vulnerabilities": [ {
      "id": "GHSA-35jh-r3h4-6jhm",
      "aliases": ["CVE-2021-23337"],
      "database_specific": { "severity": "HIGH" },
      "affected": [ { "ranges": [ { "type": "SEMVER", "events": [ {"introduced":"0"}, {"fixed":"4.17.21"} ] } ] } ]
    } ],
    "groups": [ { "ids": ["GHSA-35jh-r3h4-6jhm"], "maxSeverity": "7.2" } ]
  } ]
} ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=1
OUT="$(bash "$TOOL" "$WORK/proj")"; RC=$?

assert_eq "$RC" "0" "default exit is 0 even with findings"
assert_contains "$OUT" "status=findings" "status is findings"
assert_contains "$OUT" "lodash@4.17.20" "package + version surfaced"
assert_contains "$OUT" "GHSA-35jh-r3h4-6jhm" "advisory id surfaced"
assert_contains "$OUT" "CVE-2021-23337" "CVE alias surfaced"
assert_contains "$OUT" "high" "severity word surfaced"
assert_contains "$OUT" "4.17.21" "fixed version surfaced"

finish
