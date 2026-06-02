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

- None in flight. The foundation phase is done; the build phase has not begun.

## Next Actions

1. **`/sdd plan` the Phase-1 MVP** (or build directly): FastAPI + SQLite + the ledger tables +
   manual-holdings adapter + yfinance market-data adapter + dashboard + contador-ready export.
   Seed the thesis watchlist (US core: SMH, QQQ, NVDA, MSFT, GOOGL…).
2. Decide source-A provider for the first runnable cut (lean: **yfinance** behind the adapter;
   Finnhub later for fundamentals/news).
3. Decide frontend shape concretely (lean: vanilla-JS + Chart.js, served static).
4. (Deferred to Phase 2) IBKR account opening + `IBKRSource` adapter + threshold flags.

## Decisions & Gotchas

- **Posture is load-bearing:** decision-support not advice; read-only forever; contador owns the
  tax numbers, the tool owns the data. Don't let scope creep into signals/scoring.
- **Sequencing:** B (IBKR) never blocks A — Phase 1 ships on manual holdings + market data.
- **Ledger = event-sourced append-only** (point-in-time FX truth for IRPF). See `system-design.md`.
- **Tax figures are provisional** — `compliance-tax.md` § E lists items to confirm with a contador
  (post-2025 IOF reform). No hardcoded liability math.
- **Repo is public; no personal financial data in git** (`holdings.yaml`/`.env`/`*.sqlite` ignored).
- **Owner chat in pt-BR; repo artifacts in English.**
