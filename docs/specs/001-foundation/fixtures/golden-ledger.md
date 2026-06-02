# Golden fixture — the Phase-1 ledger/export contract

**Status:** executable contract · **Date:** 2026-06-02 · drives schema + tests (TDD, write first)

This is the **single source of truth** the Phase-1 build is tested against. It encodes the full
event lifecycle (US-only, custo médio) and the **exact** derived output the contador-ready export
must reproduce. If the code's export doesn't match the § Expected assertions below, the code is
wrong — not the fixture. Numbers are chosen so quantity ratios are clean (no rounding ambiguity);
**internal math keeps full precision, export rounds to 2 dp BRL**.

Currency: all trades USD (Phase-1 is US-only, D12). All BRL values via the per-event `fx_to_brl`.

## Input events (chronological)

| id | type | date | key fields | voided_by |
|----|------|------|------------|-----------|
| x1 | btc_origin | 2026-06-01 | brl_proceeds 33 600.00 · acq_cost_brl 12 000.00 · **gain_brl 21 600.00** · exempt_35k ✓ · in1888_reportable ✓ | — |
| r1 | remittance | 2026-06-02 | brl_amount **33 969.60** · usd_credited 6 000.00 · fx_rate 5.60 · iof 369.60 · wire_fee 0 · fx_provenance "broker contract" | — |
| t1 | trade BUY | 2026-06-03 | NVDA · US · qty 10 · unit_price 100.00 · commission 1.00 · fx_to_brl 5.60 · origin NORMAL | — |
| t2 | trade BUY | 2026-06-10 | NVDA · qty **50** · unit_price 120.00 · commission 1.00 · fx_to_brl 5.70 | **c1** |
| c1 | correction | 2026-06-10 | target t2 · reason "qty typo 50→5" | — |
| t3 | trade BUY | 2026-06-10 | NVDA · qty 5 · unit_price 120.00 · commission 1.00 · fx_to_brl 5.70 · origin NORMAL | — |
| t4 | trade SELL | 2026-07-01 | NVDA · qty 6 · unit_price 130.00 · commission 1.00 · fx_to_brl 5.80 | — |
| d1 | dividend | 2026-09-15 | NVDA · gross 4.00 · foreign_tax_withheld 1.20 (30%) · net 2.80 · fx_to_brl 5.75 | — |
| y1 | year_end_balance | 2026-12-31 | NVDA · qty 9 · price 140.00 · fx_rate 5.50 · price_provenance "yfinance close" · fx_provenance "PTAX 31/12" | — |

`t2` is **voided** by `c1` (correct-never-edit, D10); all derivations skip voided events, so the
live buys are `t1` + `t3`. (`x1` BTC-origin is the cost-base root; an `OPENING_IMPORT` trade is not
exercised in this fixture — its own case lives in a Phase-1 unit test, D11.)

## Derivation walk-through (the math the code must reproduce)

**Weighted-average BRL cost (custo médio, § 3.1) — buy commission capitalized:**
- t1 cost_brl = (10×100 + 1) × 5.60 = 1001 × 5.60 = **5 605.60** (qty 10)
- t3 cost_brl = (5×120 + 1) × 5.70 = 601 × 5.70 = **3 425.70** (qty 5)
- Pre-sell position: qty **15**, total cost **9 031.30**, `avg_cost_brl` = 9 031.30 / 15 = **602.086̄**

**Partial SELL t4 — sell commission reduces proceeds:**
- net_proceeds_brl = (6×130 − 1) × 5.80 = 779 × 5.80 = **4 518.20**
- cost_of_sold_brl = 9 031.30 × (6/15) = 9 031.30 × 0.4 = **3 612.52**
- **`realized_gain_brl` = 4 518.20 − 3 612.52 = 905.68** ← DERIVED, labeled derived in export
- Remaining: qty **9**, basis = 9 031.30 × 0.6 = **5 418.78**, `avg_cost_brl` unchanged 602.086̄

**Dividend d1 (BRL):** gross 4.00×5.75 = **23.00** · withheld 1.20×5.75 = **6.90** · net **16.10**

**31/12 snapshot y1:** usd_value = 9×140 = **1 260.00** · brl_value = 1 260 × 5.50 = **6 930.00**
· unrealized_brl = 6 930.00 − 5 418.78 = **1 511.22**

## Expected assertions (the export must satisfy ALL)

**Position @ 2026-12-31 (NVDA):**
- qty = 9 · avg_cost_brl = 602.09 (2dp) · cost_basis_brl = 5 418.78
- market_value_brl = 6 930.00 · unrealized_pl_brl = 1 511.22

**Tax-year 2026 roll-ups:**
- realized_gain_brl (sum) = **905.68**
- dividends_gross_brl = 23.00 · foreign_tax_withheld_brl = 6.90 · dividends_net_brl = 16.10
- remittance log: 1 row — brl_amount 33 969.60, usd_credited 6 000.00, iof 369.60
- btc_origin: gain_brl 21 600.00, exempt_35k true, in1888_reportable true

**Threshold flags @ 2026-12-31 (D12 roll-ups):**
- us_situs_usd_total = 1 260.00 → estate-tax flag (≥ 60 000) = **false**
- foreign_assets_usd_total = 1 260.00 → CBE flag (≥ 1 000 000) = **false**

**Append-only integrity:**
- t2 present but `voided_by = c1`; excluded from position/avg-cost/roll-up math.
- no UPDATE/DELETE on any event row is required to produce this output (correct-never-edit).

**Provenance present (non-null) on every monetary event:**
- every remittance/trade/dividend/year_end_balance row carries `fx_provenance`; y1 also carries
  `price_provenance`. `realized_gain_brl` exported with a `source = DERIVED` marker.

## Export shape (CSV/JSON)

Two faces, same data:
1. **`events.csv`** — every non-voided event, one row, with all stored fields + `source`/provenance.
2. **`summary.json`** — `{ positions[], realized_gains_brl, dividends{gross,withheld,net},
   remittances[], btc_origin, flags{us_situs_usd, cbe_usd}, generated_for_tax_year }`.

The summary is what the owner hands the contador; `events.csv` is the audit trail behind it.
