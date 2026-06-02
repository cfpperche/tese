# Status & doctor

Two on-demand, text-first shell tools that make the **live Agent0 harness state** visible and checkable from a single command — the transferable kernel of the "Sentinel" host-operations idea (`opus-domini/sentinel`) ported to a repo harness instead of a host. `status` answers *"where does my work stand?"*; `doctor` answers *"is this harness wired and recoverable?"*. Both are runtime-neutral pure bash, invocable identically under Claude Code, Codex CLI, or by a human.

See `docs/specs/137-agent0-status/` for the full spec, plan, and the Codex cross-model analysis that scoped it.

## What they are

- **`.agent0/tools/status.sh`** — the mid-session, untruncated sibling of the SessionStart brief. It reuses the brief's composition library (`.agent0/hooks/_brief-compose.sh`) to emit handoff (Current State / Active Work / Next Actions), due reminders, pending routines, and memory decay, then adds a git working-tree block and a derived `=== next ===` suggestion block. **Read-only; always exits 0.** Surfaced as the `/status` skill (Claude) / `$status` (Codex).
- **`.agent0/tools/doctor.sh`** — a harness health check. Per-check tri-state (`ok` / `advisory` / `broken`) over core files, hook wiring (both `.claude/settings.json` and `.codex/hooks.json`), `core.hooksPath` activation, and required-vs-optional binaries, with a rollup line. **Exits non-zero iff any check is `broken`**; optional-binary absence is `advisory` and never fails the exit. Reports + proposes, never fixes (mirrors `vuln-audit`). Tool-only — no skill.

## Multi-runtime invocation

| Surface | Claude Code | Codex CLI | Human |
|---|---|---|---|
| status | `/status` | `$status` or the bash command | `! bash .agent0/tools/status.sh` |
| doctor | `bash .agent0/tools/doctor.sh` | `bash .agent0/tools/doctor.sh` | `! bash .agent0/tools/doctor.sh` |

Both tools honor `AGENT0_PROJECT_DIR` for the inspected project root (the same env contract the readout helpers use), falling back to the git root of the checkout. The composition library is located relative to the tool's own path, so the tools run correctly from any working directory and from either runtime.

## Scope discipline — what this is NOT (anti-drift)

This capacity is deliberately the **text-first kernel** of Sentinel, not the browser cockpit. Per the standing rule that speculative observability / dashboards / audit-forensics tooling is harness-drift (rule-of-three before building any of it), the following are **out of scope and must not be added without demonstrated demand**:

- No browser UI, WebSocket stream, daemon, or any long-running process.
- No host metrics (CPU/mem/disk), alert timelines, tmux/service control, or recovery snapshots — Sentinel's host-ops domains that do not transfer to a repo harness.
- No new persistent state, JSONL event log, or history store — both tools are stateless point-in-time reads; git history is the audit trail.
- No `doctor` auto-remediation, and no `--json` mode until an agent/CI consumer actually needs it.

The value is reuse and visibility, not new observability surface. If a request trends toward "a dashboard for Agent0," resist it and re-read this section.

## Relationship to the SessionStart brief

`status` does NOT replace `.agent0/hooks/startup-brief.sh` — the brief keeps its boot role (bounded, hook-emitted, truncated to 6000 bytes / 80 lines). The shared library `_brief-compose.sh` carries only composition; the brief keeps its own runtime-specific emit (Claude hook-JSON vs Codex plain-text) and truncation. Change a summarizer once in the lib and both the brief and `status` follow.
