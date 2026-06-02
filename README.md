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

Phase 1 (MVP) in spec.

- **Phase 1 — source A:** market-data (quotes) + manual holdings + the ledger + export.
- **Phase 2 — source B:** live IBKR portfolio (positions/P&L) behind the same interface + threshold flags.

## Stack

Python + FastAPI + SQLite. Frontend TBD (see spec open questions).

## Run

_TBD — defined at the plan stage._
