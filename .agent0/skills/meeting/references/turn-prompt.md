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
- Contribute **one** substantive turn that advances the deliberation — agree/disagree with
  specific prior points, add a new consideration, or sharpen a tradeoff. Be concrete; name
  what you are responding to. Do not summarize the whole meeting (that is the synthesis step).
- Stay on the topic. One turn, not a transcript.
<IF --web> - You MAY use web search to ground any factual claim. If you do, end your turn with a
  `Sources:` block listing the URLs you used. A research-backed turn with no `Sources:` block
  is invalid.
<IF NOT --web> - Do not perform web research this turn; reason from the transcript and your knowledge.

Output ONLY your turn text (it becomes your contribution verbatim). Do not edit any files.
Do not wrap it in code fences. Do not prefix it with your name — the meeting records that.
