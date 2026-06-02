# tese

Personal investment **decision-support** dashboard. Tracks an equity thesis (the AI category)
and the real portfolio in one reconciled view: quotes, day change, portfolio weight, P&L.

> Decision-support, not advice. The tool surfaces data; the human decides. No signals, no
> auto-trading, read-only forever. Single user, local-first.

Core differentiator: a **Brazil-aware compliance ledger** — from the first remittance it captures
every field the IRPF (Lei 14.754/2023), Bacen CBE, and US estate rules will later demand, so filing
is a query, not an archaeology dig. Multi-market (US core; China/HK + Korea satellites), IBKR-centric.

## Foundation docs

- [`docs/concept-brief.md`](docs/concept-brief.md) — vision
- [`docs/prd/v1.md`](docs/prd/v1.md) — requirements + user stories
- [`docs/compliance-tax.md`](docs/compliance-tax.md) — obligation→field map (the ledger's source of truth)
- [`docs/system-design.md`](docs/system-design.md) — architecture + data model
- [`docs/roadmap.md`](docs/roadmap.md) — phased build
- [`docs/brand-book.md`](docs/brand-book.md) · [`docs/design-system/`](docs/design-system/) — identity
- [`docs/specs/001-foundation/spec.md`](docs/specs/001-foundation/spec.md) — engineering foundation

## Status

Phase 1 (MVP) implemented from `docs/specs/001-foundation/`.

- **Phase 1 — source A:** market-data (quotes) + manual holdings + the ledger + export.
- **Phase 2 — source B:** live IBKR portfolio (positions/P&L) behind the same interface + threshold flags.

## Stack

Python + FastAPI + SQLite. Static vanilla JS frontend served by FastAPI. Market data uses
`yfinance` behind a `MarketDataSource` adapter for the first local cut.

## Run

```bash
python -m venv .venv
.venv/bin/python -m pip install -e '.[dev]'
cp watchlist.example.yaml watchlist.yaml
.venv/bin/python -m uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000`.

The app stores local data at `data/tese.sqlite` by default. `.env`, `watchlist.yaml`,
`holdings.yaml`, SQLite files, and generated exports are gitignored because they can contain
personal financial data.

## Test

```bash
.venv/bin/python -m pytest
.venv/bin/python -m ruff check .
```

## Export

```bash
.venv/bin/python -m app.cli export --tax-year 2026
```

The export writes `exports/<tax-year>/events.csv` and `exports/<tax-year>/summary.json`.

## Import Opening Holdings

```bash
cp holdings.example.yaml holdings.yaml
.venv/bin/python -m app.cli import-holdings --file holdings.yaml
```

Imported holdings become `OPENING_IMPORT` trade events with explicit `basis_provenance`; they do
not create fake remittance-derived cost basis.
