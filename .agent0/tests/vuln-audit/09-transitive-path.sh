#!/usr/bin/env bash
# Scenario: direct dep -> kind=direct + path=name; non-direct -> transitive + honest
# "no direct remediation path known".
source "$(dirname "$0")/_lib.sh"
echo "09-transitive-path"

mkdir -p "$WORK/proj"
: > "$WORK/proj/package-lock.json"
cat > "$WORK/proj/package.json" <<'PJ'
{ "name": "demo", "dependencies": { "express": "^4.0.0" } }
PJ

# express is a direct dep; ms is transitive-only (not in package.json).
FIX="$(fixture <<JSON
{ "results": [ {
  "source": { "path": "$WORK/proj/package-lock.json", "type": "lockfile" },
  "packages": [
    { "package": { "name": "express", "version": "4.0.0", "ecosystem": "npm" },
      "vulnerabilities": [ { "id": "GHSA-aaaa", "aliases": ["CVE-1111"], "database_specific": { "severity": "HIGH" }, "affected": [] } ],
      "groups": [ { "ids": ["GHSA-aaaa"], "maxSeverity": "7.5" } ] },
    { "package": { "name": "ms", "version": "0.7.0", "ecosystem": "npm" },
      "vulnerabilities": [ { "id": "GHSA-bbbb", "aliases": ["CVE-2222"], "database_specific": { "severity": "MODERATE" }, "affected": [] } ],
      "groups": [ { "ids": ["GHSA-bbbb"], "maxSeverity": "5.0" } ] }
  ]
} ] }
JSON
)"

export FAKE_OSV_JSON="$FIX" FAKE_OSV_EXIT=1
OUT="$(bash "$TOOL" --json "$WORK/proj")"

assert_eq "$(echo "$OUT" | jq -r '.findings[] | select(.package=="express") | .dependency_kind')" "direct" "express is direct"
assert_eq "$(echo "$OUT" | jq -r '.findings[] | select(.package=="express") | .remediation_path')" "express" "direct dep path = its own name"
assert_eq "$(echo "$OUT" | jq -r '.findings[] | select(.package=="ms") | .dependency_kind')" "transitive" "ms is transitive"
assert_eq "$(echo "$OUT" | jq -r '.findings[] | select(.package=="ms") | .remediation_path')" "no direct remediation path known" "transitive path honest-unknown"

finish
