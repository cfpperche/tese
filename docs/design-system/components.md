# Components — tese design system

Concrete UI components for the dashboard. All numeric values use `--font-mono` + `tabular-nums`.
Color is restrained: green/red **only** for P&L and day-change; amber **only** for threshold flags.

## Layout

- **App shell:** single column, `max-width: var(--maxw)`, centered. Top bar (app name + data
  freshness "as of HH:MM") and a thin left/top nav (Dashboard · Ledger · Export).
- **No modals for core flows.** Ledger entry is an inline form; this is a quiet tool, not an app
  with chrome.

## Core components

### 1. `PortfolioSummary` (hero)
Total portfolio value (`--fs-xl`, mono) + day change (gain/loss color) + tax-year realized
gains/dividends mini-stats. The one place a big number lives.

### 2. `HoldingsTable`
Columns: Ticker · Market · Instrument · Qty · Avg cost · Price · **Weight %** · **P&L** (color) ·
Day Δ (color) · us_situs badge. Numeric columns right-aligned, mono, tabular. Row hover →
`--surface-2`. No row is clickable to "trade" — read-only.

### 3. `WatchlistPanel`
The thesis universe **including unheld names** (visually distinguished — muted, no weight/P&L).
Quote + day change only. Makes "what I watch vs what I own" legible at a glance.

### 4. `CategoryRollup`
A compact aggregate of the thesis movement (weighted/equal-weight day change across the watchlist).
A single sparkline (Chart.js/uPlot) + the number. No chart junk.

### 5. `LedgerEntryForm`
Tabbed by event type: Remittance · Trade · Dividend · 31/12 Balance · BTC origin. Each field maps
1:1 to a `compliance-tax.md` field. FX-rate field has a helper: *"the rate you actually used"*.
Inline validation; on save, appends an immutable event.

### 6. `ThresholdFlag` (Phase 2)
Amber banner, calm copy: *"US-situs assets crossed US$ 60k — estate-tax reading suggested."*
Dismissible but reappears until acknowledged in settings. Never red, never blocking.

### 7. `ExportPanel`
Pick tax year → preview the summary (positions @31/12 BRL, realized gains, dividends + withholding,
remittance log) → download CSV/JSON. Copy: *"Hand this to your contador."*

### 8. `DataFreshness`
Small faint timestamp + source name ("yfinance · as of 14:32"). Turns to `--flag` color if stale
beyond the poll interval — the staleness is never silent.

## States (every data component must define)

- **Empty:** calm guidance ("Log your first remittance to start the record.").
- **Loading:** skeleton rows, no spinners-as-decoration.
- **Stale:** `DataFreshness` flags it; last-known values shown, clearly dated.
- **Error:** plain message + which source failed; never a blank table.

## Accessibility

- Don't rely on color alone for gain/loss — pair with `+`/`−` sign and arrow glyph.
- WCAG AA contrast on `--text` / `--text-muted` over surfaces (palette chosen to pass).
- Full keyboard nav for the ledger form; focus ring uses `--accent`.
