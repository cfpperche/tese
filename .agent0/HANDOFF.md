# Session Handoff — tese

_Runtime-neutral handoff. Read at session start; update before ending a session._

## Current State

- **Project bootstrapped 2026-06-02.** Public GitHub repo `cfpperche/tese` (Apache-2.0, matching
  Supabase), foundation committed + pushed (`9986a33`).
- **Agent0 harness installed** into this consumer via `sync-harness.sh --apply` (716 files,
  baseline at `.agent0/harness-sync-baseline.json`). Hooks/skills/rules/tools all active.
- **Docs-first foundation complete** under `docs/` (adapted manually from `/product`, launch
  machinery dropped): concept-brief, prd/v1, compliance-tax, system-design, roadmap, brand-book,
  design-system. Engineering foundation child at `docs/specs/001-foundation/spec.md`.
- **No application code yet** — `app/` is an empty scaffold. Phase 1 skeleton not started.

## Active Work

- None in flight. Foundation done **and hardened** via a two-round Codex debate (`codex-exec`); the
  golden fixture is written. Build phase not yet begun.

## Next Actions

1. **`/sdd plan` the Phase-1 MVP, TDD-first off the golden fixture**
   (`docs/specs/001-foundation/fixtures/golden-ledger.md`): write the failing export test that
   asserts the fixture's expected output, then build schema → adapters → derivations → export → UI.
2. FastAPI + SQLite + the **event ledger** (D8–D12: trades-as-truth, derived realized gain via custo
   médio, correction/void events, basis_provenance) + yfinance adapter + dashboard + export.
3. Decide source-A provider for the first cut (lean: **yfinance** behind the adapter).
4. Decide frontend shape (lean: vanilla-JS + Chart.js, static).
5. (Deferred) Phase 2 IBKR adapter + threshold flags; Phase 3 multi-market FX (HK/KR).

## Decisions & Gotchas

- **Posture is load-bearing:** decision-support not advice; read-only forever; contador owns the
  tax numbers, the tool owns the data. Don't let scope creep into signals/scoring.
- **Sequencing:** B (IBKR) never blocks A — Phase 1 ships on manual holdings + market data.
- **Ledger = event-sourced append-only** (point-in-time FX truth for IRPF). See `system-design.md`.
- **Spec-001 debate (Codex) locked D8–D12:** trades = single source of truth (`holdings.yaml` →
  `OPENING_IMPORT`); `realized_gain_brl` DERIVED via custo médio ponderado (fees: buy capitalizes,
  sell reduces proceeds); append-only enforced by `correction`/`voided_by` (correct, never edit);
  funding ≠ cost basis (no remittance-FX seeding); Phase 1 US-only. Splits out of Phase 1.
- **The golden fixture is the test oracle** — code that doesn't reproduce its expected export is
  wrong, not the fixture.
- **Tax figures are provisional** — `compliance-tax.md` § E lists items to confirm with a contador
  (post-2025 IOF reform). No hardcoded liability math.
- **Repo is public; no personal financial data in git** (`holdings.yaml`/`.env`/`*.sqlite` ignored).
- **Owner chat in pt-BR; repo artifacts in English.**
