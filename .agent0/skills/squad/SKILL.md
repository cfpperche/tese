---
name: squad
description: >-
  Autonomous, symmetric, ping-pong multi-agent build loop (spec 150). Use when
  two heterogeneous LLM runtimes (Claude Code + Codex CLI) should implement an
  already-/sdd-planned spec together, taking turns WITHOUT a human pumping each
  turn, until an EXTERNALLY-verified done-condition (the squad.json gate:
  tests/build/validator green) is met — then the human approves and triggers
  production. Bounded (round/repair ceilings), turn-locked single-writer,
  human-at-milestone-gates. Done is NEVER "the agents agree" — agreement only
  proposes done; the external gate closes the run. Subcommands - init <NNN-slug>,
  run, status, abort; --mode assisted is a human-pumped debug path. The
  deterministic state machine is scripts/squad.sh; the gate contract is
  docs/specs/NNN/squad.json. Reuses spec-149's de-biased deliberation for any
  in-loop disagreement. NOT for autonomous production deploy (agents prepare,
  human triggers). See .agent0/context/rules/squad.md.
allowed-tools: Bash, Read, Edit, Write, Agent
argument-hint: "init <NNN-slug> [--initiator claude|codex] | run | status | abort"
---

# /squad — autonomous multi-agent build loop

Convenes two heterogeneous runtimes to implement one **already-`/sdd plan`-ned** spec autonomously to **external green gates**, then hands off to the human for approval + production. The state machine `scripts/squad.sh` owns everything mechanical (run state, turn-lock, budget, gate, terminal states, guard, rollback); this skill is the **pump loop** the initiating runtime drives over it. Full rationale + safety lineage: `.agent0/context/rules/squad.md` (and spec 150).

**Hard invariant:** agent agreement only sets `propose-done`; **the external gate (`squad.json`) green is the ONLY path to `ready_for_human_prod`.** This is why spec 149 (de-biased deliberation) is a hard predecessor.

## Preconditions (refuse if unmet)

1. The target spec has a filled `spec.md` + `plan.md` + `tasks.md` (squad implements a planned spec; it does not plan).
2. `docs/specs/<NNN-slug>/squad.json` exists and is valid (the executable gate contract — see `references/squad-contract.md`; scaffold from `references/squad.json.example`). Refuse with a pointer if absent.
3. The working tree is clean (the loop snapshots/guards against out-of-turn changes).
4. The human has approved starting the loop (this is an autonomous, cost-bearing run).
5. **The target repo contains the Agent0 harness** (it *is* Agent0, or a consumer with the harness synced). The exec bridges (`codex-exec`/`claude-exec`) anchor `ROOT` to the harness root and **refuse a `--cwd` outside it** — so `/squad` cannot drive the peer against an external/throwaway repo (e.g. one under `/tmp`). `init` warns if the bridge scripts are absent under the target repo. (Dogfood finding 150.1.)

## Subcommand: `init <NNN-slug>` — 🔒 Low freedom

`run="$(bash .agent0/skills/squad/scripts/squad.sh init --spec <NNN-slug> [--initiator <your-id>])"`. Echoes the run dir under `.agent0/.runtime-state/squads/`. The initiating runtime is whoever ran the command (symmetric: Claude or Codex). Report the run dir + that the next step is `run`.

## Subcommand: `run` — 🔓 Medium freedom: the pump loop

The initiating runtime drives this loop. **One turn at a time; the pump enforces every bound — never free-run past a terminal state.**

```
loop:
  status = squad.sh status --run <run>
  if status is terminal (ready_for_human_prod | human_checkpoint_required | aborted_*): break
  holder = status.turn_holder
  if holder == me:
      squad.sh turn-start --run <run> --speaker me
      … implement this turn's slice (Edit/Write), guided by tasks.md …
      squad.sh turn-end   --run <run> --speaker me      # snapshots diff, flips holder, enforces budget
      squad.sh guard      --run <run>                    # out-of-turn / forbidden-path → abort
      squad.sh gate       --run <run>                    # external gate; green+both-proposed → ready_for_human_prod
      if I believe the spec's acceptance is met: squad.sh propose-done --run <run> --speaker me
  else:
      # hand the turn to the peer via the exec bridge, WORKSPACE-WRITE, bounded
      #   from Claude:  codex-exec  --sandbox workspace-write  --task-file <brief>
      #   from Codex:   claude-exec --permission-mode acceptEdits --task-file <brief>
      # the brief: the run dir, the spec + tasks.md, "you are <peer>; take ONE turn:
      #   squad.sh turn-start; implement your slice; squad.sh turn-end; guard; gate;
      #   propose-done if acceptance met. Do NOT touch forbidden paths. Stop after one turn."
      # capture the bridge result; continue the loop.
```

- **Disagreement in-loop** (the agents differ on an approach) → run the spec-149 de-biased mini-deliberation (`meeting.sh` blind commit/reveal + claim/evidence ledger) rather than letting the louder turn win.
- **`human_checkpoint_required`** (a planned phase boundary or a human-gated path) → STOP, surface the state + a summary, wait for the human. Do not auto-continue past a checkpoint.
- **Any `aborted_*`** → STOP, surface `squad.sh status` + a short report (what was done, why it aborted), wait for the human. `squad.sh rollback --run <run>` is available to restore the last clean boundary.

## Subcommand: `run --mode assisted` — 🔓 (debug/compat)

Same state machine, but the **human pumps each turn** (no exec-bridge auto-dispatch). Useful to dogfood the gate/guard/budget mechanics without a live autonomous loop. Not the default — the autonomous pump is the point of `/squad`.

## Subcommand: `status` / `abort` — 🔒 Low freedom

`status` prints `squad.sh status --run <run>` (state.json). `abort --reason <r>` terminally stops a run.

## At `ready_for_human_prod` — 🔒 the human gate

Report: what was built, the green gate output, the claim/evidence ledger (why done), and the changed-paths summary. **The squad never deploys to production** — it prepares (IaC/migrations/runbook/staging as the spec dictates) and the human triggers the production deploy. Outward/destructive actions remain governance-gated.

## Notes

- v1 is Claude↔Codex; the protocol is N-ready (the `/squad` name future-proofs more runtimes). v1 write model is turn-locked single-writer on one tree (worktree-per-agent is v2).
- Cost: `squad.json` carries `max_rounds` / `max_repair_attempts` (+ future token/spend ceilings); the pump circuit-breaks on exhaustion → `aborted_budget`/`aborted_repairs` with a report. Never infinite.
- `/squad` runs a spec the existing pipeline produced; it does not replace `/product` or SDD.
