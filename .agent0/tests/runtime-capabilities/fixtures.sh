#!/usr/bin/env bash
# Shared fixtures for runtime-capabilities drift tests.

set -euo pipefail

runtime_caps_write_valid_fixture() {
  local root="$1"
  local managed='## Runtime capabilities

See `.agent0/context/rules/runtime-capabilities.md`.
'

  mkdir -p "$root/.agent0/context/rules"

  cat > "$root/CLAUDE.md" <<EOF
# Claude

<!-- AGENT0:BEGIN -->
$managed<!-- AGENT0:END -->
EOF

  cat > "$root/AGENTS.md" <<EOF
# Agents

<!-- AGENT0:BEGIN -->
$managed<!-- AGENT0:END -->
EOF

  cat > "$root/.agent0/context/rules/runtime-capabilities.md" <<'EOF'
# Runtime capabilities

## Status vocabulary

- `native`
- `native-opt-in`
- `convention`
- `read-only`
- `planned`
- `unsupported`

## Capability matrix

| Capability | Claude Code | Codex CLI | Owner files | Notes |
| --- | --- | --- | --- | --- |
| instruction entrypoints | `native` | `native` | `CLAUDE.md`; `AGENTS.md` | ok |
| session handoff | `native` | `native` | `.agent0/HANDOFF.md`; `.agent0/hooks/session-start.sh`; `.agent0/hooks/session-stop.sh`; `.agent0/hooks/session-track-edits.sh`; `.codex/hooks.json` | ok |
| SDD | `native` | `convention` | `.agent0/skills/sdd/SKILL.md` | ok |
| debate | `native` | `planned: 091-sdd-debate-runner` | `.agent0/skills/sdd/templates/debate.md.tmpl` | ok |
| lifecycle hooks | `native` | `unsupported` | `.claude/hooks/*.sh` | ok |
| delegation/subagents | `native` | `unsupported` | `.agent0/context/rules/delegation.md` | ok |
| MCP recipes | `native-opt-in` | `native-opt-in` | `.mcp.json.example`; `.codex/config.toml.example` | ok |
| browser auth | `native-opt-in` | `native-opt-in` | `.agent0/context/rules/browser-auth.md` | ok |
| image generation | `native-opt-in` | `convention` | `.agent0/context/rules/image-gen.md` | ok |
| memory | `native` | `native-opt-in` | `.agent0/memory/MEMORY.md` | ok |
| harness sync | `native-opt-in` | `native-opt-in` | `.agent0/tools/sync-harness.sh` | ok |
| customization/sync surfaces | `native` | `convention` | `AGENTS.override.md` | ok |
EOF
}
