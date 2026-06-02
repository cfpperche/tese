---
name: remind
description: Deferred-intent reminder list for this project. Use when the user wants to capture a future to-do that isn't urgent enough to act on now ("circle back on caching when first user complains", "review pricing in Q3", "update README after auth refactor lands"). Subcommands - add "<text>" [--due <YYYY-MM-DD>] [--check '<cmd>'] [--links <a,b,c>], list, done <N-or-id>, dismiss <N-or-id> (alias for done), snooze <N-or-id> <Nd|Nw|Nm|YYYY-MM-DD>, check <N-or-id>. State lives in .agent0/reminders.yaml (git-tracked) and is auto-injected at session start by .agent0/hooks/reminders-readout.sh. See .agent0/context/rules/reminders.md for what belongs here vs MEMORY vs HANDOFF.md.
argument-hint: <add "<text>" [--due <DATE>] [--check '<cmd>'] [--links <a,b,c>] | list | done <N|id> | dismiss <N|id> | snooze <N|id> <Nd|Nw|Nm|DATE> | check <N|id>>
license: MIT
compatibility: Designed for Claude Code. Body references `.claude/` conventional paths and CC-specific tools; portable to any runtime that maps a `.claude/`-analog directory and surfaces the referenced tools. Requires python3 + PyYAML for state mutation; readout hook degrades to yq or raw-YAML when PyYAML is absent.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.2"
---

# /remind — deferred reminders

<!-- SKILL-RUBRIC-EXEMPT: subcommand dispatcher with mechanical per-step structure; rationale recorded in Agent0 design history and revisit only after rule-of-three demand -->

Capture, list, snooze, complete, and probe action-shaped future items that aren't urgent enough to act on now but shouldn't be lost. State lives in `.agent0/reminders.yaml` (git-tracked YAML, one entry per record), auto-injected into context at session start. Not a task manager, not a knowledge base, not a session work-state log — reminders are *future do-this-thing* items only.

See `.agent0/context/rules/reminders.md` for what belongs here vs `MEMORY.md` vs `HANDOFF.md`, and the discipline (no auto-commit, no autonomous check execution, soft-delete via `status: done + completed_ts`).

All state mutation routes through `.agent0/skills/remind/scripts/reminders-helper.py`. The helper uses `yaml.safe_dump(..., sort_keys=False)` so git diffs stay clean (insertion-order preserved, no alphabetic re-sort).

## Argument parsing

User invokes as `/remind <subcommand> [args]`. The raw argument string is `$ARGUMENTS`. Parse it yourself: split on whitespace, first token is the subcommand (`add` / `list` / `done` / `dismiss` / `snooze` / `check`), the rest are subcommand args. Quoted strings in `<text>` and `--check '<cmd>'` must be honored as single arguments (preserve text between matching quotes). Do not rely on `$1` / `$2`.

Raw invocation: `$ARGUMENTS`

State file: `.agent0/reminders.yaml` (resolve relative to `$CLAUDE_PROJECT_DIR`).

Helper script: `.agent0/skills/remind/scripts/reminders-helper.py`. Invoke as `python3 .agent0/skills/remind/scripts/reminders-helper.py <subcommand> [args...]`, with `CLAUDE_PROJECT_DIR` set in env. The helper is the canonical mutator — never edit `.agent0/reminders.yaml` by hand from this skill body.

## Subcommand: `add`

Append a new reminder. Parse `$ARGUMENTS`: first token must be `add`; the remainder contains the reminder text (typically quoted) and optionally `--due <YYYY-MM-DD>`, `--check '<cmd>'`, `--links <a,b,c>`.

1. **Validate input**:
   - The text must be present and non-empty after trim. Refuse with `add: text is required`.
   - Reject if the text contains a literal newline. Refuse with `add: text must be a single line`.
   - If `--due <date>` is present, the date must match `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`. The helper enforces this — exit code 2 surfaces.
   - `--check '<cmd>'` is an arbitrary bash one-liner. No validation here; the user takes responsibility for shell-safety. The helper does not execute the command at add-time.
   - `--links <a,b,c>` is a comma-separated list of free-form strings (typically file paths or external URLs). Whitespace stripped per item.
2. **Invoke helper**:
   ```
   CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py add "<text>" [--due <date>] [--check '<cmd>'] [--links <a,b,c>]
   ```
   Forward stdout/stderr verbatim. Expected stdout: `added: <id>: <text>`.

## Subcommand: `list`

Print the current reminders. Invoke `python3 .agent0/skills/remind/scripts/reminders-helper.py list` and forward output verbatim. Default filter: `status: pending` plus `status: snoozed` with `snoozed_until <= today` (same as the readout hook). Add `--all` flag to also include done + future-snoozed entries.

Output shape (per the helper):

```
1. [<id>] <context>
   · due: <YYYY-MM-DD>
   · check: <cmd>
   · links: <a>, <b>
2. ...
<N> reminder(s)
```

Positions `1..N` are 1-indexed against the filtered list. The agent can quote the same positions when running `done` / `snooze` / `check` later in the same conversation — but the resolved ID is the canonical identifier; positions shift when entries are added/dismissed.

## Subcommand: `done`

Soft-delete the named entry. Parse `$ARGUMENTS`: first token must be `done`; second token is `<N|id>`.

1. **Validate**: `<N>` must be a positive integer OR `<id>` must match `^r-\d{4}-\d{2}-\d{2}-[a-z0-9-]+$`. The helper enforces both.
2. **Invoke**:
   ```
   CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py done <N|id>
   ```
   The helper flips `status: done` and stamps `completed_ts: <UTC-ISO>`. The entry stays in `reminders.yaml` (soft-delete; audit history in-band).
3. **Report**: forward `done: <id>: <context>` from helper stdout.

## Subcommand: `dismiss`

Silent alias for `done` (backward-compat with the pre-084 muscle memory). Same semantics, same arguments. The helper's `done` subcommand handles both invocation paths. No deprecation warning.

```
CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py done <N|id>
```

Forward the report; surface as `dismissed: <id>: <context>` to keep the verbal echo aligned with the user's invocation.

## Subcommand: `snooze`

Push an entry out of the readout window. Parse `$ARGUMENTS`: first token must be `snooze`; second token is `<N|id>`; third token is the duration.

1. **Validate**: duration must match `^[0-9]+(d|w|m)$` (days/weeks/months — `m` is a 30-day approximation, not calendar months) OR `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` (explicit ISO date). The helper computes `snoozed_until` and refuses on shape error.
2. **Invoke**:
   ```
   CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py snooze <N|id> <duration>
   ```
3. **Report**: forward `snoozed: <id> until <YYYY-MM-DD>`. The readout hook will skip the entry until that date is reached.

## Subcommand: `check`

Run an entry's `check_command` and surface output. Parse `$ARGUMENTS`: first token must be `check`; second token is `<N|id>`.

1. **Resolve the entry's check_command**:
   ```
   CMD="$(CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py get-check <N|id>)"
   ```
   The helper's `get-check` subcommand prints the raw `check_command` string (no shell escaping). If the entry has no `check_command`, the helper exits 2 with `check: entry <id> has no check_command` on stderr — forward that and stop.
2. **Resolve the entry's ID for the report** (positions can change between calls):
   ```
   ID="$(CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" python3 .agent0/skills/remind/scripts/reminders-helper.py resolve <N|id>)"
   ```
3. **Execute the command**: run `$CMD` via `bash -c "$CMD"` from the repo root. Capture stdout, stderr, and exit code separately.
4. **Report** to the agent verbatim:
   ```
   check: <ID>
   $ <CMD>
   <stdout>
   ----- stderr (if any) -----
   <stderr>
   exit: <code>
   ```
   The YAML is NOT mutated. The human-in-loop reads the output and decides whether to `done`, `snooze`, or leave the entry as-is.

## Unknown subcommand

If the first token of `$ARGUMENTS` is missing or not one of `add`, `list`, `done`, `dismiss`, `snooze`, `check`, refuse with a one-line usage hint and stop:

```
/remind <add "<text>" [--due <DATE>] [--check '<cmd>'] [--links <a,b,c>] | list | done <N|id> | dismiss <N|id> | snooze <N|id> <Nd|Nw|Nm|DATE> | check <N|id>>
```

## Notes

_Consumer-extension surface — append consumer-local bullets to this section. Sync flags the file as `!! customized` (sha-compare is section-blind), but the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end. See `.agent0/context/rules/harness-sync.md` § Consumer-extension convention._

- **Don't auto-stage, don't auto-commit.** The founder reviews `git diff` and decides what enters history. Every subcommand leaves the file dirty.
- **Soft-delete is the default.** `done` flips `status: done` + stamps `completed_ts`; the entry remains in `reminders.yaml` carrying its in-band history. If the file grows enough to feel like noise, a future `/remind prune` subcommand (not v1) can hard-remove `done` entries.
- **Positions are not stable IDs.** Pattern is "list, then act on the position you see right now" — same as the pre-084 discipline. Stable IDs (`r-YYYY-MM-DD-<slug>`) are the canonical identifier in storage; positions resolve to IDs at command time. The skill body always logs the resolved ID in its report so the user can confirm.
- **No autonomous `check_command` execution.** The readout hook never runs checks at SessionStart. `check_command` is a probe the agent invokes explicitly via `/remind check <id>` when the entry's relevance comes into question. This preserves the contract-not-promise discipline (see `.agent0/context/rules/delegation.md` § Why DONE_WHEN exists).
- **YAML insertion order is preserved.** The helper uses `yaml.safe_dump(..., sort_keys=False, default_flow_style=False)`. Hand-edit at your own risk — alphabetic re-sort by other YAML tools will pollute git diffs.
- **Single file, structured YAML only.** No JSON, no per-entry file, no JSON Schema validator. Schema lives in the helper's add-validation logic; the file's shape IS the contract. See `.agent0/context/rules/reminders.md` § Frontmatter schema.
- **Reminders are not knowledge.** Facts, decisions, conventions belong in `MEMORY.md` (personal) or `.agent0/context/rules/<topic>.md` (project). See `.agent0/context/rules/memory-placement.md`.
- **Reminders are not session work-state.** In-flight work belongs in `.agent0/HANDOFF.md`. Reminders are *future* work that won't fit the next session's first five minutes. See `.agent0/context/rules/session-handoff.md`.
- See `.agent0/context/rules/reminders.md` for the full capacity description, override grammar, and migration history.
