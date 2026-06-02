#!/usr/bin/env bash
# Scenario: --exit-code maps findings->1; default run stays 0 (never a gate).
source "$(dirname "$0")/_lib.sh"
echo "08-exit-code-optin"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"

FIX="$(fixture <<JSON
{ "results": [ {
  "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" },
  "packages": [ {
    "package": { "name": "lodash", "version": "4.17.20", "ecosystem": "npm" },
    "vulnerabilities": [ { "id": "GHSA-35jh-r3h4-6jhm", "aliases": ["CVE-2021-23337"], "database_specific": { "severity": "HIGH" }, "affected": [] } ],
    "groups": [ { "ids": ["GHSA-35jh-r3h4-6jhm"], "maxSeverity": "7.2" } ]
  } ]
} ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=1

bash "$TOOL" "$WORK/proj" >/dev/null; RC_DEFAULT=$?
bash "$TOOL" --exit-code "$WORK/proj" >/dev/null; RC_OPTIN=$?

assert_eq "$RC_DEFAULT" "0" "default run with findings exits 0 (advisory family)"
assert_eq "$RC_OPTIN" "1" "--exit-code with findings exits 1"

# clean + --exit-code stays 0
FIX2="$(fixture <<JSON
{ "results": [ { "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" }, "packages": [] } ] }
JSON
)"
export FAKE_OSV_JSON="$FIX2" FAKE_OSV_EXIT=0
bash "$TOOL" --exit-code "$WORK/proj" >/dev/null; RC_CLEAN=$?
assert_eq "$RC_CLEAN" "0" "--exit-code with clean exits 0"

finish
