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
- **Ledger-entry UI upgraded** from a JSON textarea to dedicated field controls, and request
  handlers moved to per-request DB connections (race fix), on branch `chore/ledger-ui-conn-fix`
  as of 2026-06-03. See Active Work.

## Active Work

- None in flight. Two changes shipped this session on branch `chore/ledger-ui-conn-fix`
  (commits `806a651` UI, race-fix commit follows) — to be merged to `main`:
  1. **Dedicated-field ledger UI.** Replaced the JSON `<textarea>` with per-event-type dedicated
     controls driven by a declarative `FIELD_SCHEMAS` in `app/static/app.js`
     (+ `renderEventFields`/`buildEventPayload`); `index.html` hosts `<div id="event-fields">`;
     `styles.css` got a 2-col field grid + checkbox row. Type coupling is 1:1 with the repo:
     money/decimals serialize as STRINGS (backend does `Decimal(str(...))` — never send JS numbers),
     `tax_year` as Number, booleans as real checkboxes, `side`/`origin` as `<select>` matching the
     schema CHECK constraints; blank optionals omitted so backend defaults apply; after save fields
     reset to defaults but the selected type is kept.
  2. **Per-request DB connection (race fix).** Request handlers now resolve a fresh connection via
     `app.api.deps.get_conn` (`ConnDep` = `Annotated[Connection, Depends(get_conn)]`) instead of the
     shared `app.state.conn`. `app.state.conn` stays only for startup migrate + as the test seeding
     handle. Routes `dashboard/ledger/quotes/export` + `/health` all converted.
- **Verified:** `pytest` 9 passed (2 new isolation/parallel tests), `ruff` clean, Playwright browser
  run (NVDA trade persisted with correct typing → position rendered), and a live-server concurrent
  hammer (400 parallel requests across both endpoints → 0 non-200, 0 server tracebacks).
- Golden fixture remains the contract:
  `docs/specs/001-foundation/fixtures/golden-ledger.md`.

## Next Actions

1. **Merge `chore/ledger-ui-conn-fix` into `main`** (fast-forward) if not already done, and optionally
   delete the branch. Push when ready (not pushed automatically).
2. Optional next product work: add owner-entered current FX for dashboard BRL P&L; add market-hours
   scheduling. NOTE: when APScheduler lands, it must NOT reuse `app.state.conn` from its job thread —
   give scheduled jobs their own connection (same reasoning as the per-request fix).
3. Keep Phase 2 deferred: IBKR adapter + threshold alerting after the local ledger/export surface
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
