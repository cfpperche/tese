---
name: claude-exec
description: Launch the local Claude Code CLI as a bounded non-interactive subprocess and capture its output. Use when Codex CLI or another non-Claude runtime needs a second-model probe, review, or continuation through `claude -p` with explicit parameters such as permission mode, model, tool allowlists, add-dir, resume id, JSON capture, or output path. The permission mode is required with no default; the helper refuses to run without it. Not for proving interactive Claude TUI hook behavior.
argument-hint: "--permission-mode <default|plan|acceptEdits|bypassPermissions|dontAsk|auto> [--allow-writes] [--model <model>] [--reasoning-effort <low|medium|high|xhigh|max>] [--allowedTools <list>] [--disallowedTools <list>] [--add-dir <repo-relative-dir>] [--bare] [--resume <session-id>] [--json] [--output <path>] [--slug <slug>] (--task <prompt> | --task-file <path> | prompt via stdin)"
license: MIT
compatibility: Compatible with agentskills.io-compatible runtimes that can run bash and have the Claude Code CLI (`claude`) plus `jq` installed and authenticated. The helper invokes `claude` directly and writes artifacts under `.agent0/.runtime-state/claude-exec/` by default.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.1"
---

# /claude-exec — Claude Code CLI bridge

Launch the Claude Code CLI non-interactively from the current repo and capture the result. This is the symmetric sibling of `codex-exec` — same purpose (one runtime invokes another model's brain as a bounded subprocess, files out), different mechanics built around `claude -p`. It is a subprocess bridge, not native shared-memory delegation: the parent agent (typically Codex CLI) supplies a bounded prompt, Claude runs in its own session, and the parent reads the produced artifacts.

## When To Use — 🔓 Medium freedom

Use this when a task benefits from a separate Claude pass driven by a non-Claude runtime:

- read-only critique of a plan, spec, diff, or design tradeoff
- bounded repo probe where Claude should inspect files and report back
- continuation of a known Claude session via `--resume <session-id>`
- JSONL event capture for eval-style inspection with `--json`

Do not use this to prove interactive Claude TUI lifecycle-hook behavior. `claude -p` is non-interactive and is not the same proof surface as the live TUI for some Agent0 hooks.

## Invocation — 🔒 Low freedom

Call the helper directly; it owns argument normalization and output capture. **`--permission-mode` is required — the helper is fail-closed and refuses to run without it.**

```bash
bash .agent0/skills/claude-exec/scripts/claude-exec.sh \
  --permission-mode default --allowedTools "Read Grep Glob" \
  --task "Review docs/specs/129-claude-exec/spec.md for one concrete risk."
```

Supported parameters:

- `--permission-mode <mode>` — **required.** Forwarded verbatim to `claude --permission-mode` (`default | plan | acceptEdits | bypassPermissions | dontAsk | auto`). No default.
- `--allow-writes` — **required confirmation for write/execute-capable modes** (`acceptEdits`, `bypassPermissions`, `dontAsk`, `auto`). Without it those modes are refused fail-closed; `default` and `plan` are the read-only floor and need no confirmation. This makes "read-only is the floor" an invariant of the bridge, not just caller discipline.
- `--task <text>` — prompt sent to Claude.
- `--task-file <path>` — read prompt text from a file.
- stdin — if no task is passed and stdin is piped, stdin becomes the prompt.
- `--allowedTools <list>` / `--disallowedTools <list>` — space/comma-separated tool names. Compose read-only review with `--permission-mode default --allowedTools "Read Grep Glob"`.
- `--model <model>` — maps to Claude `--model`.
- `--reasoning-effort <low|medium|high|xhigh|max>` — maps to Claude `--effort` (alias: `--effort`). Validated against the allowed set; recorded in `metadata.json` / `runs.jsonl`.
- `--add-dir <dir>` — extra directory Claude may access; must resolve under the repo root.
- `--bare` — opt-in: skip hooks/CLAUDE.md/auto-memory for a cheap isolated probe. Note: forces auth to strictly `ANTHROPIC_API_KEY` (breaks OAuth/subscription); off by default so reviews keep project context.
- `--resume <session-id>` — continue an existing Claude session via `claude -p --resume <id>`.
- `--json` — use `--output-format stream-json` and capture JSONL to `events.jsonl`.
- `--output <path>` — path for `last-message.md`; must stay under the state dir.
- `--slug <slug>` — run-directory slug for default output paths.

There is no read-only/write/danger abstraction: the helper passes the native permission mode through. The one safety invariant layered on top is the floor gate — to let Claude edit or execute, pass a write-capable mode (e.g. `--permission-mode acceptEdits`) **and** the explicit `--allow-writes` confirmation. `default`/`plan` run without it.

```bash
# Refused — write-capable mode without confirmation:
bash .agent0/skills/claude-exec/scripts/claude-exec.sh --permission-mode acceptEdits --task "..."
#   claude-exec error: permission mode 'acceptEdits' is write-capable; pass --allow-writes to confirm intent
```

## Flow — 🔒 Low freedom

1. Build a concise task prompt with scope, constraints, and the expected deliverable.
2. Run `scripts/claude-exec.sh` with `--permission-mode` plus the needed parameters.
3. Relay the helper summary: `exit_code`, `run_dir`, `last_message`, `session_id`, and `metadata`.
4. If `exit_code` is non-zero, surface stderr and treat the result as failed or partial.
5. If the run succeeded, read `last-message.md` when the user needs the Claude answer inline; otherwise provide the artifact path. Use the captured `session_id` to `--resume` later.

## Examples — 🔓 Medium freedom

```bash
# Read-only review (permission-mode required; allowlist makes it inspect-only).
bash .agent0/skills/claude-exec/scripts/claude-exec.sh \
  --permission-mode default --allowedTools "Read Grep Glob" \
  --task "Review docs/specs/129-claude-exec/plan.md for implementation risks."

# Capture JSONL events and pin a model.
bash .agent0/skills/claude-exec/scripts/claude-exec.sh \
  --permission-mode default --allowedTools "Read Grep Glob" \
  --model claude-opus-4-8 --json \
  --task "Inspect .agent0/skills/claude-exec/SKILL.md and report compliance risks only."

# Continue a prior Claude session (session id from a previous run's metadata).
bash .agent0/skills/claude-exec/scripts/claude-exec.sh \
  --permission-mode default --allowedTools "Read Grep Glob" \
  --resume 00000000-0000-0000-0000-000000000000 \
  --task "Continue from the previous critique and focus on missing tests."

# Permit file edits intentionally (write-capable mode requires --allow-writes).
bash .agent0/skills/claude-exec/scripts/claude-exec.sh \
  --permission-mode acceptEdits --allow-writes \
  --task "Apply the smallest docs-only correction needed in docs/specs/129-claude-exec/spec.md."
```

## Eval Scenarios

### Eval 1: Fail-closed permission mode

**Input:** The parent invokes `claude-exec` with `--task` but no `--permission-mode`.

**Expected:** The helper exits non-zero with a usage error naming the valid modes, BEFORE invoking Claude, and creates no run directory.

**Failure indicators:** The helper assumes a default mode, runs Claude anyway, or leaves a success-looking output directory.

### Eval 2: Default read-only probe

**Input:** The parent invokes `claude-exec` with `--permission-mode default --allowedTools "Read Grep Glob" --task "Review <spec> for one concrete risk."`

**Expected:** The helper runs `claude -p --permission-mode default --output-format json --allowedTools "Read Grep Glob"`, sends the prompt through stdin, extracts `last-message.md` and `session_id` via `jq`, writes `metadata.json` + `stderr.txt`, appends `runs.jsonl`, and reports the paths and exit code.

**Failure indicators:** The helper passes the prompt as a positional arg (variadic flags swallow it), grants write access, builds the command via `eval`, or reports success without a last-message artifact.

### Eval 3: Resume with explicit capture

**Input:** The parent invokes `claude-exec` with `--permission-mode default --resume <session-id> --json --task "Continue the previous critique."`

**Expected:** The helper calls `claude -p --resume <session-id>`, uses `--output-format stream-json --verbose`, captures JSONL to `events.jsonl`, records the resumed id and the returned `session_id` in metadata, and exits with Claude's exit code.

**Failure indicators:** The helper starts a fresh session, streams JSONL inline instead of writing an artifact, or masks a non-zero Claude exit.

## Notes

- The helper invokes `claude` directly; no launcher. `claude` self-discovers config (`~/.claude`, `.claude/settings.json`) and anchors on cwd.
- `jq` is a hard dependency — Claude has no `--output-last-message`, so the final message is extracted from the JSON output (`select(.type=="result")|.result`).
- The prompt is always passed via stdin so variadic flags (`--allowedTools`, `--add-dir`) never swallow it.
- Runtime artifacts are gitignored by the existing `.agent0/.runtime-state/*` rule. Set `CLAUDE_EXEC_STATE_DIR` only in tests or local experiments that need a temporary artifact directory.
- The aggregate run log is `runs.jsonl`; each run also gets `metadata.json` carrying `session_id` for later `--resume`.
- This bridge is symmetric to `codex-exec` but deliberately not a clone — see `docs/specs/129-claude-exec/`.
