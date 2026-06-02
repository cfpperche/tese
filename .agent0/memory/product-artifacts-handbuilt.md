---
name: Product artifacts hand-built, not /product-generated
description: The docs/ foundation was authored manually from the /product structure;
  the skill was deliberately NOT invoked — do not re-run it
metadata:
  type: feedback
  created_at: '2026-06-02T13:55:00-03:00'
  last_accessed: '2026-06-02'
  confirmed_count: 0
---
The `docs/` foundation (concept-brief, prd, compliance-tax, system-design, roadmap, brand-book,
design-system) was **hand-authored based on the `/product` skill's step structure**, but `/product`
was **deliberately not invoked**.

**Why:** `/product` is a product-*launch* foundation generator (15 steps). Even with
`--skip-prd --skip-brand` it forces GTM, pricing, cost, legal, roadmap-as-business, brand — exactly
the launch machinery this **personal tool** does not want. The owner asked for "a lighter /product,
personal-tool first, no marketing/pricing". The faithful answer was to take only the relevant steps
(branding, design-system, system-design, PRD, roadmap) + a re-proposed **compliance-tax** artifact
(the real differentiator) and drop GTM/cost/OST/validation/visual-contract.

**How to apply:**
- Do **not** run `/product` against this repo to "complete" the foundation — the dropped steps are
  intentional, not gaps. Extend the docs manually.
- `compliance-tax.md` replaced step-09 legal as a Brazil-tax obligation→field map; it is the
  source-of-truth that drives the ledger schema in `system-design.md`.
- The tax-ledger framing (capture IRPF/CBE/estate-tax fields from aporte #1) was a scope shift
  introduced mid-session from the owner's research input — it is the **core** of the product, not a
  feature. See [[owner-investment-context]].
