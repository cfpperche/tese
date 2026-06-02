---
name: meeting
description: Convene a multi-party, multi-model deliberation — a turn-based conversation between a human (intermittently present), Claude Code, and Codex CLI — to think through a project topic or a vague idea. The collaborative sibling of /brainstorm (one agent diverging) and /sdd debate (two agents reviewing a locked spec). Any participant may take a research-backed turn that cites sources; the human is optional and can simply react to the synthesis. Human-orchestrated - one turn at a time. Subcommands - start "<topic>" [--with <ids>], turn [--speaker <id>] [--web], synthesize, state, list. Git-tracked transcripts live under .agent0/meetings/<slug>-<ts>/meeting.md.
argument-hint: <start "<topic>" [--with <ids>] | turn [--speaker <id>] [--web] | synthesize | state | friction | list>
license: MIT
compatibility: Compatible with any agentskills.io-compatible runtime (Claude Code, Codex CLI, and others). Uses only universal primitives — file IO and shell (the meeting.sh state machine + the codex-exec/claude-exec subprocess bridges). The human gate uses AskUserQuestion in Claude Code and degrades to a plain-prose question in runtimes without it, so any runtime can be the active orchestrator.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.2"
---

# /meeting — multi-party, multi-model deliberation

Convenes a turn-based conversation among a human and two model runtimes (Claude Code, Codex CLI) to deliberate on a project topic or a still-vague idea. Distinct from its two siblings:

- **`/brainstorm`** *diverges* with a single agent; output is ephemeral.
- **`/sdd debate`** is *two-role, spec-locked, strict-turn* review of a filled `spec.md`.
- **`/meeting`** is *N-party, free-topic, intermittent-human* deliberation — Claude and Codex can argue out a vague idea while the human is away, then the human reacts to a synthesis.

v1 is **human-orchestrated**: the human drives one turn at a time. There is no autonomous LLM-to-LLM looping (a future, explicitly-gated mode). Coordination uses no broker or daemon — turn state lives in a machine-readable header managed by `scripts/meeting.sh`, and peer turns are fetched through the existing `codex-exec` / `claude-exec` bridges. The active runtime is the **single writer** for every turn.

## This port's runtime identity

The skill is symlink-shared across runtimes, so this file is byte-identical for every port. **Determine your own runtime from your execution context** — `Claude Code` → participant id `claude`; `Codex CLI` → participant id `codex`. Do NOT read a fixed literal from this file. You use your identity to decide, per turn, whether the next speaker is **you** (author the turn inline) or a **peer** (fetch it through the exec bridge).

## Argument parsing

User invokes as `/meeting <subcommand> [args]`. The raw argument string is `$ARGUMENTS`. Parse it yourself: split on whitespace; the first token is the subcommand (`start` / `turn` / `synthesize` / `state` / `friction` / `list`); the rest are subcommand args (the `start` topic may be a quoted string — strip surrounding quotes). Do not rely on `$1` / `$2` positional substitution.

Raw invocation: `$ARGUMENTS`

The state-machine helper is `.agent0/skills/meeting/scripts/meeting.sh`; the transcript template is `.agent0/skills/meeting/templates/meeting.md.tmpl`; the peer turn-prompt template is `.agent0/skills/meeting/references/turn-prompt.md`.

## Where meetings live

Git-tracked under `.agent0/meetings/<slug>-<ts>/meeting.md` (a meeting is a decision record / audit trail, like a debate — not throwaway like a brainstorm). No auto-commit; the user commits the transcript like any spec artifact. Target selection for `turn` / `synthesize` / `state`: the most recent `.agent0/meetings/*/` dir unless the user names one in conversation.

## Subcommand: `start "<topic>"` — 🔓 Medium freedom

1. **Validate** — empty/unparseable topic → refuse with `usage: /meeting start "<topic>" [--with claude,codex,human]`.
2. **Participants** — parse `--with <ids>` (comma-separated). Default roster: `claude,codex,human`. The **rotation** is the **fallback order** of model speakers (used only when no default is otherwise resolvable) — the roster with `human` removed, preserving order. It is not a round-robin; speaker selection is context-driven (see `turn`). The **convener** is your own runtime id.
3. **Slug + timestamp** — kebab-case slug from the topic (lowercase, non-alphanumeric → `-`, collapse repeats, trim, max 40 chars); ISO-8601 UTC timestamp with `:`→`-` for filename safety.
4. **Scaffold** — build a human-readable participants block (one `- <id> — <runtime> (web: allowed|n/a)` line per roster member), then call:
   ```bash
   bash .agent0/skills/meeting/scripts/meeting.sh init \
     --dir .agent0/meetings/<slug>-<ts> --slug <slug> --topic "<topic>" \
     --convener <your-id> --roster "<roster-csv>" --rotation "<rotation-csv>" \
     --participants-block "<block>"
   ```
   The script writes `meeting.md` with `turn_counter: 0`, `next_speaker` = first in the fallback order, `synthesis: pending`, and echoes the path.
5. **Opening turn** — the convener (you) writes the first turn: a tight framing of the topic and the 1–2 questions the meeting should resolve. Write it to a temp file and append via `append-turn --speaker <your-id> --label "<your runtime>"`. End it with a `Next: <id>` line if you want to hand the floor to a specific peer; otherwise the human directs the next turn with `--speaker`.
6. **Report** — print the meeting path, the participants, and that the next step is `/meeting turn` (naming the current default speaker per `resolve-speaker`).

## Subcommand: `turn` — 🔓 Medium freedom: the v1 core loop

Write exactly one turn.

1. **Resolve target meeting** and read its state: `bash .agent0/skills/meeting/scripts/meeting.sh state <meeting.md>`.
2. **Resolve speaker** (context-driven — there is no round-robin):
   - The default is whatever the last turn's trailing `Next: <id>` directive set (or the persisted default). Resolve it mechanically with `meeting.sh resolve-speaker <file> [--speaker <id>]`, which applies the precedence `--speaker` > `next_speaker` header > first model in `rotation` (fallback order) > convener and roster-validates every source.
   - No `--speaker` → speaker = `resolve-speaker <file>`.
   - `--speaker <id>` → speaker = `resolve-speaker <file> --speaker <id>` (the human directs freely; this is the normal path, **not** an "out of order" exception — do not emit any override/rotation warning). A non-roster `<id>` is refused (exit 3).
3. **Author the turn by speaker type:**
   - **Speaker is YOU** (`<id>` == your runtime id) → author the turn inline. Respond to specific prior points. A turn may be a full contribution **or** a short directed exchange — a focused question, an answer to a question put to you, a requested report, or a brief reaction (it need not be an essay). Don't summarize the whole meeting (that's synthesis). To hand the floor to a specific participant, end the body with a single final line `Next: <roster-id>` (exact id; prose `@mentions` don't count). If `--web`, do your own web research and end with a `Sources:` block (put any `Next:` line last, after Sources). Write the body to a temp file.
   - Optional `--kind question|answer|report|reaction` is a lightweight hint you may record in the turn or use to shape a peer prompt — it is metadata only, never a required taxonomy or a gate on what counts as a valid turn.
   - **Speaker is a PEER model** → read `references/turn-prompt.md`, fill its slots (peer runtime, topic, roster, the `## Transcript` section so far, and the `--web` branch), write to a temp prompt file, and invoke the peer's bridge **read-only** (the peer returns text only; it must not edit files):
     ```bash
     # peer = codex:
     bash .agent0/skills/codex-exec/scripts/codex-exec.sh --sandbox read-only \
       --task-file <prompt> --slug meeting-<slug>-turn-<n>
     # peer = claude (when Codex CLI is the active runtime):
     bash .agent0/skills/claude-exec/scripts/claude-exec.sh --permission-mode default \
       --task-file <prompt> --slug meeting-<slug>-turn-<n>
     ```
     Capture the bridge's `last-message.md` as the turn body.
   - **Speaker is `human`** → ask the human for their contribution (or take the text they already gave inline). Write it to a temp file. A human turn may also end with a `Next: <id>` line to hand the floor; with no directive, the default next speaker is left unchanged.
4. **Append (single writer = you):**
   ```bash
   bash .agent0/skills/meeting/scripts/meeting.sh append-turn <meeting.md> \
     --speaker <id> --label "<runtime label>" --body-file <body> [--require-sources]
   ```
   Pass `--require-sources` whenever the turn was taken with `--web` — the append fails (writing nothing) if the body lacks a `Sources:` block. `append-turn` writes the turn section, advances `turn_counter`, and sets `next_speaker` from the body's trailing `Next: <id>` directive if present (a non-roster directive fails the append before anything is written); with no directive the default is left unchanged.
5. **Report** — print the turn number just written, the resulting default next speaker, and remind the user they can `/meeting turn` again or `/meeting synthesize` when ready. **Stop after one turn** — do not chain turns autonomously.

## Subcommand: `synthesize` — 🔓 Medium freedom + 🔒 human gate

Triggered when the user asks to wrap up ("synthesize", "wrap the meeting"). Either model participant can synthesize — whichever the user asks (default: you).

1. **Read** the full transcript.
2. **Write the `## Synthesis` section** — replace the `_(not yet synthesized)_` placeholder with: the synthesizing runtime; the convergence (what the participants agreed on); recorded disagreements (each: who held what, why unresolved); and a **recommended next step** — either *graduate to a spec* (the deliberation is a spec candidate) or *no-op* (informational only). Edit the file directly for this prose section (the body is yours to author; the header is the script's).
3. **Mark status:** `bash .agent0/skills/meeting/scripts/meeting.sh advance <meeting.md> --synthesis written`.
4. **Human gate (runtime-neutral)** — ask the human: **accept** / **redirect** (more turns) / **end**. Use `AskUserQuestion` when the runtime is Claude Code; in any runtime without it (Codex CLI, etc.), ask the same three options as a plain-prose question and read the human's reply. Do NOT make this step depend on a Claude-only tool — the active orchestrator can be any runtime.
   - **accept** + recommendation was "graduate" → set `--synthesis accepted`, then offer to hand the synthesis to `/sdd refine` **as seed context for its interview** (it does not bypass the interview nor create a finished spec); link this `meeting.md` from the resulting spec's `## Context / references`.
   - **accept** + "no-op" → set `--synthesis accepted`; done.
   - **redirect** → leave status `written`; the user runs more `/meeting turn`s, then re-synthesizes.
   - **end** → set `--synthesis rejected` (ended without adopting the recommendation); record the human's reasoning if given.

## Subcommand: `state` — 🔒 Low freedom

Print the resolved meeting's header via `meeting.sh state <meeting.md>` plus a one-line human summary (`turn N · next: <speaker> · synthesis: <status>`). This is also how a fresh runtime learns the default next speaker without reading the prose body. The state output also carries a derived **autopilot-friction signal** (`model_turns` / `max_consecutive_model_turns` / `current_model_streak`) computed from the transcript.

## Subcommand: `friction` — 🔒 Low freedom

Print the autopilot-friction measurement via `meeting.sh friction <meeting.md>`: the longest run of consecutive model turns with no human turn between them, and whether it meets the ≥4 mechanical threshold of the autopilot demand test (see `.agent0/context/rules/meeting.md` § Autopilot demand test). This is the near-term measurement that lets the rule-of-three gate for a future autopilot mode be evaluated from real meeting artifacts; it does not change the v1 loop.

## Subcommand: `list` — 🔒 Low freedom

Glob `.agent0/meetings/*/meeting.md`. For each, emit one line sorted by created descending: `<slug>  <created>  turn <N>  next:<speaker>  [<synthesis>]  — <topic>`. If none, print `no meetings yet — try /meeting start "<topic>"`.

## Unknown subcommand

If the first token is missing or not one of `start` / `turn` / `synthesize` / `state` / `friction` / `list`, refuse with:

```
/meeting <start "<topic>" [--with <ids>] | turn [--speaker <id>] [--web] | synthesize | state | friction | list>
```

## Eval Scenarios

### Eval 1: Convene a meeting on a free topic

**Input:** `/meeting start "should we cache the API layer"` in a Claude Code session, no prior meeting.

**Expected:** Roster defaults to `claude,codex,human`, rotation `claude,codex`, convener `claude`. `meeting.sh init` writes `.agent0/meetings/should-we-cache-the-api-layer-<ts>/meeting.md` with a filled machine-readable header (turn_counter 0, next_speaker claude, synthesis pending) and a participants block. The convener appends an opening turn framing the topic. Report names the path, participants, and the next speaker.

**Failure indicators:** Header left with `{{…}}` placeholders. No opening turn. Wrote the transcript outside `.agent0/meetings/`. Auto-ran a second turn.

### Eval 2: Peer turn fetched through the bridge, appended by the active runtime

**Input:** `/meeting turn` when `next_speaker` is `codex` and the active runtime is Claude Code.

**Expected:** `turn-prompt.md` filled with the topic + transcript-so-far; `codex-exec.sh --sandbox read-only --task-file …` invoked; the returned `last-message.md` becomes the turn body; the **active Claude runtime** appends it via `append-turn --speaker codex` (the peer never edits the file). `turn_counter` advances; `next_speaker` is set from the returned turn's trailing `Next: <id>` directive if present, else left unchanged. Exactly one turn written.

**Failure indicators:** Granted the peer write access. Chained multiple turns. Appended without advancing the header. Peer asked to edit `meeting.md` directly.

### Eval 3: Research-backed turn requires sources

**Input:** `/meeting turn --speaker codex --web`.

**Expected:** The peer prompt includes the `--web` branch (may search, must end with `Sources:`); `append-turn` is called with `--require-sources`; a body lacking a `Sources:` block fails the append (nothing written, counter unchanged); a body with `Sources:` is appended.

**Failure indicators:** `--require-sources` omitted so an unsourced turn is accepted. Counter advanced on a failed append.

### Eval 4: Synthesis + human gate

**Input:** User says "synthesize the meeting" after several turns where the human was silent.

**Expected:** `## Synthesis` filled (synthesizing runtime, convergence, disagreements, recommended next step); status set to `written`; the human is offered accept / redirect / end through the runtime-neutral gate (`AskUserQuestion` in Claude Code, plain-prose question elsewhere). On accept+graduate, the synthesis is offered to `/sdd refine` as seed context and the meeting is linked from the new spec's references; status `accepted`. On end, status `rejected`.

**Failure indicators:** Auto-applied a graduation without the human gate. Bypassed `/sdd refine`'s interview by writing a finished spec. Left synthesis status `pending`. **Made the gate depend on `AskUserQuestion` so a non-Claude orchestrator can't run it** (the lock-in this skill avoids).

## Notes

_Consumer-extension surface — append consumer-local bullets here. Sync flags the file as `!! customized` (sha-compare is section-blind), but the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end._

- v1 is **human-orchestrated only**. Autonomous LLM-as-orchestrator (one model selecting speakers and driving N turns) is a deliberately deferred, cost-gated future mode — do not auto-loop turns.
- The script owns **state** (the header); the active runtime owns **content** (turn bodies + the synthesis prose). Keep that split — it is what makes speaker selection and single-writer-per-turn mechanical.
- Peers are distinct **model runtimes**, not theatrical personas. An explicit *contribution brief* in a turn ("take a security-review lens this turn") is fine; assigning a participant a standing role-play identity is not.
- **Runtime-neutral by design (`agentskills-portable`).** Any runtime can be the active orchestrator — the body uses only file IO + shell (`meeting.sh`, the exec bridges), and the human gate degrades from `AskUserQuestion` to a plain-prose question. Do not reintroduce a Claude-only primitive in the core loop.
- **Adding a third model runtime** (beyond Claude Code / Codex CLI) needs two things: (1) its participant id in the meeting's `roster`/`rotation`, and (2) an exec bridge for it (sibling to `codex-exec`/`claude-exec`) so the active runtime can fetch its turn. The transcript format and state machine already accommodate N participants.
