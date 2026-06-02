# Delegation

Sub-agent dispatches via the `Agent` tool are gated. Two cooperating hooks enforce the discipline so under-specified briefs and unverified "done" claims surface immediately instead of after the fact:

- **`PreToolUse(Agent)`** → `.agent0/hooks/delegation-gate.sh` validates a 5-field handoff, honours an `# OVERRIDE:` marker, appends an audit line, and may attach a complexity advisory.
- **`SubagentStop`** → `.agent0/hooks/delegation-verify.sh` runs the project validator once when a *delegated* sub-agent closes, keyed by `agent_id`. Parent (main-thread) stops are exempt by design. Runtime-neutral (Claude + Codex). Replaced the per-edit `post-edit-validate.sh` in spec 111.

## The 5-field handoff

Every `Agent` prompt must include four required fields and one of two outcome fields. Field names are case-insensitive; order is free; any text after the colon counts. Missing fields → `exit 2` with the canonical template printed to stderr below.

- **TASK** — one sentence stating what the sub-agent is to do. No background, no rationale; the verb and object.
- **CONTEXT** — files, paths, links, prior decisions the sub-agent should read first. This is what keeps the sub-agent from inventing its own framing.
- **CONSTRAINTS** — what NOT to do; budgets (time, file count); style; scope guardrails; "do not modify X". The negative space matters as much as the task.
- **DELIVERABLE** — concrete artifact the sub-agent produces (file path, PR, summary shape). Use this when there is a thing.
- **DONE_WHEN** — verifiable condition (tests pass, file exists, command succeeds). Use this when there is a state. Either DELIVERABLE or DONE_WHEN satisfies the outcome slot — both are accepted, neither is required alongside the other.

Canonical template (verbatim from `delegation-gate.sh` stderr):

```
  TASK: <one sentence — what to do>
  CONTEXT: <files/paths/links the sub-agent should read first>
  CONSTRAINTS: <what NOT to do; budgets; style; scope guardrails>
  DELIVERABLE: <concrete artifact — file path, PR, summary shape>
  DONE_WHEN: <verifiable condition — tests pass, file exists, etc.>
```

**Spec-scoped delegations and `notes.md`** — when `CONTEXT` references a spec dir (`docs/specs/NNN-*`), `DELIVERABLE` SHOULD include the phrase "append any in-flight decisions/deviations/tradeoffs/open-questions to `docs/specs/NNN-*/notes.md`" (verbatim or equivalent). This gives the sub-agent a sanctioned surface for judgment calls that weren't pre-empted by spec/plan — the parent reviews the appended entries rather than reverse-engineering decisions from the diff. Author each entry as the dispatched `subagent_type`. Rule-only in v1 (no gate enforcement); see `.agent0/context/rules/spec-driven.md` § *The four artifacts* for the artifact's purpose and entry shape.

**Budgeted artifacts and the overshoot cascade** — when a brief declares a size target for the artifact the sub-agent produces, CONSTRAINTS MUST inline the two-threshold cascade per `.agent0/context/rules/artifact-budgets.md`: `target_max × 1.2 → partial-result with oversize_reason` (soft, sub-agent has agency); `target_max × 1.8 → STOP, emit partial-result, no further production` (hard, no agency). Trim-loop and re-emit-at-smaller-scope are forbidden in every zone above 1.0× — both are "redo to fit budget" antipatterns that hide the scope-mismatch signal. Override marker reuses the project's grammar with `budget-exempt:` prefix (mirrors `tdd-exempt:` here). Rule-only in v1.

## Codex: convention-only

The 5-field handoff is **enforced by a blocking hook on Claude** (`delegation-gate.sh` at `PreToolUse(Agent)`, exit 2 → re-prompt). On **Codex it is convention-only** — there is no enforcement hook, because no Codex hook surface can block a subagent spawn. This was verified against the official Codex hooks docs (2026-05-28): `SubagentStart` is observational (`continue:false` "doesn't stop the subagent from starting"); `PreToolUse` never fires on a spawn (spawn is not a tool call); `PermissionRequest` does not fire on spawn and is an approval allow/deny, not a field validator. See `.agent0/memory/codex-cli-hooks.md` § Subagent dispatch surface.

So on Codex the discipline binds the **orchestrator**, not a gate: when composing a subagent dispatch (`/agent`, "spawn N agents"), the orchestrator self-applies `TASK / CONTEXT / CONSTRAINTS / DELIVERABLE-or-DONE_WHEN` in the natural-language instruction **because this rule says so**. The `.agent0/hooks/delegation-start-audit.sh` hook records that a dispatch happened (`event: "subagent-start"`) but, because the Codex `SubagentStart` payload carries no brief text, it cannot check compliance — it logs `brief_observable: false` / `formatted: null` and asserts nothing about the contract.

This is the exact precedent of `.agent0/context/rules/user-prompt-framing.md`: when the actor being disciplined is the one composing the next message and there is no pre-submit blocker, Agent0 uses a **rule-only self-discipline layer** rather than pretending a post-hoc advisory is enforcement. The audit hook is observability; the rule is the discipline.

## Why DONE_WHEN exists (the /goal connection)

DONE_WHEN is the local materialization of the same primitive that Codex CLI and Claude Code (v2.1.139+, May 2026) ship as `/goal` — a done-state declared up front so the agent works toward a contract instead of a sequence of prompts. The frame is **contract, not promise**: a goal statement without a verifier is just a fancier prompt.

The verifier in this project is `.agent0/hooks/delegation-verify.sh` (at `SubagentStop`), which runs the project validator and emits its real exit code. A sub-agent's self-report — "tests pass", "build succeeded" — is never the final signal. The validator running the actual command and emitting the real exit code is. Same discipline `/goal` enforces upstream via its evaluator model; here it runs through hooks instead of a separate judge, but the contract semantics are the same — and they compose. A parent that submits `/goal` to itself can still dispatch `Agent` calls during the loop, and each of those still passes through the 5-field handoff and the stop-time delegated-task verifier (`delegation-verify.sh`). The two primitives layer rather than compete.

## Override marker

Same shape as the governance gate: a line `# OVERRIDE: <reason ≥10 chars>`, case-sensitive, terminated by end-of-line. The reason is the audit trail — write something a future maintainer can grep for. "skip", "bypass", "n/a" are not reasons. A reason shorter than 10 chars after trimming is rejected and the gate blocks as if no marker were present (with a hint that the reason is too short).

The marker skips ONLY the 5-field validation. It does NOT skip the audit append (the marker reason is recorded in the `override` field) and does NOT skip the escalation-advisory pass. There is no silent bypass.

## Post-edit validator loop

_(Stop-time since spec 111 — the section name is retained as the stable cross-reference anchor; the trigger is now `SubagentStop`, not per-edit.)_

When a delegated sub-agent reaches `SubagentStop`, `.agent0/hooks/delegation-verify.sh` runs the project validator (`.agent0/validators/run.sh` by default, auto-detecting bun / pnpm / npm / python / go / rust / Laravel) **once**, keyed by the documented `agent_id`. The validator emits a JSON object with an `ok` field. This is the DONE_WHEN enforcement point — the delegated task's *close*, not every edit.

Spec 111 replaced the former per-edit `post-edit-validate.sh` with this stop-time hook for two reasons: (1) Codex `PostToolUse(apply_patch)` carries no parent-vs-subagent discriminator, so per-edit delegated-edit attribution is not portable — `SubagentStop` carries `agent_id` on both runtimes; (2) the full suite no longer runs on every edit (expensive, cascade-prone) — it runs once, at close.

Decision (exit codes):

- **Pass** (`ok=true`) → exit 0; the per-`agent_id` failure counter is reset; the validator's advisory family (`lint-advisory:` / `typecheck-advisory:` / `tdd-advisory:`) is surfaced.
- **Fail, first stop** (`ok=false`, `stop_hook_active` false) → exit 2: closure is blocked and the sub-agent gets **one focused continuation** to fix the failing checks; the validator tail is surfaced.
- **Fail, after a continuation** (`ok=false`, `stop_hook_active` true) → exit 0: the closure is accepted as a **partial result** rather than blocking again. `stop_hook_active` is the loop guard (Claude's native stop-loop-prevention signal, present on `SubagentStop`), so the escalation is robust even if `agent_id` does not persist across the continuation.

Counters live at `.agent0/.delegation-state/agents/<agent_id>/consecutive_failures`. `delegation-verify.sh` is the **writer**; `.agent0/hooks/delegation-stop.sh` **reads** the same counter for the close row's `exit` field (`>= CLAUDE_DELEGATION_LOOP_BUDGET`, default 5 → `loop-budget-exceeded`). The two hooks run **in parallel** (Claude runs all matching `SubagentStop` hooks concurrently — no ordering, no short-circuit), so they coordinate through the counter file, never a sentinel. `delegation-stop.sh` is unchanged: it always appends its `subagent-stop` close row; `delegation-verify.sh` writes its own `subagent-verify` rows (`decision: pass | blocked | exhausted`) adjacent, correlated by `agent_id`.

Parent agents do NOT trigger verification (`agent_id` is the delegated-actor gate; it is absent on a main-thread `Stop`). The parent is expected to run tests directly.

Tuning:

- `CLAUDE_DELEGATION_VALIDATOR=/abs/path/to/script` — override the validator path. JSON `{ ok, command, exit, duration_ms, stdout, stderr, warnings }` on stdout.
- `CLAUDE_DELEGATION_LOOP_BUDGET=N` — threshold the close row's `exit` field reads for `loop-budget-exceeded` (default 5). The *escalation to partial-result* fires earlier, on the first continuation, via `stop_hook_active`.

If the validator is missing, non-executable, or emits unparseable output, the hook fails open (exit 0). A broken verifier must never permanently block sub-agent termination.

The validator may append a `warnings` array on stack-detected paths; `delegation-verify.sh` echoes each as a `tdd-advisory:` line on the pass path — non-blocking, surfaced once at close. See `.agent0/context/rules/tdd.md` for the warning shape and response convention.

**Parallel fan-out — the per-edit validator-cascade is gone.** The validator typechecks and lints the **whole project** (`tsc --noEmit`, `biome check`, `go vet ./...` are project-wide). Under the *old* per-edit design, ≥2 sub-agents editing one shared tree concurrently each saw the others' half-written files and flipped `ok` to `false` on errors they did not cause (the **validator-cascade**, observed across Waves 3-5 of a `/product` dogfood, 2026-05-20). Stop-time verification structurally eliminates this: each sub-agent is verified once, at its own close, against its own final tree state — there are no half-written sibling files at a clean close. Worktree isolation (`isolation: "worktree"`) is still recommended for parallel fan-outs that edit overlapping files, but now for **write-collision** reasons (last-writer-wins on shared paths), not validator interference. See § Worktree isolation.

## Audit log

`.agent0/delegation-audit.jsonl` (gitignored, append-only) — the single canonical log for **both** runtimes (hard cutover from the former `.agent0/delegation-audit.jsonl`, removed entirely; no legacy-read). Read with `jq -c .` or `tail -f`. Blocked calls are NOT logged — only allowed dispatches reach the audit phase. Every row carries three discriminator fields: `schema_version` (currently `1`), `runtime` (`"claude-code"` | `"codex-cli"`), and `event` (`"dispatch"` | `"subagent-start"` | `"subagent-stop"`). Three row shapes coexist, keyed by `event` + `runtime`: Claude dispatch rows, Codex `subagent-start` rows, and shared `subagent-stop` close rows.

### Dispatch row (written by `delegation-gate.sh` at PreToolUse(Agent))

Fourteen fields: `ts`, `session_id`, `tool_use_id`, `subagent_type`, `model`, `model_specified`, `isolation`, `formatted`, `override`, `advisory_emitted`, `advisory_kind`, `skill_directed`, `escalation_signals`, `task_summary`. `advisory_kind` is one of `"model-discipline"`, `"escalation"`, or `null` when no advisory fired — the bool `advisory_emitted` answers "did anything fire", the string `advisory_kind` answers "which one". `skill_directed` is the slug extracted from a `# SKILL-DIRECTED: <slug>` marker in the prompt body (string, or `null` when the marker is absent or its slug failed validation) — same string-or-null shape as `override`; see § Advisories for what the marker suppresses. `tool_use_id` is the harness-supplied `toolu_*` identifier and acts as the join key into the close row (see below) — this field is the prerequisite for exact dispatch↔stop correlation under parallel same-type dispatches. `isolation` mirrors the value of `tool_input.isolation` (e.g. `"worktree"` or `""` when unset) — this field provides forensic visibility into worktree-isolation choices; see § Worktree isolation below. As of spec 106 every dispatch row also carries the three discriminators `schema_version` (`1`), `runtime` (`"claude-code"`), and `event` (`"dispatch"`).

### Close row (written by `.agent0/hooks/delegation-stop.sh` at SubagentStop — shared multi-runner)

Shared across both runtimes. Carries the three discriminators (`schema_version`, `runtime`, `event` = `"subagent-stop"`) plus: `ts`, `session_id`, `agent_id`, `tool_use_id`, `agent_type`, `exit`, `duration_ms`, `edit_count`, `last_assistant_message_head`, `agent_transcript_path`, `correlation`, `stop_hook_active`. Denormalised — `agent_type` mirrors the dispatch/start row's type and the 200-char `last_assistant_message_head` is inlined so standalone `jq` queries (`select(.event == "subagent-stop" and .exit == "loop-budget-exceeded")`) work without a join.

The hook branches on `runtime`. The fields split into three tiers:

- **runtime-neutral** (both): `ts`, `runtime`, `session_id`, `agent_id`, `agent_type`, `event`.
- **correlation** (runtime-specific): `correlation` — `"tool_use_id"` (Claude, bridge resolved via the sidecar `.meta.json.toolUseId` lookup), `"heuristic-session-type"` (Claude fallback under missing sidecar), `"agent_id-direct"` (**Codex** — the close row pairs to its `subagent-start` row by matching `agent_id`), `"unmatched"` (no prior dispatch/start row found — applies to both runtimes; on Codex, an `agent_id` with no matching start row stays `unmatched`, surfacing hook-disabled starts / crashes / partial rollouts).
- **best-effort / null** (Claude-rich, Codex-null): `exit` — `"ok"` / `"loop-budget-exceeded"` (the `consecutive_failures` state lives at `.agent0/.delegation-state/`, a Claude-only loop-budget counter; **`null` on Codex** — loop-budget enforcement is deferred there); `edit_count` — counted from the Claude per-sub-agent transcript `tool_use` blocks (`.name ∈ {Edit, Write, MultiEdit}`), **`null` on Codex** (no equivalent transcript edit attribution); `duration_ms` — client-computed (close_ts − start/dispatch_ts), `null` when no prior row is located; `agent_transcript_path` — Claude transcript pointer, may be empty on Codex.

### Bridge mechanism (dispatch ↔ stop)

`PreToolUse(Agent)` payload carries `tool_use_id` (no `agent_id` yet — sub-agent doesn't exist), while `SubagentStop` payload carries `agent_id` (no `tool_use_id`). The two identifiers are disjoint. Bridge: Claude Code writes a per-sub-agent transcript at `<cc-storage>/<session_id>/subagents/agent-<agent_id>.jsonl` with a sidecar `agent-<agent_id>.meta.json` that contains `{ agentType, description, toolUseId }`. The `toolUseId` field matches the dispatch row's `tool_use_id`. The close hook reads the sidecar at SubagentStop time to obtain both identifiers and joins exactly.

**Codex has no sidecar — and needs none.** Codex's `SubagentStart`/`SubagentStop` payloads both carry `agent_id` directly, so the close hook pairs to the `subagent-start` row by matching `agent_id` (correlation `"agent_id-direct"`). Simpler than the Claude bridge, not harder. Codex `SubagentStart` carries **no brief/instruction text** (verified — fields are `session_id`, `turn_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, `permission_mode`, `agent_id`, `agent_type`), so the start-audit row records `brief_observable: false` / `formatted: null` — it observes that a dispatch happened, never whether the 5-field contract was followed (that discipline is convention-only on Codex — see § Codex: convention-only).

### Codex `subagent-start` row (written by `.agent0/hooks/delegation-start-audit.sh` at SubagentStart)

Codex-only (Claude's "start" record is the dispatch row from `delegation-gate.sh`). Non-blocking — `SubagentStart` cannot stop a spawn. Fields: the three discriminators (`schema_version`, `runtime: "codex-cli"`, `event: "subagent-start"`) plus `ts`, `session_id`, `agent_id`, `agent_type`, `brief_observable` (always `false` on current Codex), `formatted` (always `null`). It exists to give the `subagent-stop` close row a correlation/duration anchor, nothing more.

### Example queries

Pair every dispatch with its close row (when present):

```bash
jq -s 'group_by(.tool_use_id) | map({
  tool_use_id: .[0].tool_use_id,
  open: (.[]? | select(.event == "dispatch")),
  close: (.[]? | select(.event == "subagent-stop"))
})' .agent0/delegation-audit.jsonl
```

Find loop-budget exhaustions in the last 24 hours:

```bash
tail -10000 .agent0/delegation-audit.jsonl | jq -c '
  select(.event == "subagent-stop" and .exit == "loop-budget-exceeded")
'
```

Find sub-agents that dispatched but never closed (orphans — session crash or hook failure):

```bash
jq -s '
  group_by(.tool_use_id)
  | map(select(length == 1 and (.[0].event == "dispatch")))
  | .[]
' .agent0/delegation-audit.jsonl
```

## Worktree isolation

Claude Code 2.1.144+ ships native worktree primitives that the `Agent` tool exposes via the `isolation` parameter. When a parent sets `isolation: "worktree"` in the `Agent` tool call, CC's harness handles the rest:

1. The sub-agent's system prompt is auto-augmented with the instruction _"Call `EnterWorktree` as your first action — before reading files or running commands — unless your cwd is already under `.claude/worktrees/`. If `EnterWorktree` fails, continue in place."_
2. The sub-agent invokes the native `EnterWorktree` tool, which creates a temporary git worktree at `.claude/worktrees/<name>/` and changes the sub-agent's cwd into it.
3. All subsequent edits land in the worktree, isolated from the parent's working tree and from sibling sub-agents.
4. On session exit (or explicit `ExitWorktree` call), the user is prompted to keep or remove the worktree.

This is canonical CC behavior — **Agent0 does NOT mediate the mechanism**. There is no `ISOLATION:` brief field, no gate-side mutation of the tool call, no propagation logic. The parent declares isolation by setting `tool_input.isolation` directly in the `Agent` call, and CC takes over.

### What Agent0 adds (discipline ON TOP)

- **Audit** — `delegation-gate.sh` extracts `tool_input.isolation` and records it in the dispatch row as the 13th field (see § Audit log above). Empty string when unset, `"worktree"` when set. Forensic queries can ask "did this dispatch isolate, given the complexity signals it carried?":
  ```bash
  jq -c 'select(.isolation == "" and (.escalation_signals | length) >= 2)' \
    .agent0/delegation-audit.jsonl
  ```
- **Validator scoping** — `delegation-verify.sh` derives the validator's cwd from the sub-agent's `cwd` at `SubagentStop` (a worktree-isolated sub-agent closes inside its worktree), resolving its git toplevel. So the close-time validation runs against the sub-agent's own tree, not stale parent state. Fail-open: `git rev-parse` failure (non-git scratch dir, etc.) falls back to the sub-agent `cwd`, then `$PROJECT_DIR`.

### When parents SHOULD declare `isolation: "worktree"`

- **≥ 2 parallel `Agent` dispatches** that may touch overlapping files (canonical collision case). Without isolation the sub-agents share one working tree and the last writer wins on collisions — silent clobbering of each other's edits. This is a **MUST**, not a suggestion, for any parallel fan-out with overlapping targets. (Note: the per-edit *validator-cascade* that was a second reason here is gone since spec 111 — verification is stop-time, so siblings' half-written files no longer fail each other's checks; see § Post-edit validator loop. Write-collision remains the live reason.)
- **Sub-agent will create new files in unknown locations** — keeps the parent tree clean if the work is exploratory or speculative.
- **Sub-agent will run destructive operations** (`rm -r`, schema migrations, file rewrites at scale) — worktree provides reversibility via discard-on-exit, parent tree remains untouched.
- **Long-running sub-agent on a `--worktree` background session** — already isolated via `bgIsolation: "worktree"` config, no extra action needed.

### When parents should NOT declare isolation

- **Single read-only sub-agent** (Explore, research, listing) — worktree setup adds latency with no benefit.
- **Sub-agent must observe the parent's in-flight tree state** (rare; usually wrong — sub-agents should operate on committed-or-staged state).
- **Trivial single-edit sub-agent** where the parent will review the diff immediately and merge.

### Why no brief field

The original worktree-isolation draft proposed a 6th optional `ISOLATION:` field in the 5-field handoff. Empirical pre-flight (2026-05-19) showed the canonical mechanism is already `tool_input.isolation` set by the parent. Adding a brief field would duplicate intent (once verbally in CONSTRAINTS/DELIVERABLE, once mechanically in tool params) without enforcement value — the gate cannot mutate the tool call payload from the brief. The audit row records the canonical signal; the rule documents the discipline; the validator scoping fix mitigates the cross-cwd risk regardless of declaration.

## Advisories

The gate scores 5 signals against the prompt: `large-fileset`, `multi-integration`, `cross-domain`, `schema-data`, `security`. Two distinct advisories may attach to the call's `additionalContext` — both are informational, the call is always allowed.

**`model-discipline`** — fires when the parent did NOT pass an explicit `model` field AND at least one signal fires. Inlines the task-fit table so the parent can declare a model without re-deriving it: mechanical implementation → `sonnet`; schema/protocol lookup → `haiku`/`sonnet`; multi-source comparative research → `opus` if ≥2 signals (cross-domain + security/schema), else `sonnet`; architecture review or exploratory debugging → `opus`. The advisory exists because an unspecified model means the harness default runs, which may not match the task — declaring a model is the prerequisite for any subsequent escalation discussion.

**`escalation`** — fires when ≥2 signals fire AND the parent specified a non-opus model. Suggests re-issuing with `model: "opus"` for stronger reasoning. Does NOT fire on `model_specified=false` — that branch is already covered by `model-discipline`, which takes priority.

**`# SKILL-DIRECTED: <slug>` marker** — a brief carrying this line (mirrors `# OVERRIDE:` *anchoring*; slug is `[A-Za-z0-9_-]+` ≥3 chars — NOT the ≥10 of `# OVERRIDE:`, whose payload is human prose; SKILL-DIRECTED's payload is a machine slug, and real skill names are short by design: `product`, `sdd`, `run`, `verify`) is self-certifying that the model choice was deliberate (typically a slash-command skill that picked a non-opus model for mechanical pipeline work). The `escalation` advisory is suppressed; `model-discipline` is NOT — the marker doesn't excuse an undeclared model. The dispatch row's `skill_directed` field records the slug for greppable adoption tracking (`jq 'select(.skill_directed)'`). A brief may carry both `# OVERRIDE:` and `# SKILL-DIRECTED:` — they're independent.

Treat either advisory as a nudge to reconsider, not a verdict. The audit log's `advisory_kind` field records which (if any) fired, so post-hoc analysis can distinguish discipline drift (parent kept dispatching without declaring a model) from undercommitment (parent picked a small model for a complex task).

## Gotchas (for hook maintainers)

- **`jq '.field // empty'` collapses `false` and missing into the same empty string.** When reading the validator's `ok`, use `if type=="object" and has("ok") then (.ok|tostring) else "" end` so `false` (real failure) and missing (broken validator → fail open) stay distinguishable.
- **`exec 9>file 2>/dev/null` is a sticky redirect.** A bare `exec` with no command applies the redirections to the current shell — `2>/dev/null` would permanently silence stderr for the rest of the script and eat every block message. Probe writability in a subshell (`( : >>"$path" ) 2>/dev/null || exit 0`) before the bare `exec`.
