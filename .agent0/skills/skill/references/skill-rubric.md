# Skill rubric — freedom annotations + eval scenarios

Two writing conventions every Agent0 SKILL.md with ≥4 step headers should follow. Both are **repo-local conventions**, not agentskills.io spec rules — they live in the body of `SKILL.md` (not frontmatter) and the upstream canonical tool (`skills-ref`) does not enforce them. The `/skill audit` invocation surfaces gaps as non-blocking `skill-rubric-advisory:` lines (mirrors the `tdd-advisory:` / `lint-advisory:` family — see `.agent0/context/rules/delegation.md` § *Advisories*).

The discipline this enforces is the **skill→LLM-executor** sibling of the **parent→sub** discipline in `.agent0/context/rules/delegation.md` § *The 5-field handoff*. The 5-field handoff disciplines what a parent agent communicates to a dispatched sub-agent so the sub-agent doesn't drift; this rubric disciplines what a skill's body communicates to the LLM executing it, so the LLM doesn't drift between "improvise content" and "follow template literally".

## Freedom annotations

Per-step header carries a freedom marker stating the LLM's affordance for that step. Skills are imperative by definition, so there is **no `High freedom` tier** — the highest level offered is "adapt to detected state within these constraints". A step that genuinely has no constraints isn't a step; it's a free-form section and shouldn't carry a marker.

### Marker grammar

Canonical form (emoji + colon-claim):

```markdown
## Step 3: Launch parallel IC agents — 🔓 Medium freedom: agent count adapts to codebase

## Step 4: Compile QUESTIONS.md — 🔒 Low freedom: fixed format
```

Text fallback (for emoji-hostile terminals or grep-heavy workflows):

```markdown
## Step 3: Launch parallel IC agents — Medium freedom: agent count adapts to codebase

## Step 4: Compile QUESTIONS.md — Low freedom: fixed format
```

Both forms are accepted by `check-rubric.sh`. The validator regex matches `🔒` OR `🔓` OR a leading `Low freedom:` / `Medium freedom:` on the step header line OR its immediate next non-blank line.

### Calibration heuristic

Use this table when deciding which marker fits a step:

| Marker | When | Example |
|---|---|---|
| `🔒 Low freedom: exact sequence` | Order of sub-steps is dependent | Read templates → copy → substitute placeholders → report |
| `🔒 Low freedom: exact format` | Output has a schema/regex contract | JSON shape, frontmatter spec, fixed table columns |
| `🔒 Low freedom: follow template` | Output mirrors an existing file verbatim | Scaffold step that `cp`'s a `.tmpl` and substitutes |
| `🔒 Low freedom: exact parsing` | Input must match a grammar | Argument parsing with required tokens |
| `🔒 Low freedom: exact check` | Decision is a regex/path test | Phase detection: file exists → phase 2 else phase 1 |
| `🔓 Medium freedom: adapts to <X>` | Content varies with detected state | Multi-step pipeline content; agent fan-out count |
| `🔓 Medium freedom: implementation adapts to answers` | Branches on user/judge input | Phase 2 fix application driven by user's answer tags |

### Where annotations belong

- Every `^##` header that names a *step* in a pipeline-shaped skill, OR every `^##` header that names a *subcommand* in a dispatcher-shaped skill.
- NOT on frame sections: `## Notes`, `## Gotchas`, `## Cross-references`, `## Reference Files`, `## Eval Scenarios` (the eval section is the rubric itself, not a step).
- NOT on rules files (`.agent0/context/rules/*.md`) — rules are by definition fully binding; freedom annotations would be cargo-culted.

## Eval scenarios

A `## Eval Scenarios` section near the end of `SKILL.md` containing **≥2** scenario blocks. Each scenario carries three components — Input, Expected, Failure indicators — but the body shape is convention, not enforced; the validator checks only for the section header + sub-header count.

### Scenario block shape

Canonical (verbatim from anthill `anthill-codebase-review`):

```markdown
### Eval 1: Happy path — TypeScript/React project after 3 months

**Input:** User says "codebase review" on a Next.js + Prisma project with ~8K LOC, 60% test coverage.

**Expected:** Phase 1 runs. Orient detects: TS, React, Prisma, no infra. Reads PRD (SaaS billing app), roadmap (Stripe integration planned for next sprint). Launches 3 agents (staff-engineer, appsec, qa-engineer — no sre). Produces 15-25 questions. Summary table shown.

**Failure indicators:** Fewer than 10 questions. No domain context in findings. Roadmap items flagged as bugs. 4 agents launched when infra layer is absent. Generic severity without domain calibration.
```

Minimal form (also accepted — body shape is loose):

```markdown
### Eval 1: Happy path
**Happy path:** User says "hire a CTO" → gather requirements → create files → update org chart → passes checklist

### Eval 2: Edge case
**Edge case:** User provides all info upfront → skip interview → generate directly
```

### Recommended count

Three scenarios cover the common testing trinity:

1. **Happy path** — typical invocation, full-scale success.
2. **Minimal / edge case** — the simplest viable invocation; verifies the skill doesn't over-do work when scope is small.
3. **Adversarial / scale** — the largest or weirdest realistic invocation; verifies the skill doesn't fail catastrophically.

Floor of 2 is enforced (validator emits advisory if `## Eval Scenarios` has <2 `### Eval ` sub-headers). The third scenario is recommended but not required.

### Why the body shape is loose

The validator deliberately doesn't parse `Input` / `Expected` / `Failure indicators` inline. The shape is documented here in `skill-rubric.md` and policed by convention, not regex. Same posture as `## Acceptance criteria` in `spec.md` — the rule documents Given/When/Then shape, the validator doesn't grep for `Given:` line prefixes.

This keeps the validator simple (no markdown subtree parser), lets authors adapt the shape when a skill has unusual eval needs (e.g. one scenario is a code snippet, another is a screenshot description), and avoids ossifying around one cosmetic format.

## Step-counting rule

`check-rubric.sh` counts `^## ` headers in the SKILL.md body (everything after the closing `---` of the frontmatter). It **excludes** the following frame-section headers from the count:

- `## Notes`
- `## Gotchas`
- `## Cross-references`
- `## Reference Files`
- `## Eval Scenarios` (the eval section is the rubric itself)
- `## Argument parsing` (operational meta, not a step)
- `## Unknown subcommand` (error handler, not a step)

A skill whose qualifying step count is **<4** is below the rubric threshold and the validator exits silently — sub-threshold skills are exempt regardless of annotation/eval state. The threshold reflects empirical observation: skills with 1-3 substantive sections don't benefit from explicit affordance declaration; the cost outweighs the value.

Skills currently above the threshold in Agent0: `/sdd`, `/product`, `/skill`. Skills below: `/remind`, `/routine`, `/image`, `/brainstorm`.

## Override marker

Mirroring the project's other gates (`# OVERRIDE:` grammar from `.agent0/context/rules/delegation.md`, `.agent0/context/rules/secrets-scan.md`, etc.), an HTML-comment marker anywhere in the SKILL.md body bypasses the entire rubric check:

```markdown
<!-- SKILL-RUBRIC-EXEMPT: <reason ≥10 chars> -->
```

The reason is mandatory and is the audit trail — `skip` / `n/a` / `bypass` are rejected by the ≥10-char floor. Use the override for skills that are above the step threshold but genuinely shouldn't carry the convention (rare):

- A skill that's a pure dispatcher with no per-step affordance variation (every step is mechanically identical)
- A skill in the middle of a multi-day refactor where annotating now would churn against the next edit
- A skill whose body intentionally documents the conventions inline (e.g. this reference itself, were it ever a skill)

The override skips ONLY the rubric check; agentskills.io frontmatter validation in `validate.sh` still applies.

## Why this is repo-local, not agentskills.io spec

The agentskills.io spec (`.claude/skills/skill/references/spec-snapshot.md`) defines frontmatter compliance: required `name` + `description` fields, `compatibility` length cap, `name`-matches-dirname rule, etc. It is intentionally body-agnostic — different runtimes consuming the SKILL.md (Claude Code, future runtimes, agentskills.io marketplace) may have different body expectations.

Freedom annotations and eval scenarios are an **Agent0 writing discipline** that lives one level above the spec. They presume the skill runs in Claude Code (the `🔒` markers are guidance for the LLM reading the skill body) and that the project values rubric-shaped self-checks (the eval scenarios are written for the LLM and human reader, not for any external test runner).

Forks of Agent0 inherit `check-rubric.sh` via `sync-harness.sh` (it's under `.claude/skills/skill/scripts/`, sync-bound). Forks that disagree with the convention can disable the discipline at the call site (the audit subcommand) without touching upstream `validate.sh`.

## Cross-reference

- `.agent0/context/rules/spec-driven.md` § *Acceptance scenarios* — the spec-level sibling of eval scenarios; same Given/When/Then-style discipline applied to spec.md
- `.agent0/context/rules/delegation.md` § *The 5-field handoff* — the parent→sub discipline this rubric extends to the skill→LLM-executor boundary
- `.agent0/context/rules/delegation.md` § *Advisories* — `skill-rubric-advisory:` follows the established `<kind>-advisory:` grammar
- `.claude/skills/skill/scripts/check-rubric.sh` — implementation
- `.claude/skills/skill/SKILL.md` § *Subcommand: audit* — invocation site
- `.claude/skills/skill/references/spec-snapshot.md` — agentskills.io frontmatter spec (orthogonal — frontmatter, not body)
- `.agent0/context/rules/artifact-budgets.md` § *Anti-stub floor* — same anti-stub discipline that motivates "author writes annotations manually; no auto-generation"
- `/home/goat/anthill/.claude/skills/anthill-codebase-review/SKILL.md` — primary reference for both conventions (10 annotations, 3 eval scenarios)
- `docs/specs/087-skill-rubric-freedom-evals/` — origin spec for this discipline
