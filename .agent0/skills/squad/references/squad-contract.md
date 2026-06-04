# squad.json — the executable gate contract

`docs/specs/<NNN-slug>/squad.json` is the machine-checkable done-condition for a `/squad` run. The spec stays the source of *intent*; `squad.json` is the *executable* contract `squad.sh` runs. v1 uses JSON (jq-parseable; `jq` is already a harness-wide dependency) — a YAML form (`squad.yaml`) is a future nicety that would add a `yq` dependency. Scaffold from `squad.json.example`.

## Fields

| key | type | meaning |
| --- | --- | --- |
| `spec` | string | `NNN-slug` of the spec being implemented. |
| `roster` | string[] | model speakers (v1: `["claude","codex"]`); `human` is implicit and never a turn-holder. |
| `max_rounds` | int | round ceiling — reaching it → `aborted_budget`. Never infinite. |
| `max_repair_attempts` | int | consecutive gate-fail ceiling — exceeding it → `aborted_repairs`. |
| `gate` | string[] | the **done-condition**: shell commands run from the repo root; ALL must exit 0 for the gate to be green. Put the project validator (`.agent0/validators/run.sh`), the spec's executable acceptance tests, and any build/lint/typecheck here. This is the ONLY thing that reaches `ready_for_human_prod`. |
| `forbidden_paths` | regex[] | paths a turn must never touch → `aborted_policy` if changed. |
| `human_gated_paths` | regex[] | paths whose change pauses for a human → `human_checkpoint_required` (deploy/infra/migrations/CI). |

## Terminal states (set by `squad.sh`, never by agent prose)

- `running` — in progress.
- `ready_for_human_prod` — `gate` green AND every model agent `propose-done`. The human approves + triggers production from here; the squad never deploys to prod.
- `human_checkpoint_required` — a planned phase boundary or a `human_gated_paths` touch; the loop pauses for the human, then may resume.
- `aborted_budget` — `max_rounds` (or a future token/spend ceiling) exhausted.
- `aborted_repairs` — gate failed beyond `max_repair_attempts`.
- `aborted_conflict` — out-of-turn change detected (single-writer violation).
- `aborted_policy` — a `forbidden_paths` path was touched.

## The invariant

`ready_for_human_prod` requires the `gate` green. Agent agreement (`propose-done` from both) is **necessary but never sufficient** — it cannot, alone, close a run. This is the spec-149 (de-biased deliberation) dependency made mechanical: "the agents converged" never substitutes for an external, executable check.
