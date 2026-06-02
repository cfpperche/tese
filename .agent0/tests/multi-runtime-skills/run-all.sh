#!/usr/bin/env bash
set -uo pipefail; cd "$(dirname "$0")"
F=0
for t in [0-9][0-9]-*.sh; do [ -f "$t" ] || continue; bash "$t" || F=$((F+1)); echo; done
[ "$F" -eq 0 ] && echo "=== multi-runtime-skills: ALL PASS ===" || { echo "=== multi-runtime-skills: $F FAILED ==="; exit 1; }
