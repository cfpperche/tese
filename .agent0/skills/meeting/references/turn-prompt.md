# Turn-prompt template (peer participant via exec bridge)

When the next speaker is a **peer runtime** (not the active orchestrating runtime),
the active runtime fills this template and passes it to the peer through the
`codex-exec` / `claude-exec` bridge (read-only sandbox by default — the peer
must NOT edit files; it returns turn text only, which the active runtime appends).

Substitute the `<…>` slots, write to a temp file, and invoke the bridge with
`--task-file`. Capture the bridge's `last-message.md` as the turn body.

---

You are **<PEER RUNTIME>** taking one turn in a multi-party deliberation ("a meeting").

Meeting topic: **<TOPIC>**

Your participant id: `<PEER ID>`. Other participants: <ROSTER>.

Transcript so far (chronological; most recent last):

<TRANSCRIPT BODY — the `## Transcript` section of meeting.md, or a tail of it if long>

Your job this turn:
- Contribute **one** turn that advances the deliberation — agree/disagree with specific prior
  points, add a new consideration, sharpen a tradeoff, **answer a question put to you, or
  deliver a report you were asked for**. Be concrete; name what you are responding to. A turn
  may be short (a focused question, an answer, a brief reaction) — it does not have to be an
  essay. Do not summarize the whole meeting (that is the synthesis step).
- Stay on the topic. One turn, not a transcript.
- **Addressing (optional):** if you want a specific participant to speak next, end your turn
  with a single final line `Next: <id>` using an exact participant id from the roster
  (e.g. `Next: codex`). This hands them the floor as the default next speaker. Omit it if you
  have no preference. Write the id literally — `@mentions` or names in prose do not count.
<IF --web> - You MAY use web search to ground any factual claim. If you do, end your turn with a
  `Sources:` block listing the URLs you used. A research-backed turn with no `Sources:` block
  is invalid. (If you also use a `Next:` directive, put it on the very last line, after Sources.)
<IF NOT --web> - Do not perform web research this turn; reason from the transcript and your knowledge.

Anti-confirmation-bias discipline (decision-grade tier — spec 149; structural, not a persona):
- **Blind opening (round 1).** If you are asked for your *opening*, write it from your own
  independent analysis. Do NOT read or reference any peer opening — they are committed-but-sealed
  and will be revealed only after you commit yours. Anchoring on a peer's opening defeats the point.
- **Judge by content, not author.** When prior contributions are presented to you as
  `Proposal A` / `Proposal B` (anonymized, randomized order), critique the *content* — do not try
  to deanonymize or defer to a perceived-stronger model.
- **Counterfactual coverage (required when you take a position).** Name the strongest *alternative*
  to your preferred path, state what evidence would make that alternative win, and give the
  strongest objection to your own position. Do not perform generic agreement.
- **Confidence is routing, not evidence.** You may mark your confidence, but high confidence is
  never itself an argument; if you agree with a peer, say what *external* evidence (a citation, a
  passing test, a repro, a file you read) backs it — bare agreement is "assertion-only" and does
  not resolve a point.

Output ONLY your turn text (it becomes your contribution verbatim). Do not edit any files.
Do not wrap it in code fences. Do not prefix it with your name — the meeting records that.
