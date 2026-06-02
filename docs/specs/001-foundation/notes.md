# 001 - foundation - notes

## Design decisions

### 2026-06-02 - parent - Correction projection stays append-only

The implementation stores immutable correction rows and derives `voided_by` in repository/export
projections. The original economic event row is not updated just to mark a correction.

### 2026-06-02 - parent - Dashboard P&L uses latest trade FX for live quote view

The live dashboard has USD quotes and BRL cost basis. For the Phase 1 decision-support view, current
market value BRL and unrealized P&L use the ticker's latest trade FX as a pragmatic local estimate.
Tax-year export remains anchored to explicit year-end balance FX and is the compliance source.

### 2026-06-02 - parent - Ruff excludes Agent0 harness files

The product linter is scoped to app/tests/docs-facing project files and excludes `.agent0`, `.claude`,
`.codex`, `.venv`, and generated assets. Agent0 harness code has its own lifecycle and should not
block the consumer app's lint gate.

## Deviations

### 2026-06-02 - parent - Static dashboard uses tables before chart library

The plan allowed Chart.js if practical, but the MVP dashboard ships dense tables and CSS metrics.
That keeps the local-first/no-CDN constraint clean while preserving the required price, day change,
weight, P&L, category movement, ledger entry, correction, and export controls.

## Tradeoffs

### 2026-06-02 - parent - Explicit SQL instead of ORM

The first implementation uses SQL migrations plus repository methods. This keeps append-only
behavior and export math easy to audit against the golden fixture.

## Open questions

- Whether the live dashboard should eventually use a separate owner-entered current FX rate instead
  of latest trade FX for BRL P&L display.
