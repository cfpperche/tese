#!/usr/bin/env bash
# Scenario: Codex MCP template is parseable TOML with expected field shapes.

set -euo pipefail

AGENT0_ROOT="${AGENT0_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TEMPLATE="$AGENT0_ROOT/.codex/config.toml.example"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL: python3 required for TOML shape validation\n'
  exit 1
fi

python3 - "$TEMPLATE" <<'PY'
import sys

try:
    import tomllib
except ModuleNotFoundError:
    raise SystemExit("FAIL: python3 tomllib unavailable")

path = sys.argv[1]
with open(path, "rb") as f:
    data = tomllib.load(f)

servers = data.get("mcp_servers")
if not isinstance(servers, dict):
    raise SystemExit("FAIL: missing mcp_servers table")

required = ["playwright", "chrome-devtools", "dbhub", "laravel-boost", "next-devtools", "fal-ai"]
missing = [name for name in required if name not in servers]
if missing:
    raise SystemExit(f"FAIL: missing servers: {', '.join(missing)}")

for name in required:
    if servers[name].get("enabled") is not False:
        raise SystemExit(f"FAIL: {name} is not disabled by default")

stdio = ["playwright", "chrome-devtools", "dbhub", "laravel-boost", "next-devtools"]
for name in stdio:
    if not isinstance(servers[name].get("command"), str):
        raise SystemExit(f"FAIL: {name} missing stdio command")
    if not isinstance(servers[name].get("args"), list):
        raise SystemExit(f"FAIL: {name} missing stdio args list")

if servers["dbhub"].get("env_vars") != ["DATABASE_URL"]:
    raise SystemExit("FAIL: dbhub env_vars shape mismatch")

fal = servers["fal-ai"]
if fal.get("url") != "https://mcp.fal.ai/mcp":
    raise SystemExit("FAIL: fal-ai URL mismatch")
if fal.get("bearer_token_env_var") != "FAL_KEY":
    raise SystemExit("FAIL: fal-ai bearer_token_env_var mismatch")
if "http_headers" in fal or "env_http_headers" in fal:
    raise SystemExit("FAIL: fal-ai template must not use static/env HTTP header maps")

print("PASS: 02-template-codex-config-shape")
PY
