# Memory placement

When saving a learning, fact, or rule, route it by **what kind of knowledge** it is and **who/what should see it**. Three buckets, each with distinct propagation properties:

## The 3 buckets

### 1. CC per-user memory — `~/.claude/projects/<path>/memory/`

**For:** preferences, style, personal context that wouldn't help anyone else. Per-user, per-machine, **not git-tracked**. Lost when you switch machines — by design.

**Use when:** the knowledge is genuinely about THIS user (language, response terseness, "I prefer X over Y"). Anything that reads like a profile attribute or interaction style.

**Do NOT use for:** anything substantive about the project itself. If another Agent0 contributor would benefit from knowing this fact, it does not belong here. The "memoria do projeto" naming in CC's UI is misleading: it's memory of the user *about* the project, not of the project itself.

**Typical contents:** a small handful of per-user preference notes (language, response style, "I prefer X over Y"). Each developer's bucket is independent; preferences don't sync between machines or contributors.

### 2. Project memory — `.agent0/memory/<topic>.md`

**For:** factual cross-cutting knowledge about THE PROJECT — platform constraints, prior decisions and their reasoning, architectural gotchas discovered through dogfooding, references to canonical external sources. Git-tracked, **propagates between contributors of THE SAME project via PR/clone** but **NOT shipped between projects** via sync-harness manifest. The empty scaffold (`.agent0/memory/.gitkeep`) IS shipped so every consumer project gets its own bucket — but memory content is project-local, never cross-pollinated.

**For consumer projects of Agent0:** this same rule applies. Each consumer project has its own `.agent0/memory/` that accumulates its own factual knowledge (e.g. a Python-stack consumer project might memorize "Starlette form parsing without python-multipart uses urllib.parse.parse_qs"). The upstream's memory entries (about CC platform internals, sync-harness design rationale, etc.) do NOT travel to consumer projects — and reciprocally, consumer-specific memories do NOT propagate back upstream. The sync tool is one-way for capacities; memory content is one-source.

**Use when:** the knowledge is project-specific factual reference, not behavioral mandate. "Claude Code has 29 hook events", "we chose hash-compare because alternatives X/Y had problems Z". The agent reads these on demand when starting relevant work — discovery is via the `## Memory` block in CLAUDE.md (lazy-read of `.agent0/memory/MEMORY.md` index).

**Do NOT use for:** behavioral mandates ("the agent must do X") — those are rules. Capacity operational documentation ("how a hook works") — those are rules. Work-specific design context — that lives in the corresponding `docs/specs/NNN-*/` dir.

**One narrow exception** to "no behavioral mandates here": a mandate that binds the upstream *maintainer* rather than the agent working in any consumer project. Rules ship to consumer projects, so a maintainer-only discipline placed in a rule would be inert cruft in every consumer project that consumes the harness but never extends it. Such disciplines route to project memory despite being mandate-shaped — e.g. a propagation-hygiene memory describing how shipped files must be written so they carry no upstream-internal pointers (a discipline binding the upstream maintainer, inert in any leaf consumer project).

**Typical contents:** platform-knowledge references (canonical hook surfaces, framework constraints), prior decisions and their reasoning, dogfood-surfaced gotchas. Each project accumulates its own; entries are project-local by design.

### 3. Project context rules — `.agent0/context/rules/<topic>.md`

**For:** behavioral mandates the agent SHOULD comply with, plus operational documentation of the project's capacities (hooks, validators, tools). Git-tracked AND **shipped to consumer projects** via sync-harness manifest — the rules ride with the capacities they govern.

**Use when:** the knowledge is "the agent must follow X when working in this project" or "here's how capacity Y works in any consumer project that adopts it". Path-scoped variants of these rules use a `paths:` frontmatter that the Agent0 context hydrator can use when selecting fragments.

**Do NOT use for:** factual reference data that's project-internal design context (CC platform knowledge, why-we-chose-X decisions). Those are project memory, not rules — they'd noisily ship to every consumer project that doesn't extend the harness.

**Concrete examples currently in this bucket:** `delegation.md` (5-field handoff mandate), `secrets-scan.md` (gitleaks behavior + override grammar), `harness-sync.md` (3-way reconciliation operational docs).

## Routing decision tree

```
Is the knowledge a user-specific preference (language, style)?
  Yes → CC per-user memory (~/.claude/projects/<path>/memory/)
  No  → continue

Is the knowledge a behavioral mandate, OR a capacity operational doc that the
consumer-side agent acts on (invokes the primitive, reads the override grammar,
inspects an audit log it produces)?
  Yes → .agent0/context/rules/<topic>.md (will ship to consumer projects and hydrate via hooks)
  No  → continue
        ↑ This branch ALSO catches capacity operational docs — how to extend,
          calibrate, regression-check — that ONLY the upstream maintainer ever
          acts on. The consumer-side agent never reads them, so shipping them
          via sync-harness is dead weight in every consumer project. Route them
          to memory below, NOT to rules. (Example: `hook-chain-latency.md` /
          `compaction-continuity.md` / `rule-load-debug.md` moved rule → memory
          in spec 096 for exactly this reason.)

Is the knowledge factual project reference (platform constraint, prior decision, gotcha)?
  Yes → .agent0/memory/<topic>.md (git-tracked, NOT shipped to consumer projects)
  No  → reconsider; the knowledge probably belongs elsewhere (CLAUDE.md for orientation, .agent0/HANDOFF.md for WIP, docs/specs/ for work-unit design memory)
```

When in doubt, route to project memory (`.agent0/memory/`). Demoting from rule → memory later is easy; promoting from per-user → project requires migration.

**The "consumer-side agent acts on it" test.** This is the load-bearing question for rule-vs-memory at the boundary case of capacity docs. Ask: "in a fork that consumes the harness but never extends it, does the agent ever load this doc to inform its behavior?" If yes → rule (e.g. `delegation.md`'s 5-field handoff, `secrets-scan.md`'s override grammar). If no → memory (the doc binds the maintainer extending the capacity, not the consumer-side agent using it).

## Quick reference table

| Bucket | Path | Git-tracked? | Ships to consumer projects? | Auto-loaded? | Best for |
| --- | --- | --- | --- | --- | --- |
| CC per-user memory | `~/.claude/projects/<path>/memory/` | No | No | Yes (MEMORY.md, capped) | Preferences only |
| Project memory | `.agent0/memory/<topic>.md` | **Yes** | **Empty scaffold only** (`.gitkeep`); content stays project-local | No (lazy-read via CLAUDE.md `## Memory`) | Factual project knowledge — each project accumulates its own |
| Project context rules | `.agent0/context/rules/<topic>.md` | **Yes** | **Yes** | Hydrated by `.agent0/hooks/context-inject.sh` | Behavioral mandates + capacity docs |

<!-- DO NOT RENAME — referenced verbatim by .agent0/hooks/memory-frontmatter-validate.sh advisory messages -->
## Frontmatter schema

Project-memory entries (bucket #2 — `.agent0/memory/<topic>.md`, NOT `MEMORY.md` itself, which is the index) carry a YAML frontmatter block fenced by `---`. Three fields are **required**; three are **optional** and populated by the decay engine + event-sourced journal documented below.

The `.agent0/hooks/memory-frontmatter-validate.sh` hook fires on Claude `PostToolUse(Edit|Write|MultiEdit)` and Codex `PostToolUse(apply_patch)` for any file under `.agent0/memory/*.md` (except `MEMORY.md`) and emits a non-blocking `memory-frontmatter-advisory:` line to stderr when the entry violates the schema. Always exit 0 — never blocks the edit. Pattern matches `tdd-advisory:` / `lint-advisory:` / `typecheck-advisory:` (see `.agent0/context/rules/delegation.md` § *Advisories*).

### Required fields

| Field | Shape | Purpose |
|---|---|---|
| `name` | string | Stable identifier — slug or human-readable label. Both shapes pass (existing entries use both). |
| `description` | string | One-line summary used in the MEMORY.md index. Soft cap on projected index-line length (advisory only) — see § *Cap / query / decay* below. |
| `metadata.type` | string | Classification, nested under `metadata:`. Value-open by design (consumer projects pick the taxonomy that fits their project). Examples in current use: `project`, `reference`. |

### Optional fields (under `metadata.*`)

| Field | Shape | Purpose |
|---|---|---|
| `metadata.created_at` | ISO-8601 timestamp | Entry creation time. Decay engine input (see § *Cap / query / decay*). |
| `metadata.last_accessed` | ISO-8601 timestamp | Last-read time. Decay engine input. |
| `metadata.confirmed_count` | integer | Strength signal — how many times the entry has been re-validated since creation. |

### Worked example

```markdown
---
name: payment-webhook-quirks
description: Idempotency rules + retry semantics observed in our payment-gateway incident; consult before touching webhook handlers.
metadata:
  type: reference
  created_at: 2026-05-19T17:41:00Z
  last_accessed: 2026-05-23T09:15:00Z
  confirmed_count: 4
---
# Payment webhook quirks
…body…
```

### Failure modes the validator advises on

- **Missing required field** — `name`, `description`, or `metadata.type` absent.
- **Unknown field** (typo guard) — any top-level key outside `{name, description, metadata}`, or any `metadata.*` key outside the 4 allowed values above.
- **No frontmatter block** — file does not start with `---` at line 1.
- **Frontmatter unparseable** — first `---` present but no closing `---` found.

Conforming entries pass silently. `MEMORY.md` (the index) is skipped — it carries no frontmatter by design.

## Event journal

`.agent0/memory/MEMORY.md` is a **derived view**, regenerated from the entries' `name` + `description` frontmatter. Two cooperating hooks make the system self-consistent:

- **Claude `PostToolUse(Edit|Write|MultiEdit)` / Codex `PostToolUse(apply_patch)`** → `.agent0/hooks/memory-events-journal.sh` fires on any write to `.agent0/memory/*.md` (excluding `MEMORY.md`). Appends one JSONL event to `.agent0/.memory-events.jsonl` AND invokes `bash .agent0/tools/memory-project.sh` to regenerate `MEMORY.md` from the current entries. Always exit 0 — failure modes (unwritable journal, missing `jq`, projection error) emit a `memory-journal-advisory:` line and continue. The PreToolUse gate is the only blocking part of this capacity.

- **Claude `PreToolUse(Edit|Write|MultiEdit)` / Codex `PreToolUse(apply_patch)`** → `.agent0/hooks/memory-index-gate.sh` blocks raw edits to `.agent0/memory/MEMORY.md` (exit 2 with corrective template) unless the tool input carries `# OVERRIDE: memory-index-edit: <reason ≥10 chars>` (or the equivalent `<!-- OVERRIDE: memory-index-edit: <reason> -->` HTML-comment form). Override-bypassed edits are recorded as `manual-edit` events in the journal with the reason as a field.

### Event shape

One JSONL line per memory write. Five `event_type` values:

| `event_type` | When | Fields |
| --- | --- | --- |
| `add` | First write of an `entry_id` (no prior `add` in journal) | `ts`, `entry_id`, `actor`, `runtime`, `session_id`, `tool_use_id`, `tool`, `path` |
| `update` | Subsequent write of an `entry_id` that already has an `add` | same as `add` |
| `delete` | Reserved — not auto-emitted in v1 (no file-removal hook event) | `ts`, `entry_id`, `actor` |
| `rename` | Manual append when renaming an entry (no auto-detect in v1) | `ts`, `entry_id`, `prev_entry_id`, `actor` |
| `manual-edit` | PreToolUse gate override accepted | adds `reason` field |

`entry_id = basename(filename, '.md')` — naturally stable, machine-derivable, no schema field needed. `actor = "Codex CLI"` for Codex `apply_patch` hooks; for Claude, `actor = agent_type` when present in the hook payload (sub-agent edits), else `"parent"`. `path` records the resolved project-relative entry path. `ts` in ISO-8601 UTC; the backfill uses git-introduction timestamps which may carry a timezone offset (acceptable — JSONL consumers parse both).

### Per-machine journal (gitignored)

`.agent0/.memory-events.jsonl` is **gitignored** — per-machine cache, sibling to `.agent0/delegation-audit.jsonl` and `.agent0/.runtime-state/`. A git-tracked journal would produce merge conflicts on every concurrent commit across a multi-contributor consumer project; entry files themselves are git-tracked and carry the durable record via `git log --follow`. On a new leader machine, run `bash .agent0/tools/memory-backfill.sh` once to seed the journal with one `add` event per existing entry (`ts` derived from git-introduction time). Idempotent — re-running on a populated journal is a no-op.

The first invocation of the journal hook on an empty journal emits a one-time `memory-journal-advisory: journal empty; run bash .agent0/tools/memory-backfill.sh` to mitigate the otherwise-silent add-vs-update misclassification.

### Direct `git commit` opt-out

A human running `vim .agent0/memory/MEMORY.md && git commit` bypasses the tool-surface gate. This is explicitly opt-out — the operator is responsible for re-running `bash .agent0/tools/memory-project.sh` afterward to re-converge. The `.githooks/pre-commit` projection check blocks staged drift when activated; otherwise the next agent-driven edit to any entry restores consistency.

### Cross-references

- `.agent0/hooks/memory-events-journal.sh` / `.agent0/hooks/memory-index-gate.sh` — implementations
- `.agent0/tools/memory-project.sh` / `.agent0/tools/memory-backfill.sh` — operator commands
- `.agent0/context/rules/delegation.md` § *Advisories* / *Audit log* — `memory-journal-advisory:` follows the project advisory grammar; the JSONL shape mirrors `.agent0/delegation-audit.jsonl`

## Cap / query / decay

Three scale-handling surfaces let the bucket operate at 100-500 entries without the index becoming unreadable or stale entries crowding the active set.

### 1. Index-line cap

`memory-project.sh` checks each projected `MEMORY.md` line against `cap.max_line_chars` (default 250) read from `.agent0/memory.config.json`. Overflow emits a `memory-cap-advisory: <file> projects to <N> chars (cap <M>) — shorten description` line to stderr; the bullet is still written (no auto-truncation — the cap is a writing discipline, not a silent edit). The advisory surfaces every projection until the founder shortens the entry's `description:` frontmatter.

### 2. `memory-query.sh`

Search + filter helper for entry bodies and frontmatter. Four subcommands, all routed through `.agent0/tools/memory-query-helper.py` (Python + PyYAML; mirrors the `.agent0/skills/remind/scripts/reminders-helper.py` pattern — bash dispatcher delegates to a Python helper for YAML mutation):

- **`search <pattern>`** — case-insensitive grep across all `.agent0/memory/*.md` (body + frontmatter). One line per hit: `<path>: <first matching line>`.
- **`list [--type=T] [--stale=Nd|Nw|Nm]`** — filter the index. `--type` matches `metadata.type` exactly; `--stale` accepts the same duration grammar as `/remind snooze` and lists entries whose `last_accessed` is older than `today − duration`.
- **`confirm <name1> [<name2> ...]`** — bumps `metadata.last_accessed` to today + increments `metadata.confirmed_count`. Variadic; reports the resolved file path per name. Refuses with exit 2 on unknown names. Note: the helper writes via Python syscalls, which bypasses the `PostToolUse` memory-events-journal hook — the audit trail for confirms lives in `git log` of the entry file, not in `.agent0/.memory-events.jsonl`.
- **`decay [--readout]`** — computes staleness for each entry and lists ones above the threshold. The `--readout` flag wraps output in a `=== MEMORY DECAY ===` framed block for SessionStart injection.

### 3. Decay engine

Formula (default, transparent + overridable):

```
score = (today − last_accessed_or_created_at).days − confirmed_count × confirm_boost_days
```

Entries with `score > threshold_days` are listed as stale. Defaults: `threshold_days = 60`, `confirm_boost_days = 14` (each confirm discounts ~2 weeks from the staleness clock). The `.agent0/hooks/memory-decay-readout.sh` SessionStart hook fires `memory-query.sh decay --readout` every session — always-fire with `(no stale entries)` empty-case keeps the capacity discoverable.

The engine never auto-archives, auto-deletes, or otherwise mutates entry files. Decay is observation, not removal — the founder (or agent) decides whether to `confirm`, manually edit, or move the entry. Auto-archive is rejected by design: staleness is a re-validation cadence question (some useful entries need re-confirming twice a year), not a wrongness signal.

### Config — `.agent0/memory.config.json`

```json
{
  "cap": { "max_line_chars": 250 },
  "decay": { "threshold_days": 60, "confirm_boost_days": 14 }
}
```

Shipped as a starter template. Consumer projects override values directly. Missing keys fall back to documented defaults. Malformed JSON emits a one-line `memory-config-advisory:` and the defaults run; never blocks. Out-of-spec keys are ignored silently.

### Gotchas

- **`confirm` writes via Python, NOT via the Edit/Write tool surface.** The `PostToolUse` memory-events-journal hook (which captures `Edit`/`Write`/`MultiEdit` invocations) does NOT fire on confirms. The audit trail for confirms lives in `git log <entry-file>`. If you need journal events on confirms in your consumer project, extend the Python helper to append a JSONL line directly.
- **`last_accessed` is honest only after the founder uses `confirm`.** Backfilled values for legacy entries (those predating the metadata extension) default to "today at backfill time" (no honest read signal pre-extension). Decay won't surface anyone for ~60 days after backfill unless the founder confirms (and thus moves the timestamp) some entries first.
- **Cap counts the projected bullet length, not the raw description.** The check is on `- [<name>](<slug>.md) — <description>` after assembly. Tightening `name` (rare) is one lever; the usual fix is shortening `description`.
- **Folded YAML strings in the entries can confuse non-Python tooling.** PyYAML's `safe_dump` folds long values across lines for readability. The Python helper handles this; the degraded awk projection path in `memory-project.sh` (used when python3+yaml absent) emits a `memory-project-advisory:` warning and may truncate folded descriptions at the first line. Consumer projects without PyYAML get a degraded but still-functional projection.

### Files

- `.agent0/memory.config.json` — config (cap + decay numerics)
- `.agent0/tools/memory-query.sh` — bash dispatcher (4 subcommands)
- `.agent0/tools/memory-query-helper.py` — Python helper (YAML mutation + filtering + projection)
- `.agent0/tools/memory-backfill-metadata.sh` — one-shot helper to populate `created_at` / `last_accessed` / `confirmed_count` for legacy entries
- `.agent0/tools/memory-project.sh` — extended with cap-advisory check
- `.agent0/hooks/memory-decay-readout.sh` — SessionStart hook

## Multi-runtime usage

**Operational triggers.** Read `.agent0/memory/MEMORY.md` before work that touches project architecture, first-party capacities, `.agent0/context/rules/`, `.claude/hooks/`, `.claude/skills/`, `.agent0/tools/sync-harness.sh`, `.agent0/context/rules/runtime-capabilities.md`, or `.agent0/memory/`. Follow only relevant entries; ordinary reads do not mutate memory.

**Activation.** Claude Code uses `.claude/settings.json`, which points the four memory hook registrations at `.agent0/hooks/memory-*.sh`. Codex CLI uses tracked `.codex/hooks.json`, which registers the `SessionStart`, `PreToolUse(apply_patch)`, and `PostToolUse(apply_patch)` memory hooks after the project and changed hooks are trusted.

**Coverage boundary.** Codex v1 parity covers the `apply_patch` edit surface. Arbitrary Codex `Bash` writes can still touch `.agent0/memory/*.md` without reliable path attribution, so they are out of strict hook parity and are caught only by the pre-commit projection backstop or a later projection run. Hook-disabled sessions must run `bash .agent0/tools/memory-maintain.sh finalize <entry-path>` before session end after memory edits; stale readout without hooks is `bash .agent0/tools/memory-query.sh decay --readout`.

**Runtime divergence.** Claude Code has `PostToolUseFailure`; Codex CLI does not expose an equivalent failure event for this capacity. Memory validation and journaling run after successful edit tools only. This does not block v1 because the projector reads committed working-tree files and fails open with advisories.

**Double-fire framing.** If Claude and Codex are used sequentially on the same memory entry, both runtimes may emit journal events. That is expected, not duplication: events are keyed by `runtime`/`actor`, `session_id`, `tool_use_id`, `tool`, and `path`, and the entry file's git history remains the durable cross-machine record.

**Pre-commit backstop.** Activate native git hooks per project with `git config core.hooksPath .githooks`. The memory check is non-mutating: it projects `MEMORY.md` from the staged index into a temp file, diffs it against staged `.agent0/memory/MEMORY.md`, and blocks with a corrective message if drift exists. It never rewrites files or auto-stages.

**Entrypoint budget.** `AGENTS.md` and `CLAUDE.md` keep the `## Memory` block index-shaped and within 12 non-blank lines. Detailed protocol belongs here; `.agent0/tests/agents-memory-block-budget.sh` enforces the budget.

## Cross-cutting artifacts (not buckets, but related)

- **`CLAUDE.md`** — first-contact orientation, capacity inventory, always loaded. Points at memory/rules/specs as needed.
- **`.agent0/HANDOFF.md`** — short-term WIP handoff, 4 KB target, replaced rather than appended. Injected automatically for Claude Code; read by convention for Codex.
- **`docs/specs/NNN-*/`** — design memory for specific work units. Not auto-loaded; referenced when relevant.

## Why three buckets, not two

The previous version of this rule had only two buckets: project-shared (rules) and per-user (preferences). That model conflates two distinct kinds of project-shared knowledge: behavioral mandates that should ride with capacities into consumer projects, and factual reference that's project-internal design context. Three empirical triggers established the current shape:

1. **CC-32-hooks discovery.** Claude Code has 32 hook events (not the ~9 commonly cited). That knowledge is project-shared (other Agent0 contributors benefit), NOT a behavioral mandate (it's reference data), and SHOULD NOT ship to consumer projects (consumer projects consume capacities, they don't extend the harness). No existing bucket fit.
2. **The 2026-05-27 maintainer-rules-to-memory audit (spec 096).** Three rules (`hook-chain-latency.md`, `compaction-continuity.md`, `rule-load-debug.md`) documented capacity internals that only the upstream maintainer ever acts on — budgets to defend when adding a new hook, the PreCompact/SessionStart mechanism to preserve when editing the snapshot pair, opt-in observability for diagnosing path-scoped loads. They were drifting into consumer-project context noise. Moving them to memory removed that drift AND surfaced the criterion the routing tree above now names explicitly. **This is the canonical case for the `move-full` disposition** — entire rule routes to memory because zero consumer-binding content exists.
3. **The 2026-05-27 borderline-rules-disposition audit (spec 097).** Three rules (`runtime-capabilities.md`, `propagation-advisory.md`, `runtime-introspect.md`) mixed consumer-binding sections (status vocabulary the agent consults, override grammar the agent invokes, probe output shape the agent pattern-matches, env-var contracts the agent honours) with maintainer-binding sections (update rule + drift-check anchors, regex pattern table + shipped-surface set + audit-log policy, env-var extension contract + per-detector inference heuristics + dogfood archaeology). **This is the canonical case for the `split` disposition** — the rule retains its consumer-facing slice at `.agent0/context/rules/<slug>.md`, and a new `.agent0/memory/<slug>-maintenance.md` carries the maintainer-binding companion. The cross-link is one `## Maintenance` section in the rule pointing at the memory entry. Precedent file pair: `.agent0/context/rules/propagation-advisory.md` ↔ `.agent0/memory/propagation-advisory-maintenance.md`.

**The split-vs-move-full criterion for the next borderline audit.** When a rule mixes consumer-binding sections (override grammar, env vars, behavior the agent invokes) with maintainer-binding sections (extension contracts, internal mechanism, drift tooling), the right disposition is **split** into a thin consumer-facing rule + a `<slug>-maintenance.md` memory companion. Move-full only when ZERO consumer-binding content exists. Keep-as-is only when a re-audit shows the MB sections are themselves consumer-relevant (rare — the canonical sign is that the consumer-side agent actively loads the section to inform its own behavior, not the maintainer extending the capacity).

The `.agent0/memory/` bucket covers all three trigger classes — pure-reference (CC-32-hooks), full-rule reclassification (spec 096), and split companions (spec 097).
