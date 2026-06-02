---
name: codex-exec
description: Launch the local Codex CLI as a bounded non-interactive subprocess and capture its output. Use when Claude Code or another agent needs a second-model probe, review, or continuation through `codex exec` with explicit parameters such as model, profile, sandbox, cwd, resume id, JSON capture, or output path. Defaults to read-only sandbox; pass a non-read-only sandbox only when file edits are intended. Not for proving interactive Codex TUI hook behavior or native subagent semantics.
argument-hint: "[--model <model>] [--profile <profile>] [--sandbox read-only|workspace-write|danger-full-access] [--cwd <repo-relative-dir>] [--resume <session-id>] [--json] [--output <path>] (--task <prompt> | --task-file <path> | prompt via stdin)"
license: MIT
compatibility: Compatible with agentskills.io-compatible runtimes that can run bash and have Codex CLI installed/authenticated. The helper invokes the repo-local `.agent0/tools/codex-local-env.sh` launcher and writes artifacts under `.agent0/.runtime-state/codex-exec/` by default.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.1"
---

# /codex-exec — Codex CLI bridge

Launch Codex CLI non-interactively from the current repo and capture the result. This is a subprocess bridge, not native shared-memory delegation: the parent agent supplies a bounded prompt, Codex runs in its own session, and the parent reads the produced artifacts.

## When To Use — 🔓 Medium freedom

Use this when a task benefits from a separate Codex pass:

- read-only critique of a plan, spec, diff, or design tradeoff
- bounded repo probe where Codex should inspect files and report back
- continuation of a known Codex session via `--resume <session-id>`
- JSONL event capture for eval-style inspection with `--json`

Do not use this to prove interactive Codex TUI lifecycle-hook behavior. `codex exec` is not the same proof surface as the live TUI for some Agent0 hooks.

## Invocation — 🔒 Low freedom

Call the helper directly; it owns argument normalization and output capture:

```bash
bash .agent0/skills/codex-exec/scripts/codex-exec.sh \
  --task "Review docs/specs/128-codex-exec-skill/spec.md for acceptance gaps."
```

Supported parameters:

- `--task <text>` — prompt sent to Codex.
- `--task-file <path>` — read prompt text from a file.
- stdin — if no task is passed and stdin is piped, stdin becomes the prompt.
- `--model <model>` — maps to Codex `--model`.
- `--profile <profile>` — maps to Codex `--profile`.
- `--reasoning-effort <minimal|low|medium|high|xhigh>` — maps to Codex `-c model_reasoning_effort=<level>`. Validated against the allowed set; recorded in `metadata.json` / `runs.jsonl`.
- `--sandbox read-only|workspace-write|danger-full-access` — default is `read-only`.
- `--cwd <dir>` — working root for Codex; must resolve under the repo root.
- `--resume <session-id>` — calls `codex exec resume <session-id> -`.
- `--json` — captures Codex JSONL stdout to `events.jsonl`.
- `--output <path>` — path for Codex's `--output-last-message`; relative paths resolve under `.agent0/.runtime-state/codex-exec/`, and absolute paths must also stay under that state directory.
- `--slug <slug>` — optional run-directory slug for default output paths.

Pass `--sandbox workspace-write` only when Codex is expected to edit files. The helper never grants write access by default.

## Flow — 🔒 Low freedom

1. Build a concise task prompt with scope, constraints, and the expected deliverable.
2. Run `scripts/codex-exec.sh` with the needed parameters.
3. Relay the helper summary: `exit_code`, `run_dir`, `last_message`, and `metadata`.
4. If `exit_code` is non-zero, surface stderr and treat the result as failed or partial.
5. If the run succeeded, read `last-message.md` when the user needs the Codex answer inline; otherwise provide the artifact path.

## Examples — 🔓 Medium freedom

```bash
# Default read-only review.
bash .agent0/skills/codex-exec/scripts/codex-exec.sh \
  --task "Review docs/specs/128-codex-exec-skill/plan.md for implementation risks."

# Capture JSONL events and use an explicit model.
bash .agent0/skills/codex-exec/scripts/codex-exec.sh \
  --model gpt-5-codex --json \
  --task "Inspect .agent0/skills/codex-exec/SKILL.md and report compliance risks only."

# Continue a prior Codex session.
bash .agent0/skills/codex-exec/scripts/codex-exec.sh \
  --resume 00000000-0000-0000-0000-000000000000 \
  --task "Continue from the previous critique and focus on missing tests."

# Permit file edits intentionally.
bash .agent0/skills/codex-exec/scripts/codex-exec.sh \
  --sandbox workspace-write \
  --task "Apply the smallest docs-only correction needed in docs/specs/128-codex-exec-skill/spec.md."
```

## Eval Scenarios

### Eval 1: Default read-only probe

**Input:** The parent agent needs Codex to review a spec and invokes `codex-exec` with only `--task "Review docs/specs/128-codex-exec-skill/spec.md for one concrete risk."`

**Expected:** The helper runs through `.agent0/tools/codex-local-env.sh` with `--sandbox read-only`, sends the prompt through stdin, writes `last-message.md`, `metadata.json`, `stdout.txt`, `stderr.txt`, and appends `runs.jsonl`. The parent reports the paths and exit code.

**Failure indicators:** The helper grants write access by default, builds the command through `eval`, drops the prompt instead of passing stdin, or reports success without a last-message artifact.

### Eval 2: Resume with explicit capture

**Input:** The parent agent invokes `codex-exec` with `--resume <session-id> --json --task "Continue the previous critique."`

**Expected:** The helper calls `codex exec resume <session-id> -`, places resume options after `resume`, captures JSONL stdout to `events.jsonl`, records the resume id in metadata, and exits with Codex's exit code.

**Failure indicators:** The helper starts a fresh session instead of resume, puts the prompt before the session id, streams JSONL inline instead of writing an artifact, or masks a non-zero Codex exit.

## Notes

- The helper calls `.agent0/tools/codex-local-env.sh`, which loads `.codex/.env.local` and starts from the repo root.
- Runtime artifacts are gitignored by the existing `.agent0/.runtime-state/*` rule. Set `CODEX_EXEC_STATE_DIR` only in tests or local experiments that need a temporary artifact directory.
- The aggregate run log is `runs.jsonl`; each run also gets `metadata.json`.
