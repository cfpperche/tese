---
name: product
description: Foundation generator + design partner for the product lifecycle (idea → v1 → vN). 15-step industry-aligned pipeline produces every planning artifact (concept brief, functional spec, UX audit, PRD, OST, sitemap-IA, system design, legal, roadmap, cost, GTM, brand, design system) plus a visual contract (lo-fi mood + navigable screen-atlas + hi-fi killer-flow mood + fixture-spec), then scaffolds the SDD umbrella + foundation child spec the engineering build runs as. Does NOT generate a runnable app — the visual contract hands off to SDD. Output is a docs-first tree at a user-specified path. 5 phases - Discovery / Specification / Identity / Visual-contract / SDD-handoff - with 3 AskUserQuestion gates after steps 4/12/14. No stack code ships — Phase 5 reads system-design + roadmap to compute a stack-aware umbrella matrix; the foundation child's `/sdd plan` researches the declared stack. Flags - `<idea>` `--stack=<next|expo>` `--out=<path>` `--from-step=NN` `--skip-prd` `--skip-brand`. See `references/{pipeline-coverage,state-machine,delegation-briefs,sdd-handoff}.md`. v0.5.0.
license: MIT
compatibility: Designed for Claude Code. Body references `.claude/` conventional paths, dispatches Agent tool with 5-field handoffs (delegation-gate), uses AskUserQuestion at phase gates, optionally uses Playwright MCP for screenshots. Not portable to runtimes that lack these surfaces.
metadata:
  agent0-portability-tier: cc-native
  skill-version: "0.5.0"
argument-hint: "<idea>" --out=<path> [--stack=<next|expo>] [--from-step=NN] [--skip-prd] [--skip-brand]
---

# /product — 15-step foundation generator + design partner

Takes a founder's one-line idea and produces a complete v1-ready product foundation at `<--out>`: concept brief (with market sizing) → lo-fi prototype (mood + killer flow) → functional spec (with problem-validation interviews) → UX audit → PRD 1-pager → OST (Opportunity Solution Tree) → sitemap-IA (full screen inventory with required_categories enforcement) → system design (with RACI + risk + data-flow inventory) → legal posture (DPIA-triggered by data-flow, NOT end-of-pipeline) → roadmap (defines phases) → cost estimate (per-phase using roadmap) → GTM-launch → brand book → design system → **visual contract** (navigable screen-atlas + hi-fi killer-flow mood + fixture-spec) → **mandatory SDD handoff** (scaffolds the umbrella + foundation child spec the engineering build runs as). 5 phases with 3 condensed user gates. **`/product` produces a docs-first foundation, NOT a runnable app** — semantic naming (no NN- prefix), PRD release-scoped at `docs/prd/v1.md`, design system grouped at `docs/design-system/`. The app build is the SDD workflow working the scaffolded specs. Founder reads `docs/REPORT.html` — a navigable, rendered reading surface regenerated at every gate — or `docs/REPORT.md` for the plain temporal narrative; the structure supports v2/v3/vN evolution without manual reorg.

**v0.5.0 product-stack-aware-handoff** — Agent0 stops shipping stack code. The bundled `templates/app-skeleton/{next,expo}/` directories and `references/stack-defaults.md` snapshot are deleted. Phase 5 now reads `docs/system-design.md § Stack/Services/Open Decisions` + `docs/roadmap.md` Fase 1 deliverables and computes a stack-aware umbrella matrix — infra children (one per unmatched Fase 1 deliverable) block-precede the per-phase visual children. The foundation child (`002-foundation`) is research-driven: its `/sdd plan` runs web research per `.agent0/context/rules/research-before-proposing.md` to determine the current canonical setup for the declared stack. Step 8 (system-design) receives `--stack` as a `**Stack hint from invocation:**` line — a default the product class either justifies or overrides; the final § Stack section is the binding contract. The 15-step pipeline is intact; only Phase 5 + Step 08 brief changed.

**v0.4.0 product-ui-quality** — the v2/v3 36-route per-route screen-writer fan-out is **deleted**. `/product`'s visual-contract phase now ends at `screen-atlas.md` + a hi-fi killer-flow mood (static HTML) + `fixture-spec.md`, then **mandatorily hands off to SDD** — Phase 5 scaffolds an umbrella spec + the foundation child spec, the rest of the children listed in the umbrella's matrix. `/product` keeps its strength (design synthesis → visual contract) and stops doing what it did badly (blind-fan-out screen generation). v0.3.0 and earlier are superseded.

**Required reading before execution:**
- `references/pipeline-coverage.md` — what each of the 15 steps produces at standard tier
- `references/state-machine.md` — `.state.json` v5 shape + 5-phase progression + resume support (breaking: refuses silent v4 → v5 upgrade)
- `references/delegation-briefs.md` — 5-field briefs for every sub-agent dispatch (one per pipeline step; Step 15 = 15a-atlas / 15b-hi-fi-mood / 15c-fixture-spec; the shared mood-screen-writer template)
- `references/sdd-handoff.md` — the Phase 5 contract: how to scaffold the umbrella spec + foundation child from the pipeline artifacts
- `references/quality-judge.md` — the quality judge: when it runs, rubric assembly, the verdict shape, the verdict→gate routing
- `references/quality-checklist.md` — the quality judge's semantic rubric (per-step + visual-contract criteria) + the deterministic orchestrator gates
- `references/sitemap-schema.md` — `required_categories` enforcement + per-route field set (load-bearing — orchestrator BLOCKS Step 07 if uncovered category found without `deferred_categories` declaration)

## Argument parsing

User invokes as `/product "<idea>" --out=<path> [flags]`. The raw argument string is `$ARGUMENTS`. Parse it yourself:

1. First quoted-token is `<idea>` — refuse with `usage: /product "<idea>" --out=<path> [flags]` if missing.
2. `--out=<path>` is REQUIRED — refuse if missing. Resolve to absolute path.
3. Optional flags (any order after idea): `--stack=<name>` (next | expo; default: web stack inferred from idea → next), `--from-step=NN` (resume from step N in range 1-15), `--skip-prd` (omit Step 05 dispatch — degenerate; PRD feeds Steps 06-15), `--skip-brand` (omit Step 13 + fall back to `templates/default-tokens.css`).
4. Compute `slug` = kebab-case from idea (lowercase, alphanumeric + hyphens, max 40 chars).

## Phase 0 — Setup + idempotency check + resume detection — 🔒 Low freedom: deterministic file scan + harness filter

1. **Idempotency check** — list files at `<out>`. Filter out the **Agent0 harness allowlist** (these are exempt; a freshly-bootstrapped Agent0 consumer project is "fresh" from `/product`'s perspective):

   ```
   .claude/        .githooks/         .gitignore
   .gitleaks.toml  .mcp.json.example  CLAUDE.md      .git/
   ```

   Compute `<remaining>` = files at `<out>` MINUS the harness allowlist above (recursive — `.claude/**`, `.githooks/**`, `.git/**` all count as harness).

   - **If `<remaining>` is empty** (or `<out>` doesn't exist): proceed to step 2 (Init) — no prompt, no rm, harness preserved. This is the path for `mkdir <consumer project> && sync-harness <consumer project> && /product --out=<consumer project>`, the natural harness-disciplined-from-day-1 founder workflow.
   - **If `<remaining>` is non-empty:**
     - If `--from-step=NN` was passed AND `<out>/docs/.state.json` exists: read state, validate (a) `version == 5` — if v4 found, abort with `state v4 found — older /product run; clear --out dir or run fresh /product`; if v3 found, abort with `state v3 found — older /product run; clear --out dir or run fresh /product`; if v2 found, abort with `state v2 found — older /product run; clear --out dir or run fresh /product`; (b) `slug`/`idea`/`flags.stack` match the invocation; if mismatch, abort with `state mismatch — clear --out dir or pick different --from-step`. If both pass, jump to step NN.
     - Else (no `--from-step` OR no `.state.json`): prompt `<out> exists with prior /product artifacts. Overwrite the non-harness artifacts? (.git/ history and the Agent0 harness are preserved) (y/N) ▷`. On `y` → run `bash .claude/skills/product/scripts/clear-target.sh <out>`, which removes every top-level entry NOT in the harness allowlist (the `<remaining>` set) — `.git/` history and the bootstrapped harness survive; the removed paths surface as deletions in the operator's post-run `git diff` (the audit trail). On `n` / no answer → abort cleanly with `aborted; pick a different --out or rm the existing dir yourself`. Exit 0.

   **Harness allowlist drift:** the 7-path list above is mirrored in two other places — `.agent0/tools/sync-harness.sh`'s manifest, and the `ALLOWLIST` constant in `.claude/skills/product/scripts/clear-target.sh` (the script the overwrite invokes). If the manifest gains a new path (e.g. `.envrc` someday), audit all three — otherwise the new harness file would falsely trigger the overwrite prompt, or be deleted outright by `clear-target.sh`.

2. **Init** — `mkdir -p <out>/docs/screens/hifi <out>/docs/prd <out>/docs/design-system <out>/docs/specs <out>/docs/.quality`; write fresh `<out>/docs/.state.json` per `state-machine.md` v5 shape with `version=5, phase="discovery", step=0, started_at=<ISO>, gates_passed=[], completed_steps=[], blocked_steps=[], iterations={discovery:0, specification:0, identity:0}, quality_verdicts={}, completed_at=null, target_language=null`. **Artifact layout discipline:** `/product` produces a docs-first foundation, NOT a runnable app. EVERY skill-produced output writes under `<out>/docs/` — pipeline deliverables semantic-named (`docs/concept-brief.md`, `docs/sitemap.yaml`, `docs/system-design.md`, etc. — NO `NN-` prefix), PRD release-scoped at `docs/prd/v1.md`, design system grouped at `docs/design-system/{tokens.css, components.md, README.md}`, lo-fi mood at `docs/screens/`, hi-fi mood at `docs/screens/hifi/`, the SDD specs at `docs/specs/`, the run report at `docs/REPORT.md`, the state file at `docs/.state.json`. The `<out>/` root holds only `docs/`, the `.mcp.json` seeded in step 3, and whatever Agent0 harness was bootstrapped. The runtime tree (`app/`, `lib/`, `package.json`, `node_modules/`, build config) does NOT exist after `/product` — the SDD foundation child (Phase 5) scaffolds it. Temporal ordering of pipeline steps survives via REPORT.md + .state.json; semantic naming wins for the founder's day-to-day mental model.

3. **Seed `<out>/.mcp.json`** — write the Playwright MCP server block so visual verification is available to the Phase 4 best-effort check AND to every SDD-child session the founder later opens. The block: `{ "mcpServers": { "playwright": { "command": "npx", "args": ["@playwright/mcp@latest"] } } }`. **Append-aware:** if `<out>/.mcp.json` already exists, parse it and merge the `playwright` key into the existing `mcpServers` object — do NOT overwrite other servers. If absent, write the file fresh. (`.mcp.json` is strict JSON — no comments; the reference block lives commented in `.mcp.json.example`, but the file written here is valid JSON.) MCP servers load at session start, so the Playwright tools are live for *this* `/product` run only if the session already had them; otherwise the Phase 4 visual check is best-effort-skipped and the seed pays off for the SDD-child sessions.

## Phase 0.5 — Target language resolution — 🔒 Low freedom: detect or read user-supplied locale

Resolves `target_language` BEFORE Step 01 dispatches so every downstream sub-agent generates user-facing text in the right language. Runs ONCE per fresh run (skipped on `--from-step` resume — state already carries the value).

1. **Heuristic from idea string** — scan `<idea>` for signals:
   - Portuguese cues: any of `R$` / `LGPD` / `NFS-e` / `Pix` / `CNPJ` / `CPF` / `clínica` / `salão` / `petshop`, OR pt-BR diacritics (`á é í ó ú ã õ ç`) anywhere in the string → propose `pt-BR`.
   - Spanish cues: `€` (combined with `IVA` / `S.L.` / `México` / `España`), OR es diacritics (`ñ ¿ ¡`) → propose `es-ES` or `es-MX` (favor `es-ES` if ambiguous).
   - Otherwise → propose `en` (US default; `en-GB` only if `Ltd` / `programme` / `colour` appear).
2. **`AskUserQuestion` — single question, 2-4 options**:
   - Q: `Target language for all artifacts (PRD, brand-book, screen copy, etc)?`
   - Options: `<proposed> (Recommended)` · `en` · `pt-BR` · `Other` (founder types BCP-47 tag like `es-MX`, `fr-FR`, etc).
   - The (Recommended) label uses whichever the heuristic proposed.
3. **Store** — write `target_language` into `<out>/docs/.state.json` (BCP-47 string). This is now the canonical signal for every brief substitution + brand-book Step 13 § Language section.

**On `--from-step` resume:** read `.state.json.target_language`. If null (older state without language field), run the heuristic + ask. If present, use as-is (no re-ask).

**Override:** founder can edit `.state.json.target_language` between phases — downstream sub-agents read the current value at dispatch time, so changes mid-run propagate to subsequent steps (but artifacts already written stay in their original language until re-iterated).

## Quality judge — runs after every step — 🔒 Low freedom: canonical rubric, deterministic verdict

After a phase's step producers return, the orchestrator grades each step's artifact(s) with the **quality judge** — an independent `opus` sub-agent — before building the report and reaching the gate. The judge is the scope/quality verdict that replaced the retired size budget; it answers *"is this artifact correctly scoped, complete, and coherent for its declared job?"*. Full contract: `references/quality-judge.md`. Each phase's "Update `.state.json`" step invokes this routine over that phase's steps.

For each **judge-unit** in the phase (steps 01-14 = the step; Step 15 = `15a-screen-atlas` / `15b-hifi-mood` / `15c-fixture-spec`):

1. **Anti-stub pre-filter.** `wc -c` each of the step's required artifacts against the `min_size` in `templates/pipeline/<NN-step>/schema.md § Size floor`. Below floor → the artifact is a **stub**: re-dispatch the step's producer with a brief naming the stubbed artifact, and do NOT spend a judge call on it. (A 200 KB runaway is circuit-broken upstream by the producer brief's catastrophe cap — the judge never receives one.)
2. **Dispatch the judge.** One `Agent` call per judge-unit per `references/delegation-briefs.md § Quality judge` — `model: opus`, `subagent_type: general-purpose`. Substitute `{{step_label}}`, `{{artifact_paths}}` (the step's outputs), `{{schema_dir}}` (`.claude/skills/product/templates/pipeline/<NN-step>/`), `{{rubric_section}}` (the `### NN — <name>` heading in `quality-checklist.md`), `{{verdict_path}}` (`<out>/docs/.quality/<step_label>.json`), `{{out}}`. Judge calls within a phase are independent — read-only on the artifacts, each writing a distinct verdict path — so dispatch them in parallel, **cap 5 concurrent**. No worktree isolation needed (no overlapping writes).
3. **Merge the verdict.** Read each `<out>/docs/.quality/<step_label>.json`, stamp `model` with the dispatched model, and write it into `<out>/docs/.state.json` `quality_verdicts[<step_label>]` (a map — a re-judged step overwrites its key).
4. **Route by `outcome`** (per `quality-judge.md § Verdict → gate routing`):
   - `pass` — recorded only.
   - `concern` — recorded; surfaces in `REPORT.md § Quality concerns` (advisory, no gate action).
   - `fail` — recorded; surfaces in `REPORT.md § Quality concerns`; AND flags the phase's downstream gate (below).

**Verdict → phase-gate routing.** At a phase gate (`gate_discovery` / `gate_specification` / `gate_identity`), before invoking `AskUserQuestion`, collect every `quality_verdicts` entry for that phase's steps. If any has `outcome: "fail"`, the gate's **recommended** option is `iterate`, and the `iterate` sub-prompt is pre-filled with the failed steps + their failed criteria — the human still chooses `continue` / `iterate` / `abort` (the judge never decides). If none failed, `continue` stays recommended. The iteration soft-cap (`state-machine.md § Gate UX` — warn at 3, force-abort at 5) still bounds the loop.

**Phase 4 has no gate** — a `15a`/`15b`/`15c` `fail` cannot pre-populate a gate, so it surfaces in `REPORT.md § Quality concerns` and the Phase 5 terminal handoff message.

The judge never autonomously BLOCKs or aborts — deterministic structural BLOCK/abort stays the `schema.md` Layer 1 + orchestrator job (`delegation-briefs.md § Failure handling`). A judge `fail` is orthogonal to BLOCKED: a step in `completed_steps` can still carry a `fail` verdict.

## Phase 1 — Discovery (pipeline steps 01-04) — 🔓 Medium freedom: content adapts to detected scope

**Read `references/delegation-briefs.md` § "Phase 1 — Discovery" BEFORE dispatching.** Each Agent call uses the 5-field template there.

1. **Step 01 — Ideation** (BLOCKING) — dispatch Sub-agent A per § Step 01 brief. **model: opus.** Returns `<out>/docs/concept-brief.md` (includes market sizing TAM/SAM/SOM section per Decision 6). If BLOCKED: ABORT the entire run.
2. **Step 02 — Prototype v1 (lo-fi)** — dispatch direction-writer per § Step 02 brief. Returns `<out>/docs/direction-a.html` + 3-5 killer-flow HTML mood screens at `<out>/docs/screens/NN-<name>.html`. Note: sitemap is NO LONGER produced at Step 02 (moved to its own Step 07 — sitemap-IA). Step 02 outputs are pure mood/visual exploration of the killer flow.
3. **Step 03 alone, then Step 04 alone** (NOT parallel). Step 03 produces `functional-spec.md`; Step 04's CONTEXT explicitly reads `functional-spec.md` (audit input), so the two dispatches MUST NOT share a single message. Dispatch Step 03 per § Step 03 brief (`sonnet`; extends with § Problem-Validation Interviews per Decision 6); after Step 03 returns, dispatch Step 04 per § Step 04 brief (`sonnet`).
4. **Update `.state.json`, then run the quality judge** — append to `completed_steps`; any BLOCKED to `blocked_steps`; then run the **quality judge** over Steps 01-04 per § Quality judge (anti-stub pre-filter → judge dispatch → merge verdicts into `quality_verdicts` → route).
5. **Build the HTML report** — run `bun .claude/skills/product/scripts/build-report.ts --out=<out> --slug=<slug> --stack=<stack>`. Regenerates `<out>/docs/REPORT.html` — the navigable reading surface for every artifact produced so far (steps not yet run render as greyed-out "not yet generated"). Best-effort: if `bun` is unavailable or the script errors, emit a one-line `report-html-skipped: <reason>` advisory and continue — this never blocks the gate.
6. **Gate — `gate_discovery`** — `AskUserQuestion` with 3 options. Tell the user to review the artifacts in `<out>/docs/REPORT.html` (open in a browser) before choosing. Per § Quality judge, if any Step 01-04 `quality_verdicts` entry has `outcome: "fail"`, the **recommended** option is pre-set to `iterate` (citing the failed step + criterion); otherwise `continue` is recommended:
   - `continue` → proceed to Phase 2 — Specification (append `discovery` to `gates_passed`).
   - `iterate` → user names which step(s) to re-dispatch (sub-prompt). Re-dispatches with augmented brief. Increment `iterations.discovery`. Re-gate after.
   - `abort` → exit cleanly; set `flags.from_step = current_step`; print resume command.

## Phase 2 — Specification (pipeline steps 05-12) — 🔓 Medium freedom: artifact content adapts to phase-1 outputs

The biggest phase (8 steps). Internal dispatch DAG follows dependency order; some parallelize, others are strictly serial.

1. **Step 05 — PRD 1-pager** (BLOCKING; downstream depends on US-NN stable IDs). Dispatch per § Step 05 brief. Returns `<out>/docs/prd/v1.md` in Lenny 1-pager hybrid shape (Problem · Why now · Success metrics with NSM slot · Solution sketch · User stories · Anti-goals + 3 our-specific: Release scope · NSM-dedicated-slot · Upstream/downstream refs). 4-7 KB tight target.
2. **Steps 06 + 07 — parallel fan-out** — dispatch TWO sub-agents in ONE MESSAGE per § Step 06 (OST) + § Step 07 (sitemap-IA) briefs. Both read Step 05 PRD. Step 06 = Opportunity Solution Tree (Teresa Torres methodology). Step 07 = full screen inventory YAML with schema-bound `required_categories`.
3. **Step 07 acceptance check** — orchestrator parses returned `<out>/docs/sitemap.yaml` and enforces `references/sitemap-schema.md` § required_categories: every category in `[marketing, auth, primary, admin, error]` must have ≥1 route OR be explicitly listed in top-level `deferred_categories: [{name, reason}]`. **If any required category has 0 routes AND no deferral, BLOCK Step 07 + re-dispatch with augmented brief naming the missing category(ies).** This is the load-bearing mechanical fix for the Pass-E silent-undercover bug.
4. **Step 08 — System design** (depends on Step 05 PRD + Step 07 sitemap). Dispatch per § Step 08 brief. Returns `<out>/docs/system-design.md` + `<out>/docs/security.md` + `<out>/docs/data-flow.json` (the data-flow inventory consumed by Step 09 legal for DPIA trigger). Extended with § RACI Matrix + § Risk Register per Decision 10.
5. **Step 09 — Legal posture** (depends on Step 08 data-flow inventory — shift-left per Decision 4). Dispatch per § Step 09 brief. Reads `<out>/docs/data-flow.json` for DPIA trigger; if data-flow includes sensitive categories (PII / health / minors / financial), DPIA section becomes mandatory. Returns `<out>/docs/legal-posture.md`.
6. **Step 10 — Roadmap** (depends on Step 05 PRD priorities + Step 08 dependencies). Dispatch per § Step 10 brief. Returns `<out>/docs/roadmap.md` with phase definitions that **drive** the next step's cost calculation. **Cost↔roadmap ordering — roadmap dispatches BEFORE cost so cost calculates per-phase from real phase boundaries instead of inventing implicit ones.**
7. **Steps 11 + 12 — parallel fan-out** — dispatch TWO sub-agents in ONE MESSAGE per § Step 11 (cost) + § Step 12 (gtm-launch) briefs. Step 11 reads Step 10 roadmap (for phase boundaries) + Step 09 legal (for review budget) + Step 08 system-design (for integration line items). Step 12 reads Step 10 (for launch timing) + Step 09 (for compliance signals).
8. **Update `.state.json`, then run the quality judge** — record completed/blocked steps; then run the **quality judge** over Steps 05-12 per § Quality judge.
9. **Build the HTML report** — run `build-report.ts` as in Phase 1 step 5; regenerates `<out>/docs/REPORT.html`. Best-effort, never blocks.
10. **Gate — `gate_specification`** — `AskUserQuestion` (same 3-option shape). Point the user at `<out>/docs/REPORT.html` to review before choosing. Per § Quality judge, a `fail` among the Step 05-12 `quality_verdicts` pre-sets the recommended option to `iterate`.

## Phase 3 — Identity (pipeline steps 13-14) — 🔓 Medium freedom: brand/design content adapts to product domain

Strictly serial — design system depends on brand.

1. **Step 13 — Brand book.** Dispatch per § Step 13 brief. Returns `<out>/docs/brand-book.md`. If `--skip-brand`: skip dispatch, `cp templates/default-tokens.css <out>/docs/design-system/tokens.css` + write minimal `<out>/docs/brand-book.md` with neutral tone. **Brand moves to Phase 3 per Decision 3 (PRD-first ordering)** — brand-book now consumes a finalized PRD + sitemap + system-design, NOT a half-formed concept brief.
2. **Step 14 — Design system.** Dispatch per § Step 14 brief. Reads brand-book + audit findings (Step 04) + sitemap inventory (Step 07). Returns 3 files: `docs/design-system/tokens.css`, `docs/design-system/components.md`, `docs/design-system/README.md`.
3. **Update `.state.json`, then run the quality judge** — record completed/blocked steps; then run the **quality judge** over Steps 13-14 per § Quality judge.
4. **Build the HTML report** — run `build-report.ts` as in Phase 1 step 5; regenerates `<out>/docs/REPORT.html`. Best-effort, never blocks.
5. **Gate — `gate_identity`** — `AskUserQuestion`. Point the user at `<out>/docs/REPORT.html` to review before choosing. Per § Quality judge, a `fail` among the Step 13-14 `quality_verdicts` pre-sets the recommended option to `iterate`.

## Phase 4 — Visual contract (pipeline step 15) — 🔓 Medium freedom: screen atlas size adapts to sitemap scope

NO GATE — Phase 4 closes the visual-contract phase; Phase 5 (the mandatory SDD handoff) is the pipeline's terminal step.

The v2/v3 per-route screen-writer fan-out is **deleted**. `/product` writes NO `app/` tree, NO `page.tsx` / `layout.tsx`, runs NO `pnpm install` / build verification / dev-server smoke-test. The runnable app is built by the SDD children scaffolded in Phase 5. Step 15 dispatches the three sub-agents in **two waves**: wave A = 15a + 15c **in one message** (parallel — distinct output paths, no shared inputs); wave B = 15b after 15c returns (the Mood-screen-writer brief in hi-fi mode reads `fixture-spec.md`, so 15b CANNOT share a message with 15c). Then run a best-effort visual check, then authors REPORT.md.

1. **Wave A — dispatch Step 15a + Step 15c in one message** (two parallel `Agent` calls per `references/delegation-briefs.md § Phase 4`):
   - **Step 15a — Screen atlas** — per § Step 15a brief. Returns `<out>/docs/screen-atlas.md` — the navigable visual-contract document indexing every sitemap route, PRD coverage, states coverage, the killer-flow walkthrough. **No `app/` writes, no layout files.**
   - **Step 15c — Fixture spec** — per § Step 15c brief. Returns `<out>/docs/fixture-spec.md` — one persona, one coherent entity set, internally consistent dates.

   **Wave B — after Step 15c returns, dispatch Step 15b:**
   - **Step 15b — Hi-fi killer-flow mood** — dispatch the § Mood-screen-writer brief in **hi-fi mode** (`{{mood_tier}}=hi-fi`), once per killer-flow screen. The screens are the same 3-5 the Step 02 lo-fi mood covered — read them from `<out>/docs/screens/` + Step 02's REPORT § Turn 2 Plan. The hi-fi brief reads `fixture-spec.md` for on-brand data, which is why 15b runs after 15c (not parallel with it). Cap 5 concurrent across the killer-flow screens themselves. Returns `<out>/docs/screens/hifi/<NN>-<name>.html` × 3-5 — brand+tokens-applied, mobile-first static HTML.
2. **Update `.state.json`, then run the quality judge** — append `15-screen-atlas` to `completed_steps`; record any BLOCKED to `blocked_steps` (per `delegation-briefs.md § Failure handling`: 15a BLOCKED → ABORT the run; 15b / 15c BLOCKED → degrade gracefully, Phase 5 still runs). Then run the **quality judge** over the three judge-units `15a-screen-atlas` / `15b-hifi-mood` / `15c-fixture-spec` per § Quality judge. Phase 4 has no gate — a `fail` surfaces in `REPORT.md § Quality concerns` + the Phase 5 handoff message, not a gate `iterate`.
3. **Best-effort visual check.** If the Playwright MCP is loaded this session (`mcp__playwright__*` tools available): the Playwright MCP refuses local-file URLs, so serve `<out>/docs/screens/hifi/` over a localhost HTTP server first. Background-launch the helper script and read the `READY <port>` line it prints on stdout:

   ```bash
   bash .claude/skills/product/scripts/serve-hifi.sh <out>/docs/screens/hifi/ &
   SERVE_PID=$!
   # block until first stdout line — `READY <port>` on success, non-zero exit on failure
   read -r READY_LINE
   ```

   Two outcomes:
   - **`READY <port>`** — for each `<out>/docs/screens/hifi/<NN>-<name>.html`, `browser_navigate` to `http://127.0.0.1:<port>/<NN>-<name>.html`, `browser_resize` to 375×812 then 1280×800, `browser_take_screenshot` at each width, and run a horizontal-overflow probe via `browser_evaluate` — `document.documentElement.scrollWidth > document.documentElement.clientWidth`. Record pass/fail per screen for REPORT.md § Visual check. After the loop, `kill $SERVE_PID` to release the port (the script's signal trap reaps the child `python3 -m http.server`).
   - **Non-zero exit + `not-available: <reason>` on stderr** — `python3` missing, port-bind failed, or server didn't bind within 5s. Fold into the existing skip advisory: `visual-gate-skipped: serve-hifi.sh — <reason>` and record in REPORT.md.

   If the Playwright MCP is NOT loaded at all, emit `visual-gate-skipped: Playwright MCP not loaded — <out>/.mcp.json seeded for the next session` and record the skip in REPORT.md. **Best-effort — never blocks, never aborts.**
4. **Author `<out>/docs/REPORT.md` inline.** Read `templates/report.md.tmpl`, substitute placeholders from `<out>/docs/.state.json` + the phase outputs. Fill the `## Quality concerns` section from `.state.json` `quality_verdicts` — every `concern`/`fail` criterion with its `note`, plus each judge-unit's `scope_assessment` (per `quality-judge.md § Verdict → gate routing`). See `quality-judge.md` + `quality-checklist.md` for the rubric.

## Phase 5 — Mandatory SDD handoff — 🔒 Low freedom: umbrella matrix template + foundation child scaffold

`/product` does not end at a chat message — it scaffolds the engineering entry point. **Read `references/sdd-handoff.md` before executing this phase** — it is the full contract for what to write and how to fill it from the pipeline artifacts.

1. **Scaffold the umbrella spec** at `<out>/docs/specs/001-<slug>/` — copy the four `.claude/skills/sdd/templates/*.tmpl` files, substitute `{{NNN}}=001` / `{{SLUG}}=<slug>` / `{{DATE}}`, then FILL `spec.md` per `sdd-handoff.md § The umbrella spec` and § What Phase 5 produces. **Read `docs/system-design.md` (especially § Stack, § Services, § Trade-off Triggers / Open Decisions) + `docs/roadmap.md` Fase 1 `| Deliverable | Owner | Status |` rows before computing the matrix.** Emit infra children for Fase 1 deliverables that don't map to any per-phase visual child — block-precede numbering (children #3..M are infra, then per-phase visual children #(M+1)..N). Every Fase 1 row maps to a child OR appears in umbrella OQs as `**Deferral reason:**` — no Fase 1 deliverable is silently orphaned. Copy every row from `docs/system-design.md § Trade-off Triggers → Open Decisions` into the umbrella `## Open questions` prefixed `**Architecture — <topic>:**` (see `sdd-handoff.md § Open questions migration` for the shape). Header is `**Type:** umbrella`; fill `## Standing constraints` per `sdd-handoff.md § Standing constraints` (stack-conditional styling / no inline `style` for layout / mobile-first / fixture coherence / Playwright visual verification). `plan.md` / `tasks.md` / `notes.md` stay as template scaffolds — the matrix in `spec.md` is the umbrella's tracking surface.
2. **Scaffold the foundation child** at `<out>/docs/specs/002-foundation/` — copy the four templates, substitute `{{NNN}}=002` / `{{SLUG}}=foundation` / `{{DATE}}`, then FILL `spec.md` per the rewritten `sdd-handoff.md § Child #1` (research-driven). The foundation child's `spec.md § Context` mandates research at `/sdd plan` time per `.agent0/context/rules/research-before-proposing.md` — no Agent0 template is consumed. § Acceptance is stack-neutral (dev server starts clean, typecheck/lint exit 0, token utility resolves). `plan.md` / `tasks.md` / `notes.md` stay as scaffolds — the founder runs `/sdd plan` then `/sdd tasks` on this child.
3. **Children #2..N are matrix rows only** — listed in the umbrella's child-spec matrix, NOT pre-scaffolded. Child #2 (component-library) names `docs/design-system/components.md` as its input spec. Children #3..M (when present) are infra, derived from `docs/roadmap.md` Fase 1 unmatched deliverables; children #(M+1)..N are per-phase visual children sliced by `docs/roadmap.md` phases. If `docs/roadmap.md` has no usable phase structure, fall back to a single `app-build` child per `sdd-handoff.md § Fallback`.
4. **Finalize `<out>/docs/.state.json`** — set `phase="sdd-handoff"`, `completed_at=<ISO timestamp>`.
5. **Build the terminal HTML report** — run `bun .claude/skills/product/scripts/build-report.ts --out=<out> --slug=<slug> --stack=<stack>`. This is the final regeneration — `<out>/docs/REPORT.html` now covers the full 15-step pipeline plus the SDD-handoff specs. Best-effort: a `bun`/script failure emits a one-line `report-html-skipped: <reason>` advisory and does not abort the run.
6. **Print the handoff message:**

```
Product foundation ready at <out>/.

  Pipeline coverage: 15/15 steps completed (or N/15 if any BLOCKED — see docs/REPORT.md § Blocked steps).
  Report:        <out>/docs/REPORT.md
  Report (HTML): <out>/docs/REPORT.html          <-- navigable reading surface (open in a browser)
  Concept brief: <out>/docs/concept-brief.md
  PRD:           <out>/docs/prd/v1.md
  Sitemap:       <out>/docs/sitemap.yaml
  Screen atlas:  <out>/docs/screen-atlas.md      <-- the visual contract
  Hi-fi mood:    <out>/docs/screens/hifi/        <-- 3-5 rendered killer-flow screens
  Fixture spec:  <out>/docs/fixture-spec.md
  Full pipeline artifacts: <out>/docs/

  Phase wall-clock: <total elapsed from started_at to completed_at>
  Gate iterations: discovery=<n> specification=<n> identity=<n>
  Quality concerns: <count of concern+fail criteria across all quality_verdicts> (see docs/REPORT.md § Quality concerns)

  ENGINEERING HANDOFF — the app build runs as SDD specs (no runnable app was generated):
    Umbrella:         <out>/docs/specs/001-<slug>/spec.md      (Type: umbrella — tracks the whole v1 build)
    Infra children:   <out>/docs/specs/003-* … 00N-*           (N infra children — backbone first, per the umbrella matrix)   <-- conditional: only when infra children exist; omit entirely for simple-visual case
    Start here:       <out>/docs/specs/002-foundation/         (child #1 — research-driven; /sdd plan researches the stack declared in docs/system-design.md § Stack)

  Next: work the foundation child (/sdd plan -> /sdd tasks -> implement),
  then materialize each umbrella child-matrix row via /sdd new <phase-slug>.
```

## Worked example — parallel dispatch in a single message

True parallelism (no FS race) happens when sub-agents have **no shared input AND distinct output paths**: Phase 2 Step 06+07 (both read Step 05 PRD only), Phase 2 Step 11+12 (both read Step 09 legal + Step 10 roadmap), and **Phase 4 wave A — Step 15a + Step 15c** (atlas / fixture-spec — no shared input, distinct output paths). Steps with strict serial dependencies (05 → 06+07 → 08 → 09 → 10 → 11+12) must NOT be dispatched together — they'd race the FS.

**Anti-parallelism — sub-agents whose CONTEXT names another's DELIVERABLE**:
- **Step 03 → Step 04**: Step 04's brief CONTEXT explicitly reads `functional-spec.md` (Step 03's deliverable). Dispatch Step 03 alone first; after it returns, dispatch Step 04 alone.
- **Step 15c → Step 15b**: the Mood-screen-writer brief in hi-fi mode CONTEXT explicitly reads `fixture-spec.md` (Step 15c's deliverable). Dispatch Step 15a + Step 15c in one message (wave A — safe); after Step 15c returns, dispatch Step 15b (wave B — serial).

Example (Phase 4 wave A — 2 parallel calls for Step 15a + 15c):

```
[single assistant message with two <tool_use> blocks]:
  <tool_use name="Agent" id="A1">
    subagent_type: general-purpose
    model: sonnet
    description: Step 15a — screen-atlas
    prompt: <TASK + CONTEXT + CONSTRAINTS + DELIVERABLE + DONE_WHEN per delegation-briefs.md § Step 15a>
  </tool_use>
  <tool_use name="Agent" id="A2">
    subagent_type: general-purpose
    model: sonnet
    description: Step 15c — fixture-spec
    prompt: <... per § Step 15c>
  </tool_use>
```

Then in a SECOND message (after A2 returns), wave B dispatches the killer-flow fan-out:

```
[single assistant message with up to 5 <tool_use> blocks — one per killer-flow screen]:
  <tool_use name="Agent" id="B1..B5">
    description: Step 15b — hi-fi mood screen <NN> (one call per killer-flow screen, cap 5)
    prompt: <... per § Mood-screen-writer, {{mood_tier}}=hi-fi — reads fixture-spec.md from A2>
  </tool_use>
```

Dispatching serially when safe to parallelize (one Agent call per message for sub-agents with no shared input) is a v1 orchestration bug. Wall-time penalty alone (~3× for a quad) makes parallel-where-safe critical.

**Anti-pattern**: do NOT dispatch Step 02 + Step 03 + Step 04 in one message. Step 03 and Step 04 CONTEXT both reference `<out>/docs/direction-a.html` + `<out>/docs/screens/` — those files don't exist when Step 02 hasn't returned. The de-facto-correct dispatch is Step 02 alone first, then Step 03 alone, then Step 04 alone (Step 04 reads Step 03's `functional-spec.md`).

## Unknown / extra subcommand

This skill does not have subcommands beyond the initial invocation. If `$ARGUMENTS` starts with an unrecognized token (not a quoted idea and not a flag), refuse with the usage hint:

```
/product "<idea>" --out=<path> [--stack=<name>] [--from-step=NN] [--skip-prd] [--skip-brand]
```

## Eval Scenarios

### Eval 1: Happy path — full multi-phase product

**Input:** User says `/product "ERP para salões de beleza Acme Yard" --stack=next --out=/home/user/acme-yard`.

**Expected:** Phase 0 idempotency check — `<out>` empty or harness-only → proceed. Phase 0.5 locale resolved from idea language (pt-BR). Phase 1 dispatches Discovery steps 01-04 in parallel; Phase 2 fans out steps 05-12 (specification) with the quality judge gating each handoff; Phase 3 builds identity (steps 13-14); Phase 4 produces the screen atlas + hi-fi killer-flow mood (5-screen concurrency cap respected); Phase 5 scaffolds the SDD umbrella spec + foundation child child reading system-design.md to compute the stack-aware matrix. Output is a docs-first tree under `<out>` plus an SDD umbrella; NO app code, NO `pnpm install`, NO build verification.

**Failure indicators:** Pipeline ships a runnable app tree (`app/` / `apps/` / `package.json` at root). Mood-screen-writer fan-out exceeds 5 concurrent. Artifact rejected by quality judge but pipeline continues to next phase. `<out>` overwritten despite containing non-harness pre-existing files (idempotency check skipped). Visual contract dispatched before specification phase completes.

### Eval 2: MVP — selective skip flags

**Input:** User says `/product "MVP SaaS for solo entrepreneurs" --out=./mvp-saas --skip-brand`.

**Expected:** Phase 0/0.5 same as Eval 1. Brand step (within Phase 3) skipped with a one-line `--skip-brand active` advisory; downstream steps that would normally read brand artifacts (design-system step 14, atlas step 15) emit explicit warning that they're falling back to neutral defaults. PRD still ships (no `--skip-prd`); roadmap + cost + GTM all reference US-NN from the PRD. Pipeline still concludes with Phase 5 SDD handoff.

**Failure indicators:** Brand step silently skipped without downstream warning. PRD also dropped (user didn't pass `--skip-prd`). Design system step invents a brand from thin air instead of using neutral defaults. Phase 5 umbrella omits the foundation child because brand artifacts are missing.

### Eval 3: Resume mid-pipeline via `--from-step=NN`

**Input:** User says `/product "<idea>" --out=./existing-product --from-step=07` after a prior run aborted mid-pipeline.

**Expected:** Phase 0 idempotency detects non-empty `<out>`; resume-detection logic reads `<out>/docs/REPORT.md` (or equivalent state marker) to confirm steps 01-06 are present and valid. Pipeline restarts AT step 07 (sitemap-IA), reading already-produced step 01-06 artifacts as context. Steps before 07 NOT re-dispatched. Sitemap schema enforcement check from § Notes still applies (any `required_categories` member with 0 routes AND no `deferred_categories` declaration → BLOCK). Quality judge gates resumption verdict.

**Failure indicators:** Phase 0 wipes `<out>` despite valid prior artifacts. Steps before 07 re-dispatched (token waste). Step 07 dispatched without reading step 06 (system-design.md) output. Sitemap schema check skipped on resume path.

## Notes

_Consumer-extension surface — append consumer-local bullets to this section. Sync flags the file as `!! customized` (sha-compare is section-blind), but the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end. See `.agent0/context/rules/harness-sync.md` § Consumer-extension convention._

- **Skill compliance is non-skippable.** Run `bash .claude/skills/skill/scripts/validate.sh .claude/skills/product` before commit; exit 0 required.
- **`/product` ends at the visual contract — it does NOT generate a runnable app.** Phase 4 produces `screen-atlas.md` + the hi-fi killer-flow mood (static HTML) + `fixture-spec.md`; Phase 5 scaffolds the SDD umbrella + foundation child. No `app/` tree, no `pnpm install`, no build verification. The app build is the founder working the scaffolded SDD specs. This is the deliberate fix for the v2/v3 36-route fan-out whose output quality collapsed (2026-05-19/20 dogfood).
- **Concurrency cap 5** for the mood-screen-writer fan-outs (Step 02 lo-fi, Step 15b hi-fi — both 3-5 screens, killer flow only). Proven non-OOM on a 17-route dogfood.
- **Output dir is `--out=<path>`**, NOT hardcoded `/tmp/`.
- **Standalone skill.** Bundled templates at `templates/pipeline/01-ideation/` … `15-screen-atlas/`. `/product` is the canonical delivery of the 15-step pipeline.
- **`--skip-prd` is degenerate.** PRD feeds Steps 06-15 (OST/sitemap/system-design/legal/roadmap/cost/GTM/brand/design-system/atlas all reference US-NN). Skipping produces a partial pipeline with downstream gaps marked in REPORT.md. Not recommended.
- **OD vendor bundled inside the skill.** 150 named `DESIGN.md` design systems at `.claude/skills/product/design-systems/<vendor>/DESIGN.md`, plus 5-school prompts + frames + templates at `.claude/skills/product/vendor/open-design/`, sync engine at `.claude/skills/product/scripts/sync-open-design.ts` (`--check` / `--bump` / `--apply` / `--verify`). _(The `skills/` design-template bundle tree was dropped 2026-06-03 — spec 145 — as pipeline-unread; consumed OD content is `design-systems/` + the catalogue.)_ Apache-2.0 attribution preserved in `vendor/open-design/{LICENSE,NOTICE}`. Lightweight catalogue at `.claude/skills/product/references/od-catalog-index.json` (name + mood + palette + path) — Step 14 design-system brief reads it to pick 1-2 catalog vendors, then `Read`s the chosen `DESIGN.md` path directly. No MCP tool indirection; the skill is self-contained.
- **Artifact size discipline.** Artifact size is NOT a scope/quality signal — scope, completeness, and right-sizing are graded by the **quality judge** (§ Quality judge; `references/quality-judge.md`). The only size mechanisms left: each step's brief inlines the uniform 200 KB **catastrophe cap** (a token-runaway circuit-breaker per `.agent0/context/rules/artifact-budgets.md`), and each `schema.md § Size floor` carries a `min_size` anti-stub floor (the judge's `wc -c` pre-filter enforces it). The retired `× 1.2 / × 1.8` overshoot cascade and the per-step KB budget are gone. Trim-loop and re-emit-at-smaller-scope stay forbidden.
- **Sitemap schema enforcement is mechanical**. Orchestrator parses `<out>/docs/sitemap.yaml` after Step 07 returns; if any `required_categories` member has 0 routes AND no `deferred_categories: [{name, reason}]` declaration, Step 07 is BLOCKED. This is the load-bearing fix for the "atlas under-cover" bug Pass E demonstrated (Steward shipped without auth/admin/error screens silently).
