# Compliance & Tax — the obligation→field map (Brazil resident, foreign investing)

**Status:** draft · **Date:** 2026-06-02
**Posture:** This document is the *requirements source* for the ledger schema in `system-design.md`.
It is educational, **not** individual tax advice. Rates/rules change (notably the 2025 IOF reform)
— **every number here must be reconfirmed with a contador** before relying on it. The tool captures
and organizes the record; **a contador computes and files the official liability.**

## Why the ledger is the product

Holding global equities directly from Brazil shifts record-keeping onto the investor. The Brazilian
filings below all demand a **year-round trail** that brokers don't emit in a Brazil-shaped form. If
the data isn't captured *as events happen*, April becomes archaeology. So the ledger is designed
backwards **from these obligations**.

## A. Obligations map

### 1. IRPF — financial investments abroad (Lei 14.754/2023)
- Gains/income from foreign financial applications are taxed **annually**, ~**15%**, reported in
  the annual DAA (separate from other income).
- Positions declared in **"Bens e Direitos"** at **31/12** value (BRL).
- **Implication for the ledger:** need cost basis in BRL, realized gains per disposal, dividends,
  foreign tax withheld, and a **31/12 balance snapshot** per position.

### 2. IRPF — the BTC→equities *entry* event (capital gains on crypto)
- Selling crypto: monthly disposals **≤ R$ 35.000 are exempt**; above, ~15%+ on the *gain*, DARF
  (código 4600) by the last business day of the following month.
- Foreign-exchange crypto activity (Binance) **> R$ 30.000/month** → report to RFB (IN/RFB 1888)
  **even when exempt**.
- **Implication:** the ledger should record the **BTC disposal** (date, BRL proceeds, gain,
  exempt? y/n) as the *origin* of the foreign capital — it's the cost-base root of everything after.

### 3. Bacen — CBE (Capitais Brasileiros no Exterior)
- **Annual** CBE when total assets abroad ≥ **US$ 1,000,000** on 31/12.
- **Quarterly** CBE when ≥ **US$ 100,000,000**.
- **Implication:** track **total foreign assets in USD** and flag the US$ 1M line. (Far off for a
  ~US$ 6k start, but the flag is cheap and the data is already there.)

### 4. US — dividend withholding (no BR–US tax treaty)
- US-source dividends to a non-resident alien are withheld at **30%** (no treaty relief for Brazil).
  **W-8BEN** is filed at onboarding to certify non-US status (avoids higher backup withholding).
- Realized **capital gains** are **not** taxed by the US for non-resident aliens — taxed in Brazil.
- **Implication:** record **foreign tax withheld** per dividend (feeds IRPF; possible offset logic
  is the contador's call, but the *data* must exist).

### 5. US — estate tax (the sleeper)
- For non-resident aliens, **US-situs assets** (US-incorporated stocks/ETFs) enter the US estate-tax
  base; a return is required when US-situs assets exceed **US$ 60,000**.
- Mitigation studied above that line: **UCITS (Irish-domiciled) ETFs** (non-US situs) instead of
  US-domiciled ETFs, joint accounts, succession planning.
- **Implication:** the ledger must classify each holding as **US-situs or not** and roll up the
  US-situs USD total, with an alert near US$ 60k.

## B. The fields to persist (drives the schema)

Per **remittance (câmbio):** date · BRL amount · USD credited · FX rate · IOF · SWIFT/wire fee ·
source account (own CPF) · broker destination.

Per **trade (buy/sell):** date · ticker · exchange/market (US/HK/KR) · currency · instrument
(stock/ETF/ADR/UCITS) · **us_situs** (bool) · quantity · unit price · commission · FX-to-BRL on
trade date · BRL cost/proceeds · realized gain (on sell).

Per **dividend:** date · ticker · gross amount · currency · **foreign_tax_withheld** · net ·
FX-to-BRL.

Per **position, at 31/12:** ticker · quantity held · year-end price · year-end FX · **BRL value**
(the "Bens e Direitos" figure) · USD value (feeds CBE + US-situs roll-ups).

Per **BTC origin event:** date · BRL proceeds · acquisition cost · gain · exempt(≤R$35k)? ·
IN-1888-reportable(>R$30k)?

Derived/roll-up: total foreign assets USD (CBE flag) · total **US-situs** USD (estate flag) ·
realized gains for tax year · dividends + withholding for tax year.

## C. Outputs the tool must produce

1. **Contador-ready export** (per tax year): CSV/JSON of all events + a human summary
   (positions @31/12 in BRL, realized gains, dividends + withholding, remittance log).
2. **Threshold flags:** US-situs → US$ 60k; total abroad → US$ 1M.
3. **Audit trail:** every figure traceable to its source event + the FX rate used.

## D. Boundaries (what the tool deliberately does NOT do)

- Does **not** file anything, with anyone.
- Does **not** assert the official tax owed — it provides *informational* roll-ups; the **contador**
  produces the binding numbers (offsets, carry-forwards, exemptions are their domain).
- Does **not** advise on instrument choice for tax reasons — it *surfaces* the US-situs / UCITS
  consideration as information; the decision (and its tax planning) is the owner's + contador's.
- Does **not** track FX rates authoritatively — it records the rate **the owner actually used** on
  each event (the legally relevant figure), not a market reference rate.

## E. Open items to confirm with a contador

- Post-2025 IOF reform: exact IOF on investment remittance (was ~1,1%) — reconfirm.
- Whether/how 30% US dividend withholding offsets BR tax under current Receita guidance.
- Exact 31/12 valuation rule (price source, FX source) the Receita expects for "Bens e Direitos".
- IN/RFB 1888 vs the newer crypto reporting regime status for the BTC disposal month.
