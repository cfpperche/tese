---
name: Ledger design invariants (from the spec-001 Codex debate)
description: Load-bearing tax-ledger rules — trades-as-truth, derived custo-médio gain,
  append-only via corrections, funding≠basis. Don't regress them
metadata:
  type: feedback
  created_at: '2026-06-02T17:10:00-03:00'
  last_accessed: '2026-06-02'
  confirmed_count: 0
---
A two-round adversarial review of spec 001 with Codex (`codex-exec`, resumed session) hardened the
ledger data model. These are **invariants** — a future agent must not regress them while "making it
simpler". Full detail in `docs/system-design.md` § 3 (D8–D12) and the test oracle in
`docs/specs/001-foundation/fixtures/golden-ledger.md`.

- **D8 — trades are the single source of portfolio truth.** `holdings.yaml` is only a bootstrap,
  ingested as `OPENING_IMPORT` trade events. Never maintain a parallel positions store that could
  diverge from the event log.
- **D9 — `realized_gain_brl` is DERIVED, never hand-entered:** Brazil mandates *custo médio
  ponderado* (no FIFO/LIFO), so gain = net_proceeds_brl − avg_cost_brl × qty_sold. Buy commissions
  capitalize into BRL cost; sell commissions reduce BRL proceeds. Splits/corporate actions are an
  explicit Phase-1 gap.
- **D10 — append-only is real:** fix a mistake by appending a `correction` event that sets the
  target's `voided_by`; never UPDATE/DELETE a row. UI offers correct/void, not edit. Derivations
  skip voided events.
- **D11 — funding ≠ cost basis** (Codex's catch, better than the original proposal): do NOT seed an
  imported position's basis from the remittance FX rate. The position was bought at the trade's own
  price/FX. Imported positions carry `basis_provenance` (VERIFIED/UNVERIFIED/CONTADOR_SUPPLIED) and
  `linked_remittance_id` only when a genuine link exists — forcing one creates fake auditability.
- **D12 — Phase 1 is US-only** (USD→BRL); multi-market (HK/KR) FX is Phase 3, but keep the schema
  currency-aware (don't let `usd_value` become the only valuation primitive).

**Why this matters:** the product's North Star is filing-readiness; these rules are what make the
audit trail *true* rather than asserted. The golden fixture is the executable contract that proves
them — build TDD-first against it. See [[product-artifacts-handbuilt]], [[owner-investment-context]].
