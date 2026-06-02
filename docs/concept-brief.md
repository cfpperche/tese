# Concept Brief — tese

**Working name:** `tese` · **Type:** personal tool (single user, local-first) · **Owner:** Carlos Perche
**Status:** foundation draft · **Date:** 2026-06-02

## One-liner

A personal **decision-support + compliance ledger** for investing abroad from Brazil — it
reconciles the thesis you watch with the portfolio you hold, and from the very first remittance
it captures every field the Brazilian tax authority (and Bacen, and US estate rules) will later
demand. Decision-support, never advice; read-only, never trading.

## Why this exists (the gap)

The owner is moving from BTC into global tech equities (US core; China/HK and Korea as
satellites), holding directly through an international broker (IBKR) to reduce dependence on
Brazilian brokers. That structure is achievable from Brazil but **does not remove the Brazilian
filing/tax burden** — it shifts the burden of record-keeping onto the investor.

Two real gaps, neither covered by existing apps:

1. **The reconciled view.** Brokerage apps show only what you hold; market apps show only quotes.
   Nothing shows *"what I watch" × "what I own"* — the thesis universe (including names not yet
   held) next to the real portfolio with weight and P&L.
2. **The compliance ledger.** The Lei 14.754/2023 regime taxes foreign financial gains annually
   (~15%), and Bacen's CBE kicks in above US$ 1M. Both require a year-round trail: remittance
   dates + FX rates, cost basis, dividends, foreign tax withheld, 31/12 balances. Brokers don't
   produce a Brazil-shaped record. Today this lives in fragile spreadsheets. **This is the
   differentiator** — the tool is a Brazil-aware ledger first, a dashboard second.

## What it is / what it is not

**We are:**
- A local-first instrument that *surfaces* data so a capable human decides.
- A **tax/compliance ledger** that persists, from aporte #1, the exact fields IRPF + CBE need.
- Multi-market aware (US core; China via HK/ADR/Stock-Connect; Korea via KRX/ETF — satellites).
- Broker-pluggable: manual holdings first, **IBKR Web API** as the live source-of-truth later.

**We are not:**
- Not advice. No buy/sell signals, scores, rankings, or recommendations of any kind.
- Not a trade-execution tool. Read-only, forever.
- Not a tax *engine* that files for you — it captures and organizes the record; a contador files.
- Not a product for other users (v1): no auth, no multi-tenant, no billing, no marketing surface.

## Primary user

One user — the owner. Senior IC / builder, fully capable of his own investment decisions, wants
**autonomy from Brazilian brokers** and **control of his own tax record** rather than depending on
a broker's informe. Technical enough to run a local Python app and edit a YAML/`.env`.

## Core jobs-to-be-done

1. *"Show me how my thesis (the AI/tech category) is moving — including names I don't yet hold."*
2. *"Show me my real portfolio — positions, weight, P&L — reconciled against that thesis."*
3. *"Capture, from the first remittance, everything my contador and the IRPF/CBE will need —
   so April is a query, not an archaeology dig."*
4. *"Warn me when I cross a threshold that changes my obligations"* (US$ 60k US-situs → estate-tax
   planning; US$ 1M abroad → CBE annual; dividend withholding awareness).

## Strategic posture (folded in from research)

- **Broker:** IBKR primary (US + HK/China + KRX + multi-currency, global custody); Schwab
  International as a possible future US-only secondary. Avoid CFD/forex/bonus platforms; heed
  CVM's alerts on unauthorized foreign solicitation.
- **Instrument order:** broad ETFs before single names; China kept as a small satellite (VIE /
  regulatory risk); **UCITS (Irish-domiciled) ETFs** flagged once US-situs assets approach the
  US$ 60k estate-tax line.
- **FX discipline:** formal remittance from an account in the owner's own CPF (never third-party);
  log spread, IOF, SWIFT fee, date, rate every time.

## Success signal (North Star)

**Filing-readiness:** at any moment, the owner can export a complete, contador-ready record of
every position, remittance, dividend, and 31/12 balance for the year — zero manual reconstruction.
Everything else (the dashboard, the thesis view) serves decisions; this serves sleep.

## Cross-references

- `prd/v1.md` — scoped requirements + user stories
- `compliance-tax.md` — the Brazil/US obligation map + the exact fields to persist
- `system-design.md` — architecture + the ledger data model
- `roadmap.md` — phased build (mirrors the owner's investment phases)
- `specs/001-foundation/spec.md` — the engineering foundation child
