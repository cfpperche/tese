#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

"$ROOT/01-init.sh"
"$ROOT/02-check-legality.sh"
"$ROOT/03-advance-roundrobin.sh"
"$ROOT/04-append-turn-single-writer.sh"
"$ROOT/05-state-readout.sh"
"$ROOT/06-synthesis-status.sh"
