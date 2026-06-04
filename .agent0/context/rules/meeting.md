# Meeting

`/meeting` convenes a **multi-party, multi-model deliberation** — a turn-based conversation between a human (intermittently present), Claude Code, and Codex CLI — to think through a project topic or a still-vague idea. It is the collaborative sibling of the two single-perspective ideation tools.

## When to use vs siblings

| Tool | Shape | Anchor | Output |
|---|---|---|---|
| `/brainstorm` | one agent *diverges* | free topic | ephemeral (gitignored) HTML |
| `/sdd debate` | two agents, strict turns | a *locked* `spec.md` | git-tracked `debate.md` |
| `/meeting` | N participants, intermittent human | free topic | git-tracked `meeting.md` |

Reach for `/meeting` when the value is **cross-model deliberation on an unanchored topic** — e.g. Claude and Codex argue out a vague idea while the human is away, then the human reacts to a synthesis. Use `/brainstorm` for solo divergence; use `/sdd debate` to pressure-test a written spec.

## v1 scope

- **Human-orchestrated only.** The human drives one turn at a time. There is no autonomous LLM-to-LLM looping — that is a deliberately deferred, cost-gated future mode.
- **Two wired model runtimes** (Claude Code + Codex CLI) plus the intermittent human. The format is *designed for* N parties; v1 wires two models.
- **No new persistent infra.** No broker, no daemon, no API key or MCP beyond what `codex-exec` / `claude-exec` already require. Coordination is per-turn, owned by the single active runtime.

## State vs content split

The skill separates two concerns so speaker selection and single-writer authority are mechanical, not prose-inferred:

- **State** — a machine-readable YAML front-matter header, owned by `.agent0/skills/meeting/scripts/meeting.sh`. Fields: `meeting`, `topic`, `created`, `convener`, `mode`, `roster` (CSV of all participant ids), `rotation` (CSV of model ids — the **fallback speaker order**, human excluded; not a round-robin), `turn_counter`, `next_speaker` (the **derived default** speaker — set by a turn's trailing `Next: <id>` directive, not enforced legality), `synthesis` (`pending|written|accepted|rejected`). A fresh runtime reads only this header to learn the default next speaker.
- **Content** — turn bodies and the synthesis prose, authored by the active runtime and appended to the body. The script never writes content; the runtime never hand-edits the header.

`meeting.sh` subcommands: `init`, `state`, `next`, `check <file> <speaker>` (roster-membership only), `resolve-speaker <file> [--speaker <id>]`, `advance <file> --speaker <id> [--next <id>] [--synthesis <status>]`, `append-turn <file> --speaker <id> --body-file <p> [--sources-file <p>] [--require-sources]` (parses a trailing `Next: <id>` marker in the body).

## Turn transport & single-writer rule

The active runtime is the **single writer** for every turn:

- **Next speaker is the active runtime** → it authors the turn inline and appends it.
- **Next speaker is a peer model** → the active runtime fills `references/turn-prompt.md`, invokes the peer through `codex-exec` / `claude-exec` **read-only** (the peer returns turn text only and must not edit files), and appends the returned text itself.
- **Next speaker is the human** → the human supplies the text; the active runtime appends it. A human turn increments the counter; like any turn it may carry a trailing `Next: <id>` directive, and with none it leaves the default speaker unchanged.

This keeps write authority single-owner per turn and makes a peer's mid-turn failure auditable (nothing half-written).

## Addressing & speaker selection

Speaker selection is **context-driven, not round-robin** (spec 140). A turn body MAY end with a single explicit trailing directive — `Next: <roster-id>` — to hand the floor to a specific participant. `meeting.sh` parses **only** that exact shape on the last non-empty line (never natural language; prose `@mentions` or the word "Next" mid-line do not count). A valid marker becomes the new `next_speaker`; an explicit-but-invalid marker (empty, multi-token, or a non-roster id) **fails the append before anything is written**. The directive is left **visible** in the canonical transcript (it is part of the audit trail). A turn with no marker leaves the default unchanged.

`next_speaker` is therefore a **derived, reported default** — not enforced legality. `meeting.sh check` is demoted to **roster-membership only** (is this a known participant?), and `--speaker` directs freely with no "out of order" warning. The default at any moment is computed by `resolve-speaker` with this precedence, every source roster-validated (a stale/non-roster value is skipped, never used as a hidden default):

`--speaker <id>` → trailing `Next:` marker from the last appended turn (already stored in `next_speaker`) → existing `next_speaker` header → first model in `rotation` (fallback order) → convener.

**Boundary with spec 138 (load-bearing).** A deterministic, transcript-addressed default speaker is **in scope** here: the human still triggers exactly one turn, and the selection is mechanical (exact `Next: <id>` match) and visible in the header. **Out of scope** — and still gated behind spec 138's demand test — are the active model *semantically inferring* the "right" next speaker, and any multi-turn auto-chain. Deterministic transcript directive → yes; semantic speaker choice or autonomous looping → no.

## Research-backed turns

Web research is a **per-turn opt-in** (`--web`). A turn taken with `--web` MUST end with a `Sources:` block listing the URLs used; `append-turn --require-sources` fails the append (writing nothing, counter unchanged) if the block is absent. Without `--web`, a turn reasons from the transcript and the runtime's knowledge.

## Graduation to a spec

When a synthesis recommends "spec candidate" and the human accepts, the synthesis becomes **seed context fed into `/sdd refine`'s interview** — it does not bypass the interview nor silently create a finished spec. The `meeting.md` is linked from the resulting spec's `## Context / references`.

## Files & locations

- Skill: `.agent0/skills/meeting/` (`SKILL.md`, `scripts/meeting.sh`, `templates/meeting.md.tmpl`, `references/turn-prompt.md`), discovered via `.claude/skills/meeting` and `.agents/skills/meeting` symlinks.
- Transcripts: **git-tracked** under `.agent0/meetings/<slug>-<ts>/meeting.md` — a meeting is a decision record / audit trail, not throwaway. No auto-commit; commit like any spec artifact.
- Tests: `.agent0/tests/meeting/` (`run-all.sh`).

## Participants are runtimes, not personas

Participants are distinct **model runtimes**, not theatrical role-play identities. An explicit per-turn *contribution brief* ("take a security-review lens this turn") is legitimate task framing; assigning a participant a standing persona is out of scope.

## Gotchas

- **Symmetric identity.** The skill determines its own runtime from execution context (Claude Code → `claude`, Codex CLI → `codex`) to decide per turn whether the next speaker is itself or a peer. A port must not hardcode a runtime literal.
- **One turn per invocation.** `/meeting turn` writes exactly one turn and stops; it must not chain turns autonomously (that is the deferred orchestrator mode).
- **Header is the source of truth.** Never hand-edit `turn_counter` / `next_speaker` / `synthesis`; route through `meeting.sh` so state stays consistent.
- **Runtime-neutral, not Claude-locked.** The skill is `agentskills-portable`: any runtime can be the active orchestrator. The human gate degrades from `AskUserQuestion` (Claude Code) to a plain-prose question elsewhere — do not bind the core loop to a Claude-only primitive. Adding a third model runtime needs its id in `roster`/`rotation` plus a sibling exec bridge for it.

## Autopilot demand test (gate for a future v2 mode)

A future opt-in "bounded loop runner" mode (one runtime drives N round-robin model turns between human checkpoints) is **deliberately not built** until demand is shown — a flag that exists gets used because it exists, which would contaminate the very signal that justifies it. The gate is a rule-of-three demand test.

A **qualifying meeting** is a real v1 meeting where BOTH hold:
1. the human dispatched **≥4 consecutive model turns** without taking a turn or redirecting, AND
2. the human explicitly recorded wanting it to continue **unattended**.

The mechanical half is measured now: `meeting.sh friction <meeting.md>` (and the `model_turns` / `max_consecutive_model_turns` / `current_model_streak` lines in `meeting.sh state`) report the longest run of consecutive model turns with no human turn between them, and flag whether the ≥4 mechanical threshold is met. **Three qualifying meetings** reopen planning on the autopilot build. Until then, only this measurement ships.

## De-biased deliberation (decision-grade tier — spec 149)

To make "the agents converged" a trustworthy signal (the prerequisite for the planned `/squad`), decision-grade deliberation — `/sdd debate` and any `/meeting` whose synthesis will gate implementation — runs a structural anti-confirmation-bias protocol. **Structural, not persona** (no "be the skeptic" — consistent with `[[feedback_no_persona_role_prompting]]`). `meeting.sh` owns the mechanics; `/meeting` and `/sdd debate` both call them. Exploratory meetings stay on the **light** tier (no blind phase / ledger) — set the tier at `init` (`--tier light|decision-grade`; default `light`).

1. **Blind commit/reveal opening** — `meeting.sh commit --speaker <id> --text-file <opening>` seals each agent's independent opening (gitignored under `.agent0/.runtime-state/deliberation/`, never written to the transcript) and records a `sha256` commitment row. `meeting.sh reveal` publishes the openings **only after every model speaker has committed** (it refuses otherwise) and verifies each hash (tamper-evidence). This removes the turn-1 anchoring of the old "initiator writes position first, reviewer reads it" flow. Blindness is procedural + tamper-evident, not cryptographic against an adversarial peer.
2. **Judgment-surface anonymization** — `meeting.sh ab-map` emits a randomized `Proposal A/B ↔ runtime` mapping for the critique view; the durable transcript stays attributed (audit preserved).
3. **Claim/evidence convergence gate** — `meeting.sh ledger-add --claim … --tag supported|contradicted|unresolved|assertion-only --anchor …` then `ledger-check`: a convergence point with only `assertion-only` claims is **UNRESOLVED regardless of agreement** (exit 1). `meeting.sh check-anchors` deterministically verifies cheap anchors (`path:<p>` exists; `test:<id>` present in the test tree) — v1 does not re-run tests.
4. **Synthesis = rubric over the ledger + minority report** — the synthesizer scores against the ledger (not free-form prose) and preserves any residual objection verbatim as a "fragile-convergence" signal.
- Turn schema (in `references/turn-prompt.md`): counterfactual-candidate-coverage (best alternative + evidence that would flip it + strongest objection to your own path) and confidence-as-routing (never as evidence). Heterogeneous models (Claude↔Codex) are required; single-model deliberation is bias-prone.

## Notes

_Consumer-extension surface — append consumer-local bullets here. Sync flags the file as `!! customized` (sha-compare is section-blind); the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end._
