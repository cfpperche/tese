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

The skill separates two concerns so turn legality is mechanical, not prose-inferred:

- **State** — a machine-readable YAML front-matter header, owned by `.agent0/skills/meeting/scripts/meeting.sh`. Fields: `meeting`, `topic`, `created`, `convener`, `mode`, `roster` (CSV of all participant ids), `rotation` (CSV of model ids in round-robin order, human excluded), `turn_counter`, `next_speaker`, `synthesis` (`pending|written|accepted|rejected`). A fresh runtime reads only this header to learn whose turn is legal.
- **Content** — turn bodies and the synthesis prose, authored by the active runtime and appended to the body. The script never writes content; the runtime never hand-edits the header.

`meeting.sh` subcommands: `init`, `state`, `next`, `check <file> <speaker>`, `advance <file> --speaker <id> [--synthesis <status>]`, `append-turn <file> --speaker <id> --body-file <p> [--sources-file <p>] [--require-sources]`.

## Turn transport & single-writer rule

The active runtime is the **single writer** for every turn:

- **Next speaker is the active runtime** → it authors the turn inline and appends it.
- **Next speaker is a peer model** → the active runtime fills `references/turn-prompt.md`, invokes the peer through `codex-exec` / `claude-exec` **read-only** (the peer returns turn text only and must not edit files), and appends the returned text itself.
- **Next speaker is the human** → the human supplies the text; the active runtime appends it. A human turn increments the counter but does not consume a model's rotation slot.

This keeps write authority single-owner per turn and makes a peer's mid-turn failure auditable (nothing half-written).

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
- **Header is the source of truth.** Never hand-edit `turn_counter` / `next_speaker` / `synthesis`; route through `meeting.sh` so legality stays consistent.
- **Runtime-neutral, not Claude-locked.** The skill is `agentskills-portable`: any runtime can be the active orchestrator. The human gate degrades from `AskUserQuestion` (Claude Code) to a plain-prose question elsewhere — do not bind the core loop to a Claude-only primitive. Adding a third model runtime needs its id in `roster`/`rotation` plus a sibling exec bridge for it.

## Notes

_Consumer-extension surface — append consumer-local bullets here. Sync flags the file as `!! customized` (sha-compare is section-blind); the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end._
