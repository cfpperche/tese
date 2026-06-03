# Craft floor — anti-AI-slop rules for `/product` visual artifacts

A **brand-agnostic quality floor** applied to `/product`'s authored visual artifacts (Step 02 lo-fi directions, Step 15b hi-fi killer-flow). It catches the recurring "AI-slop" tells — the default-aesthetic choices an LLM reaches for when it isn't anchored to the bound design system.

Two surfaces:
- **Deterministic checks** (`scripts/craft-floor-check.ts`) — 5 mechanically-detectable P0 tells, emitted as JSON findings. The quality-judge consumes the findings (`craft-floor` criterion = `fail` iff `active_p0 > 0`); it does not re-discover them.
- **Judge-only guidance** — 2 tells too false-positive-prone for regex; the judge weighs them semantically.

Scope: judge-units `02-prototype` and `15b-hifi-mood` only. NOT `15a-screen-atlas` (a contract/inventory artifact), NOT `15c-fixture-spec`, NOT steps 01-14. Advisory by default — the floor gates the *quality verdict*, never artifact persistence.

> Rules authored for Agent0. Adapted from the P0 set in Open Design's `craft/anti-ai-slop.md` (`github.com/nexu-io/open-design`, Apache-2.0) — the concept and the specific tells are theirs; the detection logic and triage are Agent0's.

## Deterministic P0 checks (auto-flagged)

Each finding suppresses when the bound `design-systems/<vendor>/DESIGN.md` legitimately declares the value (brand exception).

1. **`default-indigo-accent`** — the exact Tailwind-default indigo/violet ramp used as an accent: `#6366f1`, `#4f46e5`, `#4338ca`, `#3730a3` (case-insensitive). The textbook AI tell. **Suppressed** when the hex appears in the bound DESIGN.md's declared colors, or the artifact uses a declared `var(--token)`. (A legitimately-purple brand — e.g. Linear's `#5e6ad2`/`#7170ff` — is never flagged: those hexes aren't the Tailwind default, and even if a brand declares `#6366f1` the suppression fires.)

2. **`trust-gradient`** — a two-stop `linear-gradient(...)` whose stops are both in the purple→blue / blue→cyan families (the "trust" hero gradient). **Suppressed** when both stops are declared brand tokens. Detection is conservative (clear two-stop purple/blue/cyan only) — bias toward under-flagging.

3. **`emoji-feature-icon`** — emoji used as feature/section icons inside headings (`h1`–`h3`), buttons, or `icon`/`feature`-classed elements. Prescription: monoline SVG with `currentColor`. (Emoji elsewhere in body copy is not flagged.)

4. **`filler-copy`** — `lorem ipsum`, `feature one|two|three`, `placeholder text`, `sample content`. Solve composition structurally, not with filler.

5. **`sans-display-when-serif-bound`** — `h1`–`h3` / hero-title selectors assigning a default sans (or a `font-family` that omits the bound serif) **when** the DESIGN.md binds a serif display/heading font. Only runs when a serif display is actually bound.

## Judge-only guidance (not auto-checked — too noisy for regex)

The judge weighs these semantically; they do not appear in the deterministic JSON.

- **`rounded-card-colored-left-border`** — the canonical "AI dashboard tile" (rounded card + colored left border). Too many legitimate dashboard patterns to auto-flag; the judge calls it when it reads as slop.
- **`invented-metrics`** — unsourced superlatives ("10× faster", "99.9% uptime"). Legitimacy needs semantic context (is there a real source / labelled placeholder?), not a regex.

## Brand exception (how suppression works)

The check is passed the bound `DESIGN.md` path and harvests: every `#[0-9a-fA-F]{3,8}` hex literal, every `--custom-prop: value` declaration, and whether a serif display/heading font is bound. A color finding is **suppressed** when its literal exactly matches a declared hex or the artifact references a declared `var(--token)`. Over-collecting declared colors only makes suppression more lenient (the safe direction for an advisory).
