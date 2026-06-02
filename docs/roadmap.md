# Roadmap — tese

**Status:** draft · **Date:** 2026-06-02

Three phases. Each software phase is **paced to the owner's real investment journey** (folded in
from the broker/market research) — the tool only needs to exist slightly ahead of the money.

---

## Phase 1 — "Ledger + thesis view" (MVP)  ·  pairs with: *open IBKR, test remittance, first ETFs*

**Investment context:** account opening, a small **test remittance**, first **broad ETF** buys.
Low position count, no live broker feed needed yet.

**Build:**
- Project skeleton: FastAPI + SQLite + Chart.js static frontend, one-command run.
- Adapters: `MarketDataSource` → `YFinanceSource`; `PortfolioSource` → `ManualHoldings`.
- **Ledger tables** (remittance, trade, dividend, btc_origin, year_end_balance, instrument_ref).
- Dashboard: watchlist (live quote + day change, incl. unheld) · holdings (qty, avg cost, price,
  **weight**, **P&L**) · category-movement roll-up.
- **Contador-ready export** (CSV/JSON + summary) for a tax year. ← the NSM lands here.
- Seed the thesis watchlist (US core: SMH, QQQ, NVDA, MSFT, GOOGL…).

**Done-when:** `uvicorn` shows thesis × portfolio reconciled, the owner can log a remittance + a
buy + a 31/12 balance by hand, and export a complete year record.

**Covers:** US-01..US-07.

---

## Phase 2 — "Live truth + guardrails"  ·  pairs with: *scaling aporte, adding single US names*

**Investment context:** recurring monthly aportes, first **individual US stocks**, portfolio
large enough that manual entry is friction and thresholds start to matter.

**Build:**
- `IBKRSource` against the IBKR **Web API** (OAuth2 preferred; CP Gateway fallback) — same
  `PortfolioSource` interface, so the UI is unchanged. Isolate session lifecycle + keep-alive.
- **Threshold flags:** US-situs → US$ 60k (estate-tax planning prompt: consider UCITS); total
  foreign assets → US$ 1M (CBE annual).
- Per-holding **market** (US/HK/KR) + **instrument** (stock/ETF/ADR/UCITS) + **us_situs** tagging,
  feeding the roll-ups.
- Dividend + foreign-withholding capture wired to the live feed where IBKR exposes it.

**Done-when:** holdings come live from IBKR with no UI change; crossing US$ 60k US-situs fires a
visible flag; export now reconciles live positions.

**Covers:** US-08, US-09, US-10.

---

## Phase 3 — "Diligence + history"  ·  pairs with: *satellites (China/HK, Korea), multi-year*

**Investment context:** small **satellite** positions (China via HK/ADR, Korea via KRX/ETF),
multi-year history accumulating, diligence on single names.

**Build:**
- Time series: portfolio value + category movement over time (charts).
- `FinnhubSource` fundamentals/news per ticker for diligence (behind the existing interface).
- Multi-market polish: market-hours awareness per exchange (US/HK/KR), multi-currency display.
- Multi-year analytics in the export (year-over-year positions, cumulative gains/dividends).

**Done-when:** the owner can review a name's fundamentals + the category's multi-year movement, and
satellite markets render correctly.

**Covers:** US-11, US-12 + multi-market depth.

---

## Explicitly out of scope (all phases)

Trading/execution · advice/signals/scoring · auto-filing taxes · multi-user/auth/hosting · pricing/
marketing. (See `prd/v1.md` anti-goals.)

## Sequencing principle

**B (IBKR) never blocks A.** Phase 1 is fully useful with manual holdings; the live feed is a
later upgrade, not a prerequisite — matching the reality that the IBKR account + auth take time to
stand up while the owner wants the ledger running from aporte #1.
