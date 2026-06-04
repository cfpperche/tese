# tese

Personal **decision-support + tax-compliance ledger** for investing abroad from Brazil. Reconciles
the thesis watched with the portfolio held, and from the first remittance captures every field the
Brazilian filings (IRPF / Lei 14.754, Bacen CBE) and US estate rules will later demand. Behavior
rules for any agent working on this repo live in `./.agent0/context/rules/`.

## Overview

Single-user, local-first tool. Two planes behind adapters: **market-data (A)** for the thesis
universe (incl. unheld names) and **portfolio (B)** for real holdings (manual file first, IBKR Web
API later). An append-only **ledger** records every economic event in a Brazil-tax-shaped schema;
the North Star is **filing-readiness** — a one-command contador-ready export at any moment.

**Posture (load-bearing):** decision-support, **never advice** — no signals, scores, or
recommendations. **Read-only forever** — no trade execution, even from IBKR. The tool organizes the
record; **a contador computes and files** the official tax numbers. Full vision in `docs/`
(concept-brief, prd, compliance-tax, system-design, roadmap, brand-book, design-system).

## Stack

Python 3.12+ · FastAPI + Uvicorn · SQLite (single-file, local) · APScheduler (market-hours-aware
polling) · vanilla-JS + Chart.js frontend (served static, no build step) · ruff + pytest (TDD).
Config: `.env` (API keys) + `holdings.yaml` + `watchlist.yaml` (both gitignored / example-only).

## Build & test

```bash
# build:  (none yet — Phase 1 skeleton not built; see docs/specs/001-foundation)
# test:   pytest          # once the skeleton lands
# lint:   ruff check .
# run:    uvicorn app.main:app --reload   # planned entrypoint
```

## Conventions

- **Spec-first** (`/sdd`): non-trivial work starts under `docs/specs/NNN-<slug>/`. Foundation child
  is `docs/specs/001-foundation/`.
- **Adapter discipline:** `MarketDataSource` (yfinance→Finnhub) and `PortfolioSource`
  (manual→IBKR) are abstract from day 1 — both future swaps are config flips, not rewrites.
- **Ledger is event-sourced + append-only;** positions/balances are derived or 31/12-snapshotted —
  Brazilian filing needs point-in-time historical truth (the FX rate of the day), not just state.
- Repo artifacts in **English**; chat with the owner in **pt-BR**.

## Gotchas

- **`B (IBKR) never blocks A`.** Phase 1 is fully useful with manual holdings; the live IBKR feed is
  a later upgrade, not a prerequisite (IBKR account + OAuth/CP-Gateway auth take time to stand up).
- **Tax numbers are "confirm with contador"** — the 2025 IOF reform moved rates; `compliance-tax.md`
  § E lists the open items. The tool never hardcodes liability math.
- **No personal financial data in git:** `holdings.yaml`, `.env`, `*.sqlite` are gitignored. The
  repo is **public** (Apache-2.0); docs describe strategy/architecture, never positions.

<!-- AGENT0:BEGIN -->

## Spec-driven development

Non-trivial work is spec-first — intent before code under `docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md`, scaffolded and progressed by the `/sdd` skill. See `.agent0/context/rules/spec-driven.md`.

## Runtime entrypoints

`CLAUDE.md` is the Claude Code entrypoint; `AGENTS.md` is the Codex entrypoint. This managed block is the shared Agent0 index; runtime support details live in `.agent0/context/rules/runtime-capabilities.md`. `AGENTS.md` is baseline-tracked; Codex consumer project customization belongs in `AGENTS.override.md` or nested `AGENTS.md`.

## Runtime capabilities

`.agent0/context/rules/runtime-capabilities.md` is the canonical provider-neutral matrix for Agent0 capability support across Claude Code, Codex CLI, and future runtimes. Consult it before assuming a `.claude/*` capability is native in a runtime. **Never assert that a built-in command (e.g. a slash command like `/goal`) does not exist just because it is absent from your skills list — the injected inventory is not exhaustive; hedge and verify instead (see the rule's § Before claiming a capability or command does NOT exist).**

## Session handoff

`.agent0/HANDOFF.md` is the canonical runtime-neutral handoff with four sections: Current State, Active Work, Next Actions, Decisions & Gotchas. Claude Code injects/nags through hooks; Codex receives the same handoff through tracked `.codex/hooks.json`, with `AGENTS.md` as the convention fallback. See `.agent0/context/rules/session-handoff.md`.

## Delegation

`Agent` dispatches are gated: `.agent0/hooks/delegation-gate.sh` enforces a 5-field handoff (TASK / CONTEXT / CONSTRAINTS / DELIVERABLE-or-DONE_WHEN), and `.agent0/hooks/delegation-verify.sh` verifies sub-agent work at close (`SubagentStop`, runtime-neutral). See `.agent0/context/rules/delegation.md`.

## User prompt framing

On a non-trivial prompt the main agent runs a 3-question mental check (TASK / CONTEXT / DONE clear?) and clarifies via `AskUserQuestion` before acting when ≥2 are unclear. Rule-only — no hook. See `.agent0/context/rules/user-prompt-framing.md`.

## Test-driven development

Production code follows red → green → refactor with tests in the same diff; the validator emits a non-blocking `tdd-advisory:` when prod files move without a test. Cultural discipline, not a blocking gate. See `.agent0/context/rules/tdd.md`.

## Secrets scan

Two layers — the native `.githooks/pre-commit` runs gitleaks over the staged diff at commit time; a runtime-neutral `PreToolUse(Bash)` preflight (`.agent0/hooks/secrets-preflight.sh`) gates dangerous commit shapes on Claude Code and Codex CLI. Activate per-consumer with `git config core.hooksPath .githooks`. See `.agent0/context/rules/secrets-scan.md`.

## Vuln audit

`.agent0/tools/vuln-audit.sh` (engine osv-scanner) detects known-vulnerable INSTALLED dependencies on demand, stack-aware, runtime-neutral. Codex invokes the tool directly: `bash .agent0/tools/vuln-audit.sh [path] [--json] [--exit-code] [--severity <level>]`. Don't gate install/commit — detect vulnerable locked libs and act; reports + proposes, never auto-fixes. See `.agent0/context/rules/vuln-audit.md`.

## MCP recipes

MCP server blocks for common external MCPs (Playwright, Chrome DevTools, DBHub, Laravel Boost, Next.js DevTools, fal.ai) ship as copy-paste templates only: `.mcp.json.example` for Claude Code, `.codex/config.toml.example` for Codex CLI. Each block is `enabled = false` / commented by default and uses env-var indirection for any secret (`bearer_token_env_var`, `env_vars`). Consult the upstream README of each MCP for activation specifics, runtime requirements, and security stance — Agent0 ships the templates, not curated reference docs.

## Image generation

Opt-in capacity for AI image generation via fal.ai MCP — the `/image` skill produces draft mockups (FLUX schnell, ~$0.003/img, gitignored) and brand assets (gpt-image-2 or Imagen 4 Ultra, $0.04-$0.20/img, tracked) with mandatory `--tier` flag, pre-call cost printing, and a JSONL manifest of every call. Activation is a `.mcp.json` edit + `FAL_KEY` env. See `.agent0/context/rules/image-gen.md`.

## Video generation

Opt-in capacity for video, sibling to `/image`. The `/video` skill has two disjoint modes behind a required `--mode` flag: `code` (deterministic — HyperFrames renders an HTML/CSS/JS composition to MP4 locally, zero inference cost, source git-tracked) and `generative` (paid, async — fal.ai video models via the queue REST API, fire-and-forget ledger, hard `--confirm-cost-usd` gate). Activation is per-mode: code needs Node 22+/ffmpeg/headless-Chrome; generative needs `FAL_KEY`. Ships mechanisms, not model IDs — generative tiers resolve from a refreshable `video-tiers.yaml`. See `.agent0/context/rules/video-gen.md`.

## Harness sync

`.agent0/tools/sync-harness.sh` brings a consumer project's harness up to date with Agent0 via 3-way baseline reconciliation against `.agent0/harness-sync-baseline.json` — stale files auto-update, consumer-customized files refuse without `--force`, never touches product code. See `.agent0/context/rules/harness-sync.md`.

## Lint validator

The post-edit validator runs the consumer project's idiomatic linter — Biome (JS/TS), Ruff (Python), Pint + PHPStan/Larastan (PHP) — when the manifest declares it; missing-but-declared emits a non-blocking `lint-advisory:`. See `.agent0/context/rules/lint-validator.md`.

## Typecheck advisory

The validator runs a typecheck step only when the consumer project declares the primitive (a `tsconfig.json`, or a `typecheck` script in `package.json`); otherwise it emits `typecheck-advisory:` and skips. See `.agent0/context/rules/typecheck-advisory.md`.

## Memory

Factual project knowledge lives in `.agent0/memory/<topic>.md`; the trigger-read index is `.agent0/memory/MEMORY.md`. Content is git-tracked for this project, but not shipped to consumers.
Read the index when work touches project architecture, first-party capacities, `.agent0/context/rules/`, `.agent0/hooks/`, `.claude/skills/`, `.agent0/tools/sync-harness.sh`, `.agent0/context/rules/runtime-capabilities.md`, or `.agent0/memory/`.
Follow only relevant entries; ordinary reads do not mutate memory.
Claude uses `.claude/settings.json` hooks. Codex uses tracked `.codex/hooks.json` hooks after the project and changed hook definitions are trusted.
Do not raw-edit `.agent0/memory/MEMORY.md`; edit entries and let projection regenerate it.
Hook-disabled memory edits must end with `bash .agent0/tools/memory-maintain.sh finalize <entry-path>`.
Without hooks, stale-memory readout is `bash .agent0/tools/memory-query.sh decay --readout`.
See `.agent0/context/rules/memory-placement.md` § Multi-runtime usage.

## Context retrieval

`.agent0/tools/context-retrieve.sh search --query "<text>"` performs deterministic local retrieval across Agent0 context rules, project memory projection/metadata, specs, and handoff. `context-inject.sh` uses it as a bounded retrieval lane after deterministic rule selection: existing rule matches form a must-include floor, retrieval fills only remaining prompt budget, and snippets are pointers rather than source of truth. No embeddings/vector DB in v1. See `.agent0/context/rules/context-retrieval.md`.

## Status & doctor

Two on-demand, text-first shell tools over live harness state (the transferable kernel of `opus-domini/sentinel`, ported to a repo harness). `status` (`/status`, or `bash .agent0/tools/status.sh`) is the untruncated mid-session sibling of the SessionStart brief — handoff, reminders, routines, decay, git state, suggested next commands; read-only, always exit 0. `doctor` (`bash .agent0/tools/doctor.sh`) reports harness health (files/hooks/binaries/`core.hooksPath`) with a tri-state per check, exit non-zero only on `broken`; reports, never fixes. Both reuse `.agent0/hooks/_brief-compose.sh`. NOT a browser/daemon/metrics surface — the anti-drift scope is load-bearing. See `.agent0/context/rules/agent0-status.md`.

## Browser auth

On an auth-gated URL with no saved state the agent emits `BROWSER_AUTH_REQUIRED: <host>`; the human logs in via a headed Playwright MCP session and the state (`.agent0/.browser-state/<host>.json`) is reused for headless reads. See `.agent0/context/rules/browser-auth.md`.

## Skill compliance

Every first-party `.claude/skills/*/SKILL.md` must pass the agentskills.io frontmatter spec; the `/skill` meta-skill scaffolds, audits, ports, and validates them, with three declared portability tiers. See `.claude/skills/skill/`.

## Product skill

`/product` is the foundation generator + design partner for the product lifecycle (idea → v1 → vN) — a multi-step industry-aligned pipeline producing the planning artifacts + a visual contract that hands off to SDD. See `.claude/skills/product/`.

## Meeting

`/meeting` convenes a multi-party, multi-model deliberation — a human (intermittent), Claude Code, and Codex CLI take turns on a free topic or vague idea. Human-orchestrated v1 (one turn at a time, no autonomous looping); peer turns run through the `codex-exec`/`claude-exec` bridges; turn legality lives in a machine-readable header managed by `scripts/meeting.sh`. The collaborative sibling of `/brainstorm` (solo divergence) and `/sdd debate` (two-role spec review). Git-tracked, project-local transcripts under `.agent0/meetings/` (not propagated to consumers). See `.agent0/context/rules/meeting.md`.

## Routines

`.agent0/routines/<slug>.md` git-tracks recurring project work; an opt-in leader machine's cron enqueues each run for the next interactive session to dispatch via `/routine run <slug>`. See `.agent0/context/rules/routines.md`.

## Artifact size cap

Artifact size is not a scope/quality signal — scope and quality are judged by the `/product` quality judge. The only size mechanism is a uniform 200 KB catastrophe cap (a dumb token-runaway circuit-breaker) plus the retained per-step `min_size` anti-stub floors; trim-loop and re-emit-at-smaller-scope stay forbidden. See `.agent0/context/rules/artifact-budgets.md`.

## Compact Instructions

When summarizing this conversation for context compaction, prioritize keeping:

- The user's most recent intent and the *why* behind in-flight work (not just the *what*)
- Decisions made and rejected alternatives, with reasoning
- Open questions, blockers, and known gotchas hit during the session
- File paths and identifiers that anchor the work (so subsequent searches stay grounded)

Safe to compress:

- Verbatim tool output (file contents, command output) — re-read on demand
- Resolved sub-tasks where the outcome is already in `git log` or the code
- Exploratory tangents that didn't influence the final direction
<!-- AGENT0:END -->
