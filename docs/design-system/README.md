# tese — Design System

The visual contract for `tese`: a **calm financial instrument** for a capable owner. The design
job is to make precise numbers legible and to keep the tool's *posture* (decision-support, never
advice) visible in every surface.

## Principles

1. **The data is the design.** Sparse chrome, generous whitespace, no decorative gradients or chart
   junk. A well-set table of numbers beats a trading HUD.
2. **Color carries meaning, nothing else.** One calm brand accent (`--accent`); green/red reserved
   strictly for P&L and day-change; amber strictly for threshold flags. If everything is colored,
   nothing means anything.
3. **Numbers are monospace + tabular.** Every monetary/numeric value uses `--font-mono` with
   `tabular-nums` so columns align and figures read exactly.
4. **Calm over urgent.** No hype, no manufactured urgency — the opposite of the BTC noise this tool
   exists to quiet. Flags inform; they don't alarm.
5. **State honesty.** Empty, loading, **stale**, and error states are first-class. Data freshness is
   always visible; staleness is never silent.

## Files

- `tokens.css` — the single source of truth for color, type, spacing, radius. Frontend imports it;
  nothing hardcodes these values.
- `components.md` — the component catalog (summary, holdings table, watchlist, ledger form, export,
  flags) with required states + a11y notes.

## How it's consumed

The Phase-1 vanilla-JS frontend `@import`s `tokens.css` and builds the components in
`components.md`. No build step, no framework — tokens + plain CSS + Chart.js. When/if the frontend
grows, the tokens stay the contract.

## Cross-references

- `../brand-book.md` — voice, name, visual posture this system implements.
- `../system-design.md` — the data these components render.
