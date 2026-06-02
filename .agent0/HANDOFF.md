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
- **Spec-001 Phase-1 MVP implemented and validated** on 2026-06-02. `spec.md` is `shipped`;
  `plan.md`, `tasks.md`, and `notes.md` are present under `docs/specs/001-foundation/`.
- **Application code now exists** under `app/`: FastAPI + SQLite + static vanilla JS frontend.

## Active Work

- None in flight. Spec-001 is implemented and validated:
  `.venv/bin/python -m pytest` (7 passed, 1 upstream Starlette/httpx deprecation warning),
  `.venv/bin/python -m ruff check .` (passed), Uvicorn smoke (`/health` + `/`), CLI export smoke,
  and CLI holdings-import smoke.
- Golden fixture remains the contract:
  `docs/specs/001-foundation/fixtures/golden-ledger.md`.

## Next Actions

1. Optional next product work: improve the ledger-entry UI from JSON templates to dedicated field
   controls; add owner-entered current FX for dashboard BRL P&L; add market-hours scheduling.
2. Keep Phase 2 deferred: IBKR adapter + threshold alerting after the local ledger/export surface
   is comfortable to use.

## Decisions & Gotchas

- **Posture is load-bearing:** decision-support not advice; read-only forever; contador owns the
  tax numbers, the tool owns the data. Don't let scope creep into signals/scoring.
- **Shipped choices:** ledger/export-first, FastAPI + SQLite, explicit SQL repositories before ORM,
  `yfinance` only behind `MarketDataSource`, static vanilla JS frontend, no CDN dependency for
  charts, `Decimal` for all monetary math.
- **Sequencing:** B (IBKR) never blocks A. Phase 1 ships on manual holdings import + market data;
  Phase 2 IBKR and threshold alerts are deferred.
- **Ledger = event-sourced append-only** (point-in-time FX truth for IRPF). Correction/void export
  should derive visible `voided_by` from correction events, not require UPDATE/DELETE on originals.
- **Spec-001 debate (Codex) locked D8–D12:** trades = single source of truth (`holdings.yaml` →
  `OPENING_IMPORT`); `realized_gain_brl` DERIVED via custo médio ponderado (fees: buy capitalizes,
  sell reduces proceeds); append-only enforced by `correction`/`voided_by` (correct, never edit);
  funding ≠ cost basis (no remittance-FX seeding); Phase 1 US-only. Splits out of Phase 1.
- **The golden fixture is the test oracle** — code that doesn't reproduce its expected export is
  wrong, not the fixture.
- **Dashboard BRL P&L is decision-support only:** current BRL market value uses the ticker's latest
  trade FX as a pragmatic local estimate; compliance export remains anchored to explicit year-end
  balance FX.
- **Tax figures are provisional** — `compliance-tax.md` § E lists items to confirm with a contador
  (post-2025 IOF reform). No hardcoded liability math.
- **Repo is public; no personal financial data in git** (`holdings.yaml`/`.env`/`*.sqlite` ignored).
- **Owner chat in pt-BR; repo artifacts in English.**
