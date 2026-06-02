#!/usr/bin/env bash
# serve-hifi.sh — best-effort HTTP server launcher for /product § Phase 4 visual check.
#
# The Playwright MCP refuses to navigate `file://` URLs, so the visual-check loop in
# SKILL.md serves the hi-fi screen directory over HTTP on a free localhost port, then
# `browser_navigate`s to `http://127.0.0.1:<port>/<NN>-<name>.html`.
#
# Usage:
#   bash .claude/skills/product/scripts/serve-hifi.sh <serve-dir> &
#   read -r line       # caller captures the first stdout line
#   # line is either "READY <port>" or a fallthrough that means failure
#
# Output:
#   On success — single line "READY <port>" on stdout; script blocks until the
#     caller sends a signal (e.g. `kill %1`) or the underlying http.server exits.
#   On failure — `not-available: <reason>` on stderr, non-zero exit, no READY line.
#
# Caller responsibilities:
#   - background the script (trailing `&`) so the caller doesn't block
#   - read the first stdout line to obtain the port (or detect failure via exit/stderr)
#   - send SIGTERM / `kill %1` to teardown when done; the trap reaps the child
#
# Failure modes (all best-effort — never blocks the pipeline):
#   - python3 missing                          → not-available: python3 not found
#   - free-port probe fails                    → not-available: free-port probe failed
#   - serve dir missing or unreadable          → not-available: serve directory missing
#   - http.server doesn't bind within 5s       → not-available: server did not bind within 5s
#
# All four cases produce a non-zero exit; SKILL.md catches and degrades to the
# pre-existing `visual-gate-skipped: <reason>` advisory path.

set -uo pipefail

SERVE_DIR="${1:-}"
if [ -z "$SERVE_DIR" ] || [ ! -d "$SERVE_DIR" ]; then
  echo "not-available: serve directory missing (arg: '$SERVE_DIR')" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "not-available: python3 not found" >&2
  exit 1
fi

# Pick a free ephemeral port. Bind+release in a single Python invocation; in
# practice the kernel does not rebind a just-released port before the http.server
# subprocess below claims it, but the polling loop below catches the rare race.
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)" || {
  echo "not-available: free-port probe failed" >&2
  exit 1
}

if [ -z "$PORT" ]; then
  echo "not-available: free-port probe returned empty" >&2
  exit 1
fi

# Start http.server in background — its stdout/stderr are swallowed so the
# caller's `read` against THIS script's stdout only sees the READY line.
python3 -m http.server "$PORT" --bind 127.0.0.1 -d "$SERVE_DIR" >/dev/null 2>&1 &
SERVER_PID=$!

# Teardown discipline: kill the child on any exit path (signal, error, normal).
trap 'kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; exit 0' TERM INT
trap 'kill "$SERVER_PID" 2>/dev/null' EXIT

# Poll until the port responds (5s @ 100ms = 50 attempts). `/dev/tcp` is bash-
# native and avoids requiring `nc` / `curl` for the readiness probe.
for _ in $(seq 1 50); do
  if (exec 3<>/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null; then
    exec 3>&- 2>/dev/null || true
    echo "READY $PORT"
    # Block until the child exits OR the trap fires from a signal.
    wait "$SERVER_PID"
    exit 0
  fi
  sleep 0.1
done

# Timeout — server never came up; teardown via EXIT trap.
echo "not-available: server did not bind within 5s" >&2
exit 1
