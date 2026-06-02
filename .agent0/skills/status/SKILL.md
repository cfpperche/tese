---
name: status
description: On-demand, text-first cockpit over the live Agent0 harness state — session handoff, due reminders, pending routines, memory decay, git working-tree state, and suggested next commands, in one untruncated readout. Use when the user asks "where does my work stand?", "what's the status?", "what should I do next?", "show me the handoff", or mid-session wants the full picture the SessionStart brief only shows at boot (and bounded). Wraps the runtime-neutral .agent0/tools/status.sh. Read-only; never mutates state. For harness wiring/health ("is the harness set up right?") use .agent0/tools/doctor.sh instead. See .agent0/context/rules/agent0-status.md.
argument-hint: ""
license: MIT
compatibility: Designed for Claude Code. Core logic is the runtime-neutral bash tool `.agent0/tools/status.sh` (reuses the startup-brief composition library); the skill is a thin invocation wrapper, portable to any runtime that can run the tool. Codex CLI invokes the tool directly via `$status` or the bash command.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.1"
---

# /status — on-demand harness cockpit

Thin wrapper over `.agent0/tools/status.sh`. The tool is the engine; this skill decides when to run it and relays the result. See `.agent0/context/rules/agent0-status.md` for the full capacity contract (what status vs doctor cover, the anti-drift scope, multi-runtime invocation).

## When to run

Run on demand whenever the user wants the current state of their work mid-session: handoff summary, what's queued, what changed in the tree, what to do next. This is the fuller, untruncated sibling of the SessionStart brief (`.agent0/hooks/startup-brief.sh`) — same composition, no 6000-byte / 80-line cap, plus a git-dirty block and a derived "next commands" block.

It is **read-only** — it never edits handoff, reminders, routines, or any file. Safe to run any number of times.

## What to do

1. **Invoke the tool** (it takes no arguments):
   ```bash
   bash .agent0/tools/status.sh
   ```

2. **Relay the result** — the output is structured between `AGENT0_STATUS` and `END_AGENT0_STATUS` with sections: `=== handoff ===`, `=== git ===`, `=== reminders ===`, `=== ROUTINES ===`, `=== next ===`. Surface it faithfully; don't re-summarize away the detail the user asked for. The `=== next ===` block is a derived suggestion, not a mandate — present it as options.

3. **Don't conflate with doctor** — if the user is actually asking whether the harness is wired correctly (hooks registered, binaries present, `core.hooksPath` active), run `.agent0/tools/doctor.sh` instead; `status` reports work state, `doctor` reports harness health.

## Notes

- Pure-shell and runtime-neutral. Claude invokes `/status`; Codex invokes `$status` (discovery symlink `.agents/skills/status`) or the bash command directly; a human can run `! bash .agent0/tools/status.sh`.
- No `agents/openai.yaml` — the skill is read-only and safe to auto-fire, mirroring `vuln-audit`.
- On symlink-hostile checkouts, `sync-harness` materializes the canonical body as a copy (spec 121 fallback).
