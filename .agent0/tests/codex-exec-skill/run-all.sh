#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

"$ROOT/01-default-read-only.sh"
"$ROOT/02-parameter-mapping.sh"
"$ROOT/03-resume.sh"
"$ROOT/04-missing-codex.sh"
"$ROOT/05-reasoning-effort.sh"
