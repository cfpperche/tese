---
name: sdd
description: Spec-driven development scaffolding. Use when starting non-trivial work (3+ files, new module, API/schema change, vague request needing decomposition). Creates and progresses docs/specs/NNN-slug/{spec,plan,tasks,notes,debate}.md per the spec-driven workflow. Subcommands - new <slug>, refine, debate, plan, tasks, list. See .agent0/context/rules/spec-driven.md for when SDD applies and when to skip.
argument-hint: <new <slug> | refine [<idea> | NNN] | debate | plan | tasks | list>
license: MIT
compatibility: Designed for Claude Code. Body references `.claude/` conventional paths and CC-specific tools; portable to any runtime that maps a `.claude/`-analog directory and surfaces the referenced tools.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.2"
---

# /sdd — spec-driven development

Scaffolds and progresses spec folders for non-trivial work. Each feature gets `docs/specs/NNN-<slug>/` with four files: `spec.md` (what + why), `plan.md` (how), `tasks.md` (do), `notes.md` (in-flight design memory populated during implementation).

See `.agent0/context/rules/spec-driven.md` for the workflow rationale and when to apply / skip SDD.

## Argument parsing

User invokes as `/sdd <subcommand> [args]`. The raw argument string is `$ARGUMENTS`. Parse it yourself: split on whitespace, first token is the subcommand (`new` / `refine` / `debate` / `plan` / `tasks` / `list`), the rest are subcommand args. Do not rely on `$1` / `$2` — harness substitution for those is inconsistent across invocation paths (slash vs Skill tool); always parse `$ARGUMENTS` instead.

Raw invocation: `$ARGUMENTS`

## Subcommand: `new <slug>` — 🔒 Low freedom: scaffold + substitute sequence

Scaffold a new spec dir. Parse `$ARGUMENTS`: first token must be `new`, second token is the slug (kebab-case, e.g. `auth-rewrite`).

1. **Validate** — refuse with a clear message if:
   - slug is empty
   - slug doesn't match `^[a-z][a-z0-9-]*$` (kebab-case starting with a letter)
   - `docs/specs/NNN-<slug>/` with that slug already exists (suggest a different slug or `/sdd list`)

2. **Find next NNN** — scan `docs/specs/` for existing `NNN-*` dirs (ignore hidden files like `.gitkeep`), take the highest NNN, increment. Start at `001` if none exist. Zero-pad to 3 digits.

3. **Create the dir and copy templates** — use the templates in `.agent0/skills/sdd/templates/`:
   ```
   mkdir -p docs/specs/NNN-<slug>
   cp .agent0/skills/sdd/templates/spec.md.tmpl  docs/specs/NNN-<slug>/spec.md
   cp .agent0/skills/sdd/templates/plan.md.tmpl  docs/specs/NNN-<slug>/plan.md
   cp .agent0/skills/sdd/templates/tasks.md.tmpl docs/specs/NNN-<slug>/tasks.md
   cp .agent0/skills/sdd/templates/notes.md.tmpl docs/specs/NNN-<slug>/notes.md
   ```

4. **Substitute placeholders** in each created file — replace literally:
   - `{{SLUG}}` → `<slug>`
   - `{{NNN}}` → the zero-padded number
   - `{{DATE}}` → current date in `YYYY-MM-DD` (UTC)

5. **Report** — output the four paths and tell the user the next step is to fill `spec.md`. Do NOT auto-fill it; the user owns intent. Suggest they describe the change conversationally and you can draft `spec.md` from that, but only after they say so. If the idea is still vague, suggest `/sdd refine` instead. The fourth file `notes.md` stays empty at scaffold time — its purpose is in-flight design memory populated **during** implementation (see `.agent0/context/rules/spec-driven.md` § The four artifacts).

## Subcommand: `refine` — 🔓 Medium freedom: adaptive interview with structured close

Discovery interview that turns a vague idea into a filled `spec.md`. Opt-in front-end to `new` — conducts a senior-engineer interview, then writes the synthesis into the `spec.md` template. **Invocable at any point** — before a spec dir exists, or to refine one that does.

**Entry shapes** (parse `$ARGUMENTS` after the `refine` token):

- `refine "<idea>"` — a quoted idea or free text → interview from scratch; a spec dir is scaffolded only if the user opts in at Step 3.
- `refine NNN` — a spec number → refine that existing spec in place.
- `refine` (no args) — target the latest `docs/specs/NNN-*/` dir, same rule as `plan` / `tasks`.

**Resumability** — if the target spec dir exists, read its `spec.md` first; you are refining, not starting fresh. If `plan.md` or `tasks.md` are already filled (no `{{` placeholders), warn — "refining intent after planning has started; re-run `/sdd plan` afterward to resync" — but do not block.

### Step 0: Context load — 🔒 Low freedom: always silent

Read project context BEFORE speaking; build an internal model, do NOT dump a summary. Read: `CLAUDE.md`, `.agent0/context/rules/*.md`, `.agent0/memory/MEMORY.md` (the lazy index — pull specific memory files only when a round needs them), the `docs/specs/` directory listing (titles, not full bodies), recent `git log`. Reference this naturally during the interview.

### Step 1: Opening — 🔓 Medium freedom: brief, grounded

In 2-3 sentences: what context you loaded, which existing specs / rules / modules overlap with the idea, and that you are ready to start. If no idea was supplied, ask what to explore.

### Step 2: Discovery — 🔓 Medium freedom: adaptive questioning

**Read `.agent0/skills/sdd/references/question-bank.md` before this step.**

Each round: (1) state your current understanding in 1-2 sentences; (2) ask 1-2 non-obvious questions from the bank; (3) reference actual repo context; (4) state a recommended default per question — the user confirms, corrects, or overrides, never starts from blank. If you have no opinion, say so explicitly rather than fabricating one.

Rules:

- Minimum 3 rounds, even if the idea seems clear. Maximum 6 by default — if not converging, force synthesis.
- **Deep mode** — if the user passes `--deep` or asks to "go deep", lift the 6-round cap; continue until 3 consecutive rounds surface no new in-scope decisions. Hard ceiling 20.
- **Grep before asking** — if the repo could answer a question (configs, rules, memory, specs, schemas), read first; asking is the fallback. Per `.agent0/context/rules/research-before-proposing.md`, web research is allowed here: repo first, web second, ask last. Name the file / source you read.
- Challenge the idea at least twice (scope creep, over-engineering, vague value). Never sycophantic — "great idea" is banned.
- Cover at least 4 of the 7 question-bank categories.
- Detect convergence (answers stop adding information → synthesis) and kill signals (feature not worth building → say so directly).

Checkpoint after each round: `Round N/6 — scope converging on [summary]. Continue, or move to synthesis?`

### Step 3: Synthesis — 🔒 Low freedom: structured summary

Present for confirmation: feature name; problem (who, what pain, frequency); proposed solution (1-2 sentences); scope v1 (in / out / anti-goals); architecture fit (which existing specs / rules / modules it touches); key tradeoff; effort estimate (S/M/L/XL); top 2-3 risks.

Ask the user to confirm, adjust, or kill — and to choose the output:

1. **Write `spec.md`** — scaffold a spec dir (or refine the existing one) and fill the template. Recommended.
2. **Just the summary** — return the synthesis inline; write no file.

For option 1 on a from-scratch refine: propose a kebab-case slug derived from the feature name; the user confirms or overrides. Then scaffold exactly as `new` does (next NNN, copy templates, substitute placeholders).

### Step 4: Output — 🔒 Low freedom: use the existing template

**Read `.agent0/skills/sdd/templates/spec.md.tmpl` before producing.** Fill all five sections — Intent, Acceptance criteria, Non-goals, Open questions, Context / references. Every claim must trace to a discovery-round answer; invent nothing the user did not confirm. Acceptance criteria use the `Scenario: … Given/When/Then` sub-bullet shape for behavior and plain checkbox bullets for static facts (per `.agent0/context/rules/spec-driven.md` § Acceptance scenarios) — Gherkin surfaced during discovery maps directly onto that shape.

### Step 5: Close — 🟢 High freedom: handoff

**Read `.agent0/skills/sdd/references/checklist.md` and self-review against it.** Then self-assess a quality score:

| Category                  | Weight | Measures                                          |
|:--------------------------|-------:|:--------------------------------------------------|
| Problem clarity           |    20% | Who, what pain, frequency, cost of inaction       |
| Scope precision           |    20% | In-scope vs out-of-scope is unambiguous           |
| Architecture fit          |    20% | References actual specs, rules, modules           |
| Acceptance completeness   |    15% | Scenarios cover happy path, edges, errors         |
| Implementation readiness  |    15% | `/sdd plan` can start from this spec alone        |
| Grounding                 |    10% | Every claim traces to a discovery answer          |

Report the score and point the user at the next step: `/sdd plan`.

## Subcommand: `debate` — 🔓 Medium freedom: scaffold + write the local agent's next slot

Cross-model review of `spec.md` between two tool-calling CLI agents in separate sessions, each running its own port of this skill. **The agent that invokes `/sdd debate` first becomes the `initiating agent`; the other runtime, when invoked against the same file, becomes the `reviewing agent`.** Both read and write `debate.md` directly via native file tools; the human alternates which runtime is active and decides when the debate ends. Goal: productive disagreement before `plan.md` is locked — catching spec ambiguities, hidden assumptions, and weak acceptance criteria that a single model misses. Opt-in step between `refine`/`new` and `plan`. Zero infra in this session: no API key, no MCP, no broker script — both agents have native file read/write. The artifact `debate.md` IS the audit trail (git-tracked alongside the spec).

**This port's runtime identity:** the name of the runtime you are actually executing in — `Claude Code`, `Codex CLI`, `Cursor`, `Aider`, etc. **Determine it from your own execution context; do NOT read it as a fixed literal from this skill file.** Skills are symlink-shared across runtimes (see `.agent0/context/rules/runtime-capabilities.md`), so this file is byte-identical for every port — any hardcoded name here would be wrong for all but one runtime. The skill writes *your* identity into `**Initiating agent:**` at scaffold time, and on re-invocation compares the `**Initiating agent:**` value against your own identity to determine your role: **names you → you are the initiating agent; names a different runtime → you are the reviewing agent.** The runtime labels used as examples throughout this section (`Claude Code`, `Codex CLI`, …) are illustrative, not behavioural rules.

**Entry shape:** `/sdd debate` — no positional argument. Same target-selection rule as `plan` / `tasks`: latest `docs/specs/NNN-*/` dir unless the user has named a specific one in conversation. **Re-invocable on an in-flight debate** — each invocation determines this runtime's role (initiating vs reviewing) from file metadata and writes the next empty slot belonging to that role.

### Step 1: Locate target — 🔒 Low freedom

1. Find the latest `docs/specs/NNN-*/` dir. If multiple are in flight and ambiguous, ask which one.
2. Read `spec.md`. **Refuse** with a clear message if:
   - `spec.md` still has `{{` template placeholders → "fill spec.md first; debate operates on a real spec"
   - no spec dir exists at all → "no spec dir in flight; run `/sdd new <slug>` first"

### Step 2: Detect debate state + determine role — 🔒 Low freedom

If `debate.md` does NOT exist → this runtime is the **initiating agent**; proceed to Step 3 (Scaffold). Otherwise:

1. Inspect the file's `**Resolution:**` line under `## Synthesis`:
   - **In-flight** — `Resolution:` value is the literal placeholder `{{converged | cap-reached | abandoned}}` (template scaffolds it this way; only overwritten when the user asks for synthesis). **Do NOT refuse** — this is the normal re-invocation pattern. Continue to step 2.
   - **Complete** — `Resolution:` value is one of `converged` / `cap-reached` / `abandoned` (set when synthesis was written). Warn but allow — the user is explicitly starting a second debate; rename the existing file to the next free `debate-N.md` (1, 2, 3, …) and treat as scaffold (this runtime becomes the initiator of the new debate). Continue to Step 3.

2. Read the `**Initiating agent:**` line at the top of `debate.md`:
   - Value equals **your own runtime identity** (the runtime you are executing in — see "This port's runtime identity" above) → this runtime is the **initiating agent**. Jump to Step 6 (write the next empty initiating-agent slot — counter or, if user-requested, synthesis).
   - Value is anything else (names a different runtime) → this runtime is the **reviewing agent**. Jump to Step 6 (write the next empty reviewing-agent critique slot).
   - **Line is absent (legacy file pre-dating runtime-neutral metadata)** → do NOT default to "local runtime is initiator"; that lets two ports both think they own the debate. Instead, infer from legacy round headers:
     - Grep the file for `## Round 1 — Claude (position)` → infer Initiating agent = `Claude Code`. Emit advisory `debate-advisory: <path> has no '**Initiating agent:**' metadata; inferred Claude Code from legacy 'Round 1 — Claude (position)' header — add the metadata block manually for forward compatibility` and proceed with role determination using the inferred value (so a Claude Code port resuming a legacy Claude-scaffolded file correctly takes the initiator role).
     - Grep for `## Round 1 — Codex CLI (position)` / `## Round 1 — Cursor (position)` / `## Round 1 — Aider (position)` (or any other known peer-port literal) → infer that runtime as the initiator. Same advisory shape with the inferred name. This runtime then takes the reviewer role per the standard non-match branch.
     - No inferrable header → **refuse**. Print to stderr and exit: `debate-blocked: <path> has no '**Initiating agent:**' metadata and no inferrable legacy header. Add the metadata block manually (Initiating agent / Reviewing agent / Initiated by — see .agent0/skills/sdd/templates/debate.md.tmpl for the shape) and re-invoke /sdd debate.`

The Resolution-line check distinguishes in-flight vs complete; the Initiating-agent line (or, for legacy files, the inferred initiator) determines this runtime's role. The section header `## Synthesis` is present from scaffold time and is not a discriminator.

### Step 3: Scaffold debate.md — 🔒 Low freedom

Copy `.agent0/skills/sdd/templates/debate.md.tmpl` to `docs/specs/NNN-<slug>/debate.md`. Substitute the standard placeholders (`{{NNN}}`, `{{SLUG}}`, `{{DATE}}` — same as `new`) AND the metadata block at the top:

- `{{initiating agent name}}` → **your own runtime identity** (e.g. `Claude Code` if you are Claude Code, `Codex CLI` if you are Codex, etc.)
- `{{reviewing agent name}}` → leave as the literal placeholder string `{{reviewing agent name}}` (the reviewing runtime fills it on its first write)
- `{{runtime or session label}}` → a short label naming your runtime + session date, e.g. `Claude Code session YYYY-MM-DD` or `Codex CLI session YYYY-MM-DD` (use today's date)

### Step 4: Pre-populate Round 1 — 🔓 Medium freedom

Only runs when this runtime is the initiating agent (no pre-existing file or freshly archived). Replace the `{{round 1 position — initiating agent fills at scaffold time from spec.md}}` placeholder with a structured summary of `spec.md`:

- **Intent** — one paragraph (verbatim or condensed from `spec.md` § Intent)
- **Top 3 acceptance scenarios** — pick the 3 most load-bearing scenarios from `## Acceptance criteria` (skip plain-bullet static facts; favor Given/When/Then behaviors)
- **Top 3 open questions** — verbatim from `spec.md` § Open questions; if fewer than 3 exist, include all
- **Where the initiating agent wants pushback** — 2-3 lines naming the parts of the spec the local agent is least confident about (don't fabricate; if confident throughout, say "I'm confident in scope and acceptance; pushback most useful on Non-goals — is anything missing?")

Leave all other placeholders (`{{round 1 critique}}`, `{{round 2 counter}}`, …) intact for the reviewing agent and later rounds to fill.

### Step 5: Emit handoff instruction — 🔒 Low freedom

Print to the user (substitute the actual `NNN-<slug>`, this runtime's role, and the slot just written). Two shapes — pick the one matching this invocation's role:

When this runtime is the **initiating agent** and just wrote position/counter/synthesis:

```
debate.md is at docs/specs/NNN-<slug>/debate.md.

Local agent (initiating) wrote: <Round N position | Round N counter | Synthesis>.

Next step (you orchestrate):
- To get the next critique: switch to the peer agent's session and invoke its sdd-debate equivalent — it reads debate.md, detects it is the reviewing agent, writes the next empty critique slot.
- When the peer agent finishes its critique, re-invoke /sdd debate here — this runtime re-reads the file, identifies the next empty initiating-agent slot, writes the counter.
- When you decide the debate is done, ask explicitly: "synthesize the debate" — whichever agent you ask writes the Synthesis section + proposes spec.md changes.

The artifact debate.md is the only shared state; both agents read and write it directly. No copy-paste.
```

When this runtime is the **reviewing agent** and just wrote a critique:

```
debate.md is at docs/specs/NNN-<slug>/debate.md.

Local agent (reviewing) wrote: Round N critique.

Next step (you orchestrate):
- Switch to the initiating agent's session and re-invoke its sdd-debate equivalent — it reads debate.md and writes its counter or, if you ask, synthesis.
- If you'd rather end the debate here, ask either runtime to "synthesize the debate" on its next invocation.
```

### Step 6: Round-handling protocol — 🔓 Medium freedom

Each `/sdd debate` invocation on an in-flight debate (Step 2 has already classified this runtime as initiating or reviewing):

1. **Read `debate.md`** — parse the round sections; identify the next slot whose body is still a `{{...}}` placeholder.
2. **Determine slot type based on role AND turn-order prerequisite. Either role, user asked to synthesize → jump to Step 7.** Otherwise:
   - **Initiating agent role.** Look for the first initiating-agent slot still unfilled (Round 1 position, Round 2 counter, Round 3 counter, …). For a counter at Round N (N ≥ 2), the prerequisite is that **Round N-1 critique is filled**.
     - Next slot is a counter at Round N AND Round N-1 critique is empty → report `Waiting on reviewing agent for Round N-1 critique; no initiating-agent counter is ready.` and exit. Do NOT write.
     - Next slot is a counter at Round N AND Round N-1 critique is filled → write the counter (Step 3, counter branch).
     - All initiating-agent slots filled AND user has not asked for synthesis → report `All initiating-agent rounds written; waiting on the reviewing agent for next critique, OR ask me to synthesize when ready` and exit.
   - **Reviewing agent role.** Look for the first reviewing-agent critique slot still unfilled (Round 1 critique, Round 2 critique, Round 3 critique). For a critique at Round N, the prerequisite is that the same-round initiator slot is filled (position when N=1, counter when N≥2).
     - Next slot is a critique at Round N AND the same-round initiator slot is empty → report `Waiting on initiating agent for Round N position` (when N=1) or `Waiting on initiating agent for Round N counter` (when N≥2), followed by `; no reviewing-agent critique is ready.` Exit. Do NOT write.
     - Next slot is a critique at Round N AND the same-round initiator slot is filled → write the critique (Step 3, critique branch). **On first reviewing-agent write only**, if `**Reviewing agent:**` is still the literal placeholder `{{reviewing agent name}}`, replace it with **your own runtime identity** (e.g. `Codex CLI` if you are Codex, `Claude Code` if you are Claude Code).
     - All reviewing-agent critique slots filled → report `All reviewing-agent critiques written; waiting on the initiating agent for next counter, OR ask the initiating agent to synthesize` and exit.
3. **Write the slot:**
   - **Counter** (initiating role): for each critique point in the most recent reviewing-agent critique, classify as **accept** (will propose spec change in synthesis), **reject** (with one-line reasoning), or **defer** (open question; flag for synthesis). Fill the placeholder.
   - **Critique** (reviewing role): list the specific spec.md ambiguities, hidden assumptions, weak acceptance criteria, missing non-goals you can identify. Be concrete — name sections, quote the unclear phrase. Avoid generic praise.
4. **Report** — emit the Step 5 handoff instruction matching this runtime's role.

**No auto-convergence detection. No round-count cap. The user decides when the debate ends** by explicitly asking for synthesis (or just running `/sdd plan` without one). If more rounds than the template's 3 are needed, the user can append `## Round 4 — initiating agent (counter)` / `## Round 4 — reviewing agent (critique)` headers manually; the round-handling logic above keys on placeholder presence and the same-round prerequisite, not round number.

### Step 7: Synthesis — 🔓 Medium freedom

Triggered when the user explicitly asks ("synthesize the debate", "wrap up", "write the synthesis", etc.). Either runtime can perform synthesis — whichever the user asks. Fill the `## Synthesis` section:

- **Resolution** — `converged` (the synthesizing agent judges no new critique points in the latest round) | `cap-reached` (user stopped after a fixed number of rounds) | `abandoned` (user stopped without resolution intent)
- **Proposed spec changes** — bulleted list, each entry naming the `spec.md` section + the delta (e.g. "Add Scenario X to § Acceptance criteria", "Remove Non-goal Y", "Sharpen § Intent paragraph 2")
- **Unresolved disagreements** — for any deferred critique points or open positions; for each, name the initiating agent's view + the reviewing agent's view + why no resolution

Then ask the user: `Accept all proposed changes / edit before applying / reject — what's your call?`

### Step 8: Apply changes — 🔒 Low freedom

On user confirmation:

1. Apply each proposed change to `spec.md` (use Edit, not Write — preserve unchanged sections)
2. Fill the `## Applied changes` section of `debate.md` with the actual edits made (file path + section + brief description)
3. If the user rejected the synthesis, fill `## Applied changes` with "synthesis rejected — no changes applied" and the user's stated reasoning if given
4. Report: `Debate complete. spec.md updated with N changes. Next step: /sdd plan.`

## Subcommand: `plan` — 🔒 Low freedom: read spec, fill plan template

Draft `plan.md` from an existing `spec.md`. No positional argument — operate on the most recent spec dir (highest NNN) unless the user has already named a specific one in conversation.

1. **Locate target** — find the latest `docs/specs/NNN-*/` dir. If multiple are in flight and ambiguous, ask which one.
2. **Read `spec.md`** — refuse if it still has unfilled template placeholders (`{{` substrings) or is essentially empty. Tell the user to fill spec first.
2.5. **Migration advisory** — if the spec's `## Context / references` (or any § Context section in `spec.md`) literally contains the substring `app-skeleton/`, emit a one-line advisory to stderr: `migration-advisory: foundation spec references the deleted app-skeleton template; re-run research at /sdd plan time per the stack-aware handoff discipline`. Non-blocking — `/sdd plan` proceeds with step 3.
3. **Draft `plan.md`** — preserve the existing template section headers; fill them from `spec.md` + your understanding of the codebase. For "Alternatives considered" you MUST list at least one rejected option with reasoning — if there genuinely was no alternative, say so explicitly ("no real alternatives; only viable approach is X because Y").
4. **Cite research** — if the spec or plan involved web research or codebase exploration, link the sources in the plan. This satisfies `research-before-proposing.md`.
5. **Report** — output `plan.md` path. Tell the user to review and confirm before `/sdd tasks`.

## Subcommand: `tasks` — 🔒 Low freedom: read plan, decompose into ordered checklist

Generate `tasks.md` from `plan.md`. Same target-selection rule as `plan`.

1. **Locate target** — find the latest spec dir (or the one in conversation).
2. **Read `plan.md`** — refuse if it has unfilled template placeholders.
3. **Decompose into tasks** — each task should be:
   - Small enough that completion is unambiguous (passes/fails clearly)
   - Independently checkable (testable, observable, or produces a concrete artifact)
   - Ordered by dependency — earlier tasks unblock later ones
   - Numbered (`1.`, `2.`, …) with checkbox prefix (`- [ ]`)
4. **Include verification** — the last 1-2 tasks should be acceptance checks against the criteria in `spec.md` (run tests, verify behavior, sanity checks).
5. **Report** — output `tasks.md` path. Tell the user implementation is now mechanical: work the tasks top-to-bottom, check off as completed, update `plan.md` if any task reveals plan is wrong.

## Subcommand: `list` — 🔒 Low freedom: scan + format

List all specs in the repo with a one-line status each. Supports two opt-in flags: `--in-flight` (filter to active work) and `--json` (machine-readable output, agent-friendly). Both are independent; any combination is legal.

1. Scan `docs/specs/` for `NNN-*/` dirs (sorted by NNN ascending).
2. For each, emit one line (default text output): `NNN-<slug>  [status]  — <h1 of spec.md, or "(no spec)" if empty>`.
3. Resolve status using **declared truth first, derived heuristic as fallback**:
   - **Declared (preferred):** read `spec.md` for a `^\*\*Status:\*\* (draft|in-progress|shipped|superseded)` line. If present, that value is the status — overrides the derived heuristic everywhere (bare output and `--in-flight` alike).
   - **Derived (fallback when no `**Status:**` line is present):**
     - `spec` — `spec.md` has content but `plan.md` still has placeholders
     - `plan` — `plan.md` filled but `tasks.md` still has placeholders
     - `tasks` — `tasks.md` filled, some unchecked boxes remain
     - `done` — all checkboxes in `tasks.md` are checked (`- [x]`)
     - `empty` — `spec.md` still has `{{` placeholders

### Status semantics

Nine total states reachable: four declared (`draft`, `in-progress`, `shipped`, `superseded`) and five derived (`spec`, `plan`, `tasks`, `done`, `empty`). The declared set carries author intent; the derived set is the safety-net inference for specs that pre-date this convention or whose author skipped setting `**Status:**`. `superseded` is reserved for specs replaced by a later one — write `**Status:** superseded by 0NN-<slug>` so the inline slug names the replacement.

### Flag: `--in-flight`

Filter the output to active work. A spec is in flight iff:

- Declared `Status ∈ {draft, in-progress}` — OR
- Declared `Status` is absent AND derived state ∈ {`spec`, `plan`, `tasks`} AND last git activity on the dir is within the recency window

The recency window defaults to **14 days** (matches typical session-stretch length). Override with `CLAUDE_SDD_IN_FLIGHT_RECENCY_DAYS=<integer>` env var.

Specs with declared `shipped` or `superseded`, derived `done`, or derived `empty` are excluded. Derived `tasks` older than the recency window is also excluded — this is the false-positive case (`tasks.md` carries residual unchecked boxes from a long-shipped capacity).

`--in-flight` row shape, one line per spec:

```
NNN-<slug>  [status]  N/M acceptance unchecked  last activity Yd ago  — <h1>
```

Where:

- `[status]` is the resolved value (declared or derived)
- `N` = count of `- [ ]` bullets directly under `## Acceptance criteria` in `spec.md`, all nesting depths included (scenario sub-bullets AND plain static-fact bullets both count)
- `M` = total count under that section (`N` unchecked + checked)
- `last activity Yd ago` from `git log -1 --format=%ar -- docs/specs/NNN-<slug>/`

If the `## Acceptance criteria` section is missing or malformed, render `N/M` as `?/?` (text mode) and emit `null` for both counts in JSON — distinguishable from zero.

### Flag: `--json`

Emit a JSON array on stdout, one object per spec. Shape:

```json
[
  {
    "nnn": "029",
    "slug": "sdd-list-in-flight",
    "status": "in-progress",
    "acceptance_unchecked": 5,
    "acceptance_total": 8,
    "last_activity_iso": "2026-05-16T14:32:11+00:00",
    "h1": "029 — sdd-list-in-flight"
  }
]
```

Keys: `nnn` (string, zero-padded 3-digit), `slug` (string), `status` (string — one of the 9 reachable states), `acceptance_unchecked` (integer or `null`), `acceptance_total` (integer or `null`), `last_activity_iso` (string, ISO-8601 from `git log -1 --format=%aI -- <dir>`), `h1` (string — first `# ` line of `spec.md`).

`--json` is **shape-only convenience** for ad-hoc agent reads. It is **NOT a versioned wire contract** — the field set may evolve. Consumers that hard-depend on this shape do so at their own risk; no schema-version key is emitted, deliberately.

Flag combinations:

- `/sdd list` — bare text output, all specs, default behaviour (declared status now honoured)
- `/sdd list --in-flight` — text output, in-flight subset only, enriched row shape
- `/sdd list --json` — JSON array, all specs
- `/sdd list --in-flight --json` — JSON array, in-flight subset only

## Unknown subcommand

If the first token of `$ARGUMENTS` is missing or not one of `new`, `refine`, `debate`, `plan`, `tasks`, `list`, refuse with a one-line usage hint:

```
/sdd <new <slug> | refine [<idea> | NNN] | debate | plan | tasks | list>
```

## Eval Scenarios

### Eval 1: Happy path — `new <slug>` from a clear idea

**Input:** User says `/sdd new auth-rewrite` after describing the change conversationally.

**Expected:** Slug regex passes; no `docs/specs/NNN-auth-rewrite/` collision. Next NNN computed by scanning existing `NNN-*` dirs and incrementing. Four template files copied (`spec.md`, `plan.md`, `tasks.md`, `notes.md`) and `{{SLUG}}` / `{{NNN}}` / `{{DATE}}` substituted in each. Four paths reported. Skill stops short of auto-filling `spec.md` — user is asked to fill it OR explicitly opt into a draft from the conversation. `notes.md` left empty (populated only during implementation).

**Failure indicators:** Spec dir number conflicts with an existing dir (scan skipped). Placeholder `{{SLUG}}` left literal in some file. `spec.md` auto-filled with invented content the user never confirmed. `notes.md` pre-populated.

### Eval 2: Refine an existing spec mid-flight

**Input:** User says `/sdd refine 087` after the plan has started but the spec needs additional acceptance scenarios.

**Expected:** Resumability path triggers — `spec.md` read first; `plan.md` filled state detected; warning emitted ("refining intent after planning has started; re-run `/sdd plan` afterward to resync") but flow not blocked. Step 0 context load runs silently. Discovery rounds challenge the additions at least twice (scope creep guard). At least 4 of 7 question-bank categories covered. Synthesis surfaces a structured summary for user confirmation; on confirmation, `spec.md` rewritten preserving existing checked items.

**Failure indicators:** Discovery skipped on resumability path (jump straight to synthesis). Sycophantic ("great idea") phrases in any round. Round 1 starts without context load. Synthesis overwrites already-checked acceptance criteria. No re-plan reminder issued at close.

### Eval 3: `list --in-flight` filter behavior

**Input:** User says `/sdd list --in-flight` mid-week to assess what's still active.

**Expected:** Scan `docs/specs/` for `NNN-*/` dirs. Resolve status — declared `**Status:**` line wins; derived heuristic fallback otherwise. Filter to specs whose status ∈ {draft, in-progress} OR derived ∈ {spec, plan, tasks} with git activity within 14 days (or `CLAUDE_SDD_IN_FLIGHT_RECENCY_DAYS` override). Per-row output: `NNN-<slug>  [status]  N/M acceptance unchecked  last activity Yd ago  — <h1>`. Specs with declared `shipped`/`superseded` or derived `done`/`empty` excluded. Stale `tasks` rows (>14d) excluded.

**Failure indicators:** Shipped specs included in --in-flight output. Acceptance counts (N/M) computed only on top-level bullets (missing scenario sub-bullets). Status line declared as `in-progress` but the row uses a derived value instead. JSON shape leaks (--json not requested but output is JSON).

### Eval 4: This runtime initiates — scaffold + Round 1 position

**Input:** User has filled `spec.md` in `docs/specs/NNN-<slug>/` and invokes `/sdd debate`. No prior `debate.md` exists.

**Expected:** Latest spec dir resolved. `spec.md` read; no `{{` placeholders. `debate.md` scaffolded from template; `{{NNN}}`/`{{SLUG}}`/`{{DATE}}` substituted as usual AND the metadata block filled — `**Initiating agent:** Claude Code`, `**Reviewing agent:** {{reviewing agent name}}` (placeholder retained), `**Initiated by:** Claude Code session <today's date>`. Round 1 — initiating agent (position) populated with structured summary (intent + top 3 scenarios + top 3 open questions + "where the initiating agent wants pushback"). All other round placeholders left intact. Handoff instruction emitted in the **initiating-agent shape** (Step 5 first variant) — directs the user to the peer agent for the critique.

**Failure indicators:** `**Initiating agent:**` left as placeholder or filled with anything other than `Claude Code`. Round 1 position left as `{{...}}`. Reviewing-agent placeholder overwritten at scaffold time. Wrote a critique slot instead of the position. Auto-applied changes to `spec.md`. Refused on unfilled `spec.md` placeholders skipped. Reviewing-agent handoff message used (wrong role variant).

### Eval 5: Peer runtime initiated — this runtime writes critique

**Input:** A peer agent (e.g. Codex CLI) has previously run its own `/sdd debate` against `docs/specs/NNN-<slug>/` and the scaffolded `debate.md` carries `**Initiating agent:** Codex CLI` (or any value other than `Claude Code`). Round 1 — initiating agent (position) is filled. User invokes `/sdd debate` in this Claude Code session.

**Expected:** State detected as in-flight (Resolution still placeholder). `**Initiating agent:**` value read; does NOT match `Claude Code` → this runtime is the **reviewing agent**. No scaffolding, no overwrite of position. Round 1 — reviewing agent (critique) slot found empty; concrete critique written (named spec sections, quoted unclear phrases, missing non-goals, weak acceptance scenarios). `**Reviewing agent:**` literal placeholder replaced with `Claude Code` on this first reviewer write. Handoff instruction emitted in the **reviewing-agent shape** (Step 5 second variant) — directs the user back to the peer (initiator) for the counter.

**Failure indicators:** Overwrote Round 1 position. Filled `{{round 1 counter}}` instead of `{{round 1 critique}}`. Treated self as initiator despite metadata. Left `**Reviewing agent:**` as placeholder. Initiating-agent handoff message used (wrong role variant). Refused or warned.

### Eval 6: Re-invocation by initiating agent — writes counter

**Input:** `debate.md` already carries `**Initiating agent:** Claude Code` and Round 1 position. Reviewing agent has filled Round 1 critique. User re-invokes `/sdd debate` in this Claude Code session.

**Expected:** State in-flight. `**Initiating agent:**` matches `Claude Code` → role = initiator. Round 1 critique read; next empty slot is `{{round 2 counter}}`. For each critique point, classify accept/reject/defer with one-line reasoning, fill the placeholder. Handoff instruction emitted in the initiating-agent shape — "waiting on reviewing agent for next critique, or ask to synthesize".

**Failure indicators:** Wrote a critique slot (wrong role). Skipped the per-point classification. Auto-asked to synthesize without the user requesting it. Auto-stopped at any round count.

### Eval 7: Re-invocation by reviewing agent — writes critique

**Input:** `debate.md` carries `**Initiating agent:** Codex CLI` (or similar non-`Claude Code` value). Round 1 position + Round 1 critique + Round 2 counter all filled. User invokes `/sdd debate` in this Claude Code session for the next round.

**Expected:** State in-flight. `**Initiating agent:**` does NOT match `Claude Code` → role = reviewer. Next empty slot is `{{round 2 critique}}`. Concrete critique written addressing the most recent counter (rebut what was rejected; add new issues if seen). `**Reviewing agent:**` was already filled on the first reviewer write — no change. Handoff instruction emitted in the reviewing-agent shape.

**Failure indicators:** Wrote a counter slot (wrong role). Re-filled `**Reviewing agent:**` overwriting the prior value. Treated self as initiator. Refused because the file was past Round 1.

### Eval 8: Initiator re-invocation when prior critique is missing — refuses to write

**Input:** `debate.md` carries `**Initiating agent:** Claude Code` (this port). Round 1 position is filled. Round 1 critique is still the literal placeholder (the reviewing agent has not run yet). User re-invokes `/sdd debate` in this Claude Code session.

**Expected:** State in-flight. Role = initiator. The next initiating-agent slot is `{{round 2 counter}}`. Prerequisite check: Round 1 critique empty → report `Waiting on reviewing agent for Round 1 critique; no initiating-agent counter is ready.` and exit. No write to `debate.md`. No call to Step 7.

**Failure indicators:** Wrote Round 2 counter despite Round 1 critique being empty (the canonical bug this gate exists to prevent). Wrote a reviewing-agent slot (wrong role). Jumped to synthesis without the user asking. Phrased the waiting message with the wrong round number (e.g. saying "Round 2 critique" when the missing prerequisite is Round 1).

### Eval 9: Legacy file with Claude-coupled headers — inferred initiator + advisory

**Input:** `debate.md` exists but has no `**Initiating agent:**` metadata line. The file's Round 1 header is the literal `## Round 1 — Claude (position)` (a debate scaffolded by the pre-runtime-neutral version of this skill). User invokes `/sdd debate` in this Claude Code session.

**Expected:** Step 2 fallback fires. Grep finds the legacy `## Round 1 — Claude (position)` header → infers Initiating agent = `Claude Code`. Stderr advisory: `debate-advisory: <path> has no '**Initiating agent:**' metadata; inferred Claude Code from legacy 'Round 1 — Claude (position)' header — add the metadata block manually for forward compatibility`. Inferred value matches this port's identity → role = initiator. Proceed to Step 6 with the inferred role. No write to the metadata block (the inference is in-memory; the user adds the block manually per the advisory).

**Failure indicators:** Defaulted to "local runtime is initiator" without grepping for legacy headers (the unsafe pre-fix behaviour). Mutated `debate.md` to insert a metadata block automatically. Refused with the no-inferrable-header message even though a legacy header was present. Inferred Claude Code but then took the reviewer role.

### Eval 10: Legacy file with no inferrable header — refuses + asks for manual migration

**Input:** `debate.md` exists, has no `**Initiating agent:**` metadata, AND has no recognisable legacy round header (e.g. a hand-written file or a header pattern from a runtime the inference list doesn't know). User invokes `/sdd debate`.

**Expected:** Step 2 fallback runs the grep, finds no `## Round 1 — <known-runtime> (position)` match. Refuse: print to stderr `debate-blocked: <path> has no '**Initiating agent:**' metadata and no inferrable legacy header. Add the metadata block manually (Initiating agent / Reviewing agent / Initiated by — see .agent0/skills/sdd/templates/debate.md.tmpl for the shape) and re-invoke /sdd debate.` Exit. No write to `debate.md`, no role taken, no jump to Step 6.

**Failure indicators:** Proceeded with "assume local runtime is initiator". Mutated the file to insert metadata. Proceeded with an incorrect inferred runtime (e.g. inferring Claude Code from a non-matching header).

## Notes

_Consumer-extension surface — append consumer-local bullets to this section. Sync flags the file as `!! customized` (sha-compare is section-blind), but the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end. See `.agent0/context/rules/harness-sync.md` § Consumer-extension convention._

- Specs are **git-tracked** — they are project memory, not scratch. Don't gitignore them.
- The skill provides *structure*; you (Claude) provide *content*. Don't auto-fill `spec.md` — the user owns intent.
- If the user describes a change conversationally and SDD applies (per `.agent0/context/rules/spec-driven.md`), offer to run `/sdd new <slug>` rather than diving into code.
