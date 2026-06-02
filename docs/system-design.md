# System Design — tese

**Status:** draft · **Date:** 2026-06-02 · **Type:** personal tool, local-first

## 1. Stack

- **Language/runtime:** Python 3.12+.
- **Backend:** FastAPI (API + serves static frontend) + Uvicorn.
- **Persistence:** SQLite (single-file, local). Migrations via lightweight SQL or `alembic` if it
  grows. No server DB — single user, local-first.
- **Scheduler:** APScheduler (in-process) for market-hours-aware polling of the market-data source.
- **Frontend:** vanilla JS SPA + Chart.js (or uPlot), served as static by FastAPI. No build step.
- **Config:** `.env` (API keys) + `holdings.yaml` (positions, Phase 1) + `watchlist.yaml` (thesis).
- **Tooling:** `ruff` (lint/format), `pytest` (TDD — see foundation spec), `uv`/`pip` for deps.

## 2. Integrations (two planes behind adapters)

The whole design hinges on **two abstract interfaces** so each plane has a swappable
implementation:

```
MarketDataSource (A)              PortfolioSource (B)
  .quote(ticker) -> Quote           .positions() -> [Position]
  .quotes([t])   -> [Quote]         .cash()      -> [Cash]
  .fundamentals(t) (opt)            (events ingested separately into the ledger)

  impls:                            impls:
   - YFinanceSource  (Phase 1)        - ManualHoldings (holdings.yaml)  (Phase 1)
   - FinnhubSource   (Phase 1+)       - IBKRSource     (Web API)        (Phase 2)
```

- **Phase 1 — A:** `YFinanceSource` (no key, instant) with `FinnhubSource` ready behind the same
  interface for keyed fundamentals/news. **B:** `ManualHoldings` reads `holdings.yaml`.
- **Phase 2 — B:** `IBKRSource` against the IBKR **Web API** (OAuth2 preferred; CP Gateway daemon
  fallback). Same interface → the dashboard and ledger don't change. IBKR session lifecycle (daily
  expiry, 2FA) is isolated inside this adapter + a small keep-alive process.
- Rate limits respected per source (Finnhub free tier; IBKR 10 req/s, 100 market-data lines).

## 3. Data model (the ledger — drives `compliance-tax.md`)

SQLite tables. **Events are append-only and immutable**; positions/balances are derived or
snapshotted. (Design hardened by the spec-001 Codex debate — see § 3.4.)

**Shared event provenance.** The central `ledger_events` table carries: `id`, `created_at` (ingest
timestamp, distinct from the economic `date`), `source` (`MANUAL | IMPORT | IBKR`), and `notes`.
Export/API projections expose `voided_by` by deriving it from immutable `correction` rows; the
original event row is never updated just to mark a correction. Listed once here; omitted per-table
below for brevity.

```
remittance        date, brl_amount, usd_credited, fx_rate, fx_provenance, iof, wire_fee,
                  source_account, broker
trade             date, ticker, market(US|HK|KR), currency, instrument(STOCK|ETF|ADR|UCITS),
                  us_situs(bool), side(BUY|SELL),
                  origin(NORMAL|OPENING_IMPORT),        # OPENING_IMPORT = pre-existing position
                  qty, unit_price, commission, fx_to_brl, fx_provenance, brl_value,
                  basis_provenance(VERIFIED|UNVERIFIED|CONTADOR_SUPPLIED),  # for OPENING_IMPORT
                  linked_remittance_id(nullable),       # funding link IF it genuinely exists
                  realized_gain_brl(DERIVED, SELL only) # computed, not hand-entered — see § 3.1
dividend          date, ticker, gross, currency, foreign_tax_withheld, net, fx_to_brl, fx_provenance
btc_origin        date, brl_proceeds, acq_cost_brl, gain_brl, exempt_35k(bool),
                  in1888_reportable(bool)               # cost-base root of the foreign capital
year_end_balance  tax_year, ticker, qty, price, price_provenance, fx_rate, fx_provenance,
                  brl_value, usd_value                  # 31/12 snapshot
correction        target_table, target_id, reason       # voids/replaces a prior event (§ 3.2)
instrument_ref    ticker(PK), name, market, instrument, us_situs, thesis_tag   # watchlist meta
quote_cache       ticker, ts, price, day_change_pct, currency                  # from source A
```

### 3.1 Realized gain is DERIVED, not entered (custo médio ponderado)
Brazil mandates **weighted-average cost** for securities (no FIFO/LIFO choice), and Lei
14.754/2023 realization follows the same basis. So on a SELL:
`realized_gain_brl = net_proceeds_brl − (avg_cost_brl × qty_sold)`, deterministic. Fee rule:
**buy commissions capitalize into BRL cost**; **sell commissions reduce BRL proceeds**. `avg_cost_brl`
is the running weighted average over prior BUY/OPENING_IMPORT events for that ticker. The export
labels this field **derived** (not contador-supplied). **Splits / corporate actions are out of
Phase 1** (documented gap, not silent).

### 3.2 Append-only is real: correct, never edit
A mistake is fixed by appending a `correction` event that targets the bad event. The original row is
never mutated; `voided_by` is a projection/export field derived from correction rows. Derivations
and roll-ups skip voided events. This is what makes the audit trail in `compliance-tax.md` § C true
rather than asserted. The ledger-entry UI exposes "correct" / "void", not "edit".

### 3.3 Imported (pre-existing) positions — funding ≠ basis
An imported holding is an `OPENING_IMPORT` trade, **not** a fake NORMAL buy. Its cost basis is NOT
auto-seeded from a remittance FX rate — *funding provenance ≠ trade cost basis* (the position was
bought at the trade's own price/FX, not at the remittance rate). `basis_provenance` marks it
`UNVERIFIED` / `CONTADOR_SUPPLIED` and the UI shows that state; `linked_remittance_id` is set only
when a genuine funding→trade link exists. Forcing a link creates fake auditability.

### 3.4 Derived (views / computed, not stored)
- `position` = Σ non-voided trades per ticker (qty, weighted `avg_cost_brl`) → joined with
  `quote_cache` for live value, weight, unrealized P&L.
- `foreign_assets_usd_total` → CBE flag (≥ US$ 1M).
- `us_situs_usd_total` (Σ positions where `instrument_ref.us_situs`) → estate-tax flag (≥ US$ 60k).
- Tax-year roll-ups: realized gains, dividends + withholding, remittance log.

### 3.5 FX & valuation provenance
Every monetary event stores both the rate and its `fx_provenance` (the rate **the owner used** is
legally relevant, not a market reference). **Phase 1 is US-only → only USD→BRL is exercised**;
non-USD trade/valuation paths are deferred to Phase 3 but the schema stays currency-aware (do not
let `usd_value` become the sole valuation primitive). The 31/12 snapshot captures `price_provenance`
+ `fx_provenance` explicitly — the exact source is owner-chosen/owner-provided until
`compliance-tax.md` § E is resolved with a contador.

**Why append-only events + snapshots:** Brazilian filing needs *historical truth* (the FX rate on
the day of each event, the 31/12 value), not just current state. Recomputing from a mutable
positions table would lose the legally-relevant point-in-time figures.

## 4. Decisions locked

- **D1** Local-first, single-user, SQLite. No cloud, no auth in v1.
- **D2** Two-plane adapter architecture (A market-data, B portfolio) — both swappable; Phase 2 IBKR
  is an adapter swap, not a rewrite.
- **D3** Ledger is **event-sourced + append-only**; positions/balances derived or snapshotted.
- **D4** The tool records the **FX rate the owner used** per event (legally relevant), not a market
  reference rate.
- **D5** Read-only forever — no broker write/trade scopes are ever requested, even from IBKR.
- **D6** No tax *computation* of liability; informational roll-ups + export only (contador owns the
  binding numbers).
- **D7** Secrets (`.env`) and personal positions (`holdings.yaml`, `*.sqlite`) are gitignored.
- **D8** **Trades are the single source of portfolio truth.** `holdings.yaml` is an optional
  bootstrap, ingested as `OPENING_IMPORT` trade events — not a parallel position store. Resolves the
  spec-001 divergence (two truths) Codex flagged.
- **D9** **`realized_gain_brl` is derived** via custo médio ponderado (§ 3.1), never hand-entered;
  splits/corporate actions are an explicit Phase-1 gap.
- **D10** **Append-only is enforced by `correction`/`voided_by`** (§ 3.2) — no row is ever mutated;
  the UI offers correct/void, not edit.
- **D11** **Funding ≠ cost basis** (§ 3.3): imported positions are not basis-seeded from remittance
  FX; `basis_provenance` carries the unverified/contador-supplied state.
- **D12** **Phase 1 is US-only** (USD→BRL); multi-market FX deferred to Phase 3, schema stays
  currency-aware.

## 5. Security

- Single local user; threat model is **local data hygiene + secret handling**, not network attackers.
- API keys only in `.env` (gitignored). No secrets in code or committed files.
- IBKR (Phase 2): OAuth2 tokens stored locally with file-perms 600; **never** request trading
  scopes; the keep-alive process runs locally only.
- The SQLite file holds personal financial data → document a backup/encryption note for the owner
  (e.g. full-disk encryption / encrypted backup); not a hosted concern.
- No telemetry, no external calls except the chosen market-data API and (Phase 2) IBKR.

## 6. Observability

- Structured logs (stdlib `logging`) for collector runs: source, tickers fetched, latency, errors.
- A `/health` endpoint (sources reachable? last poll ts? DB writable?).
- Collector writes a `last_sync` row; the dashboard shows data freshness so a stale market-data
  source is visible, never silent.

## 7. RACI (lightweight — single-owner project)

| Activity | Responsible | Accountable | Consulted | Informed |
|---|---|---|---|---|
| Build / architecture | Owner (+ Claude) | Owner | — | — |
| Investment decisions | Owner | Owner | — | tool (data only) |
| Tax figures & filing | **Contador** | Owner | tool export | Receita/Bacen |
| FX execution / remittance | Owner | Owner | bank/Wise | — |

The split that matters: **the tool is Consulted (data), never Accountable** for tax or decisions.

## 8. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Market-data source breaks/ToS (yfinance) | Med | Med | Adapter isolates it; Finnhub behind same interface as keyed fallback |
| IBKR session/auth fragility (daily expiry, 2FA) | High | Med | Isolated in IBKRSource + keep-alive; Phase 1 doesn't depend on it |
| Wrong/stale FX rate recorded | Med | High (tax) | Record owner's actual-used rate per event; show provenance; contador validates |
| Tax rule drift (post-2025 IOF, Receita guidance) | High | Med | Rules live in `compliance-tax.md` as data, flagged "confirm w/ contador"; no hardcoded liability math |
| Misclassified us_situs → missed estate-tax flag | Low | High | Explicit `us_situs` field per instrument; default conservative (US-domiciled = true) |
| Personal data leak (SQLite/`.env`) | Low | High | Gitignored; FDE/backup note; no cloud |
| Scope creep into "advice"/signals | Med | High (intent) | Anti-goals in PRD; D5/D6 locked; no scoring code merged |

## 9. Cross-references

- `compliance-tax.md` — the obligation→field source this data model implements.
- `prd/v1.md` — US-NN stories mapped to tables/endpoints.
- `roadmap.md` — phase boundaries.
- `specs/001-foundation/spec.md` — the engineering foundation child.
