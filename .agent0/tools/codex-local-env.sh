#!/usr/bin/env bash
# Load project-local Codex MCP environment and exec Codex from the repo root.
# This avoids OS-level exports for secrets like FAL_KEY and DATABASE_URL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.codex/.env.local"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

exec codex -C "$ROOT" "$@"
