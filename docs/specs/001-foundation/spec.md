# 001 — Foundation: personal investment decision-support dashboard

**Status:** draft
**Owner:** Carlos Perche
**Type:** personal tool (single user, local-first). NOT a product for other users — no auth, no multi-tenancy, no billing, no marketing surface.

## Intent

A personal **decision-support + compliance ledger** for investing abroad from Brazil. The owner
forms a thesis (US tech core; China/HK and Korea as satellites) and holds directly through an
international broker (IBKR). The tool (a) reconciles the **category** watched with the **portfolio**
held, and (b) captures from the first remittance every field the Brazilian filings (IRPF / Lei
14.754, Bacen CBE) and US estate rules will later demand.

This is a decision-support instrument. It surfaces price, weight, P&L, category movement, and the
tax record. It does not recommend, score, auto-trade, or compute tax liability. The human decides;
the contador files.

> **Scope note:** this spec is the engineering foundation child. The full product vision lives in
> the docs-first foundation: `docs/concept-brief.md`, `docs/prd/v1.md`, `docs/compliance-tax.md`
> (the obligation→field map that drives the ledger), `docs/system-design.md` (data model),
> `docs/roadmap.md`, `docs/brand-book.md`, `docs/design-system/`.

## Problem

Today the owner is moving a small position (~$6k) out of BTC into AI-thesis US equities and
will hold a few positions (3–4 tickers) plus a wider watchlist of the category. There is no
single place that shows, together:

- how the **category** (the AI thesis universe) is moving — including names not yet held;
- what the **real portfolio** is doing — positions, cost basis, P&L, weight;
- the two reconciled — "what I watch" × "what I own".

Brokerage apps show only holdings; market apps show only quotes. The gap is the reconciled view.

## Approach — A + B, sequenced

Two data sources with distinct roles (see prior analysis):

| Source | Role | Phase |
|---|---|---|
| **A — market-data API** (Finnhub / Twelve Data / yfinance) | Category breadth: quotes, day change, fundamentals, news for the whole watchlist (incl. unheld names) | **Phase 1 (MVP)** |
| **B — IBKR Web API** (Client Portal / OAuth2) | Source of truth for the real portfolio: positions, cost basis, P&L, cash | **Phase 2** |

**Why sequenced:** B depends on an IBKR account (not yet open) and a continuously-authenticated
session (CP Gateway / OAuth — session expires ~daily, 2FA). Phase 1 delivers a useful tool with
zero of that friction by treating holdings as a manually-maintained list, overlaid with live
market data. Phase 2 swaps the manual holdings for the live IBKR feed without changing the UI.

### Architecture

```
                 ┌─ A: market-data API (Finnhub/yfinance) ──► quotes, change, fundamentals
 collector ──────┤
 (FastAPI +      └─ B: IBKR Web API (Phase 2) ──────────────► positions, P&L, cash
  scheduler)
      │
      ▼
   cache/store (SQLite)  ──►  FastAPI JSON API  ──►  frontend (charts: price, weight, P&L, category move)
```

- **Backend:** Python + **FastAPI**. A collector polls source A on an interval (respecting rate
  limits), normalizes, and persists to **SQLite**. API routes serve the frontend.
- **Holdings (Phase 1):** a local file (`holdings.yaml`) — ticker, qty, avg cost. Hand-edited.
- **Frontend:** lightweight (decided at /plan — likely a small SPA or server-rendered + a charts
  lib). Served by FastAPI as static.
- **Phase 2:** an IBKR adapter implementing the same internal `PortfolioSource` interface the
  manual file implements, so the swap is a config flip, not a rewrite.

## Scope (Phase 1 / MVP)

- [ ] Watchlist config (the thesis universe) + holdings config (manual).
- [ ] Collector pulls quotes + day change for watchlist & holdings from source A.
- [ ] SQLite persistence + a thin query API.
- [ ] **Ledger tables** (remittance, trade, dividend, btc_origin, year_end_balance, instrument_ref)
      with append-only events — per `docs/system-design.md` § Data model.
- [ ] Ledger entry UI (remittance / trade / dividend / 31-12 balance / BTC origin) — fields map 1:1
      to `docs/compliance-tax.md` § B.
- [ ] **Contador-ready export** (CSV/JSON + summary) for a tax year. ← the North Star.
- [ ] Dashboard view: per-ticker price & day change; portfolio weight; simple P&L vs. avg cost;
      a "category movement" roll-up across the watchlist.
- [ ] Runs locally with one command; one API key (source A) in `.env`.

## Non-goals (explicit)

- No buy/sell signals, scoring, ranking, or "recommendation" of any kind. Decision-support only.
- No multi-user, auth, accounts, billing, or hosted/public deployment.
- No GTM, pricing, brand, legal, marketing — this is not that kind of project.
- No order execution / trading. Read-only forever.
- No tax engine (BTC/IR math stays in the owner's spreadsheet/contador, out of scope here).

## Open questions (resolve at /plan)

1. Source A provider: **Finnhub** (free tier, good fundamentals+news) vs **yfinance** (no key,
   great for prototype, ToS-grey for anything beyond personal) vs **Twelve Data**. Lean: yfinance
   for the first runnable cut, Finnhub as the "real" key-based source behind the same adapter.
2. Frontend shape: minimal SPA (e.g. plain JS + a charts lib) vs a Python-native quick UI. The
   owner chose "Python (FastAPI + frontend)" — frontend stack TBD at /plan.
3. Polling cadence + market-hours awareness (don't poll a closed market).
4. Phase-2 IBKR auth path: CP Gateway (Java daemon) vs newer OAuth2 Web API — confirm which the
   account has access to before designing the adapter.

## Done-when (Phase 1)

Phase 1 is done when **both** the dashboard **and** the compliance ledger work — filing-readiness is
the North Star, so a dashboard alone is NOT "done":

1. A local `uvicorn` run shows the thesis watchlist + holdings with live quotes, day change,
   portfolio weight, and P&L (positions **derived from trade events**, not a parallel store — D8).
2. The owner can record the full event set by hand — remittance, BTC-origin, BUY, dividend,
   **partial SELL** (with `realized_gain_brl` **derived** via custo médio — § 3.1/D9), 31/12 balance —
   and **correct/void** a bad event without editing it (D10).
3. A one-command **contador-ready export** (CSV/JSON + summary) reproduces the **golden fixture**'s
   expected output exactly (see `fixtures/`).
4. The data layer is abstracted so Phase 2 can plug IBKR behind the same interface.

**The golden fixture (`fixtures/golden-ledger.md`) is the executable contract** that drives the
schema and the tests — write it (and its expected export) before any production code (TDD).

## Spec-001 debate outcome (folded in)

A two-round adversarial review with Codex (`codex-exec`) hardened this spec. Resolved:
- **D8** trades = single source of truth; `holdings.yaml` → `OPENING_IMPORT` events.
- **D9** `realized_gain_brl` derived via custo médio ponderado; fees rule fixed; splits out of Phase 1.
- **D10** append-only enforced by `correction`/`voided_by` — correct, never edit.
- **D11** funding ≠ cost basis — imported positions carry `basis_provenance`, not remittance-seeded.
- **D12** Phase 1 US-only (USD→BRL); multi-market deferred to Phase 3; schema stays currency-aware.
- Done-when corrected to require ledger + export (was dashboard-only — internal contradiction).

See `docs/system-design.md` § 3 for the full data model.
