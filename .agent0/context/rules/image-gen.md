---
paths:
  - ".mcp.json"
  - ".mcp.json.example"
  - ".agent0/skills/image/**"
  - "assets/**"
---

# Image generation

Opt-in capacity for AI image generation via fal.ai. The `/image` skill produces both **throwaway UI mockups** (FLUX schnell, ~$0.003/img) and **durable brand assets** (gpt-image-2 or Imagen 4 Ultra, $0.04-0.20/img) via a single provider — fal.ai aggregates FLUX, OpenAI gpt-image, Google Imagen, and ~1000 other models under one HTTP API. The skill is intentionally thin: tier flag selects the model, output path is mechanical, cost is printed before every call. Activation is setting `FAL_KEY` in env — generation POSTs to the fal.run REST API (the `.mcp.json` fal-ai recipe is optional, discovery-only; see § Activation). Consumer projects that never set the key pay zero cost.

The default provider is the **official fal.ai hosted MCP** (`https://mcp.fal.ai/mcp`), maintained by the fal.ai team. Community-maintained alternatives are documented for consumer projects that prefer fully-local/stdio MCPs or need a fallback if the hosted endpoint is unreachable.

## Activation

Three steps, one-time per consumer project:

1. **Copy + uncomment the recipe.** `cp .mcp.json.example .mcp.json` (or merge into existing). Remove the `//` markers on the `fal-ai` block. The block uses HTTP transport — distinct from the stdio blocks for Playwright/Chrome DevTools/DBHub/Next-devtools.

2. **Set `FAL_KEY` in your shell or `.env`.** Sign up at [fal.ai](https://fal.ai) → Dashboard → API Keys to mint one. The key has a `<uuid>:<secret>` shape; never commit it. The `.mcp.json.example` uses `${FAL_KEY}` indirection so a populated `.mcp.json` doesn't carry the literal.

3. **Restart the session.** MCPs load at session start, not hot-reloaded.

**Codex CLI activation is the same shape.** The skill is multi-runtime (spec 121): its canonical body lives at `.agent0/skills/image/`, discoverable as `$image` in Codex via the `.agents/skills/image` symlink. For the discovery MCP, set `[mcp_servers.fal-ai] enabled = true` in `.codex/config.toml` (copy from `.codex/config.toml.example` — same `url = "https://mcp.fal.ai/mcp"` + `bearer_token_env_var = "FAL_KEY"`), set `FAL_KEY`, restart Codex. Generation (curl path) needs only `FAL_KEY` in either runtime — the MCP is optional (next paragraph).

After restart, `/image --tier=<draft|brand-text|brand-photo> "<prompt>"` (Claude Code) or `$image ...` (Codex) is available. Without activation, the skill errors clean with a pointer back to this section.

**MCP recipe is optional for generation (since spec 088, 2026-05-25).** `gen.sh exec` calls the fal.run REST endpoint directly with `FAL_KEY`, bypassing the MCP transport — so a consumer project that sets `FAL_KEY` but skips the `.mcp.json` recipe still gets full generation capability. The recipe remains valuable for **agent-side discovery tools** (`search_models`, `get_model_schema`, `get_pricing`, `recommend_model`) — skip it only if your consumer project has no use for those.

## Tier table

Three tiers, mechanical mapping to model + output path + approx cost. Pricing as of 2026-05-24 (refresh discipline: § *Pricing refresh*).

| Tier | Model | Default ext | Output path | Approx cost | Best for |
|---|---|---|---|---|---|
| `draft` | `fal-ai/flux/schnell` | `.jpg` | `assets/generated/mockups/<YYYY-MM-DD>-<slug>.jpg` | ~$0.003/img | Prototype UI, placeholder mockups, high-volume throwaway |
| `brand-text` | `fal-ai/gpt-image-2` | `.png` | `assets/brand/<slug>.png` | $0.04-0.20/img | Logos, banners, anything with crisp typography |
| `brand-photo` | `fal-ai/imagen4/ultra` | `.png` | `assets/brand/<slug>.png` | ~$0.06/img | Hero images, photo-real illustrations |

Extension is tier-derived (matches the model's default content-type). FLUX schnell returns JPEG; OAI/Imagen models return PNG. Verified empirically for FLUX in the 2026-05-24 dogfood; brand-tier formats are documented assumption.

### Aspect ratios

Optional `--aspect=square|landscape|portrait` flag (default `square`). Maps to fal.ai's `image_size` enum:

| Aspect | Enum | Dimensions | Best for |
|---|---|---|---|
| `square` (default) | `square_hd` | 1024×1024 | Avatars, icons, square mockups |
| `landscape` | `landscape_16_9` | 1024×576 | Banners, hero images, blog covers |
| `portrait` | `portrait_16_9` | 576×1024 | Mobile screens, vertical posters |

The model IDs are addressed via the MCP's `search_models` / `recommend_model` tools; if any ID has shifted in fal.ai's catalog, the skill surfaces the current ID at first call and the table here gets bumped on next refresh.

## Brand-tier prompt composition

Image generators interpret vague prompts toward the **stock median** of their training distribution — "a banner" becomes the generic SaaS banner, not your brand. This is the silent failure mode for `brand-text` and `brand-photo` calls; the output looks plausibly competent but quietly off-brand, and the drift is only caught at human review (V6-style eyeball, which is expensive and easy to skip).

The discipline: **brand-tier prompts should compose from a consumer-local brand contract** — a written document declaring palette, typography, visual language, composition rules, and anti-patterns. The contract turns prompt-writing from interpretation into transcription; the failure mode shifts from invisible drift into visible "the contract was wrong" (and a wrong contract is editable; an undocumented vibe is not).

**Agent0 ships no template for this contract** — palette and visual language are quintessentially consumer-local (different products, different brands, no honest one-size-fits-all). The convention is path + presence only:

- Common location: `docs/brand/styleguide.md` (or `docs/brand/<sub-brand>.md` for multi-brand consumer projects).
- At call time for `brand-text` / `brand-photo`: if a contract document exists, read it first and compose the prompt from its § *Prompt template* section. If it doesn't exist, the prompt is ad-hoc — flag this in the call summary so the human knows what they're trusting.
- The contract document treats the consumer project's source-of-truth tokens (e.g. CSS variables, design-system JSON) as the **oracle**; the contract itself transcribes them. Disagreement between oracle and contract → oracle wins, contract is out of date. No automation; refresh discipline is manual and owner-binding.

`draft` tier is exempt — mockups are throwaway by definition; ad-hoc prompts are correct-shaped there.

## Storage policy

Path-based split — durability is signalled by the tier flag at call time:

- `assets/generated/mockups/*` → **gitignored** (`.gitignore` rule + `!.gitkeep` sentinel exclusion). Mockups are throwaway by design; the manifest is the historical record, not the PNGs themselves.
- `assets/brand/*` → **git-tracked**. Brand assets are durable; their history is part of the project memory.
- `assets/generated/.manifest.jsonl` → **git-tracked**. One JSONL line per `/image` call (across all tiers), so the cost + prompt history survives even when the mockup PNGs don't.

Promotion mockup → brand asset is a manual `git mv assets/generated/mockups/<file> assets/brand/<file>` + commit. Rare and explicit by design.

A consumer project that wants ALL image storage gitignored adds `assets/brand/*` to its own `.gitignore`. A consumer project that wants ALL tracked removes the `assets/generated/mockups/*` line. Both are local overrides; the harness default is the split above.

## Error on omitted tier

`/image "<prompt>"` without a `--tier` flag errors clean. No silent default. The error message lists the three tiers verbatim so the user picks deliberately:

```
/image error: --tier is required. Pick one:
  --tier=draft       cheap mockup       (~$0.003/img, FLUX schnell)
  --tier=brand-text  premium with text  ($0.04-0.20/img, gpt-image-2)
  --tier=brand-photo premium photo-real (~$0.06/img, Imagen 4 Ultra)
```

The same fail-explicit shape applies when `FAL_KEY` is unset or `.mcp.json` is missing the `fal-ai` block — pointer back to § *Activation*, no implicit fallback to a different provider.

Rationale: cost mistakes accumulate silently; quality mistakes are visible and self-correcting. The asymmetry favours fail-explicit — consistent with the contract-not-promise discipline in `.agent0/context/rules/delegation.md` § *Why DONE_WHEN exists*.

## Naming convention

Filenames are derived from the prompt: `<YYYY-MM-DD>-<kebab-first-5-words>.png` for draft tier, `<kebab-first-5-words>.png` for brand tiers (no date prefix because brand assets are durable and the file history carries the date). Collision resolution: append `-2`, `-3`, etc. — mirrors the `reminders.yaml` id-collision pattern in `.agent0/context/rules/reminders.md`.

`--name=<explicit-slug>` overrides the auto-derivation when the prompt produces a messy or non-ASCII slug. Example: `/image --tier=brand-text --name=hero-banner "Marca da empresa em estilo aquarela"` writes to `assets/brand/hero-banner.png`.

## Manifest shape

`assets/generated/.manifest.jsonl` carries one JSONL line per `/image` call. Schema:

| Field | Shape | Source |
|---|---|---|
| `ts` | ISO-8601 UTC | Skill script at invocation time |
| `session_id` | string or null | Claude Code session id from `tool_use_id` context |
| `tier` | enum: `draft` / `brand-text` / `brand-photo` | `--tier` flag |
| `model` | string | Resolved fal.ai endpoint id |
| `cost_usd` | float, approx | From `references/tier-pricing.md` table |
| `prompt` | string | The full prompt verbatim |
| `output_path` | string | Relative to repo root |
| `dimensions` | string | e.g. `1024x1024` |

The four core fields (`ts`, `session_id`, `model`, `cost_usd`) align with `.agent0/delegation-audit.jsonl` and `.agent0/secrets-audit.jsonl` field naming so cross-domain forensics queries work: `jq -c 'select(.session_id == "X")' assets/generated/.manifest.jsonl .agent0/delegation-audit.jsonl` returns every image call + every Agent dispatch in that session.

The manifest is append-only by convention. No retention cap in v1 — image-gen frequency is much lower than delegation events, so growth is acceptable. If forensics becomes painful, a future spec adds rotation.

## Override marker

`# OVERRIDE: image-gen-exempt: <reason ≥10 chars>` skips the pre-call cost confirmation in batch scripts where the operator already accepted the cost. Same shape as the project's other gates (`delegation.md`, `secrets-scan.md`). The reason text is the audit trail — write something a future maintainer can grep. "skip" / "bypass" / "ok" are not reasons.

Not enforced by a hook in v1 — the skill itself honours the marker by short-circuiting the confirmation prompt. The audit log captures the marker reason in the manifest line's optional `override_reason` field.

## Trust posture

The default — fal.ai's official hosted MCP at `https://mcp.fal.ai/mcp` — is maintained by the fal.ai team and tracks their catalog directly. Free at the MCP layer; you pay only for model inferences. Network-dependent: if the endpoint is unreachable, the MCP fails to register and `/image` errors at call time.

**Documented fallbacks** for consumer projects that want a fully-local/stdio MCP or need an offline-capable alternative:

| Package | Source | Notes |
|---|---|---|
| `piebro/fal-ai-mcp-server` | [npm](https://www.npmjs.com/package/fal-ai-mcp-server) · [GitHub](https://github.com/piebro/fal-ai-mcp-server) | Single individual maintainer, MIT, most-featured community option (built-in cost-estimation tools). |
| `@monsoft/mcp-fal-ai` | [npm](https://www.npmjs.com/package/@monsoft/mcp-fal-ai) | 8 tools, dual transport (stdio + SSE), zero deps on fal.ai SDK |
| `mcp-fal-ai-image` | [npm](https://www.npmjs.com/package/mcp-fal-ai-image) | Image-only variant; lighter scope |
| `lansespirit/image-gen-mcp` | [GitHub](https://github.com/lansespirit/image-gen-mcp) | NOT fal.ai-backed — multi-provider (OAI gpt-image + Imagen 4 direct). Reach for this if a consumer project wants to bypass fal.ai entirely. |

Swap is a `.mcp.json` edit (replace the `fal-ai` HTTP block with the chosen alternative's stdio block) + same `FAL_KEY` env var. The skill's tier→model resolution stays identical because all four alternatives expose the same underlying fal.ai endpoints.

## Pricing refresh

The tier-pricing table in `.agent0/skills/image/references/tier-pricing.md` is date-stamped and prefixed `approx`. Refresh discipline: a quarterly entry in `.agent0/routines/` (per `.agent0/context/rules/routines.md`) re-runs the lookup against fal.ai's pricing page. If pricing has moved >20% on any tier, update the table, bump the date stamp, regenerate `references/tier-pricing.md`.

Skill scripts read the table at call time; updates apply on next invocation without a session restart.

## Cross-references

- `.mcp.json.example` / `.codex/config.toml.example` — `fal-ai` MCP server block (HTTP transport, `bearer_token_env_var = "FAL_KEY"`)
- `.agent0/context/rules/secrets-scan.md` — `FAL_KEY` handling; the `<uuid>:<secret>` shape may not match gitleaks default rules (see § *Gotchas*)
- `.agent0/context/rules/delegation.md` § *Why DONE_WHEN exists* — contract-not-promise frame motivating pre-call cost printing
- `.agent0/skills/image/` — skill implementation (canonical; symlinked into `.claude/skills/` + `.agents/skills/` per spec 121)
- `.agent0/skills/image/references/tier-pricing.md` — static cost table

## Gotchas

- **MCP `run_model` is broken upstream — generation uses curl.** As of 2026-05-25, `mcp__fal-ai__run_model` against the official hosted MCP (`https://mcp.fal.ai/mcp`) hangs ≥990s server-side on `gpt-image-2` (verified via 21,655 `"No token data found"` poll messages in the CC MCP-client log over a 7-hour session). CC's MCP-client times out at ~6 min and mis-renders the timeout as the canonical `"The user doesn't want to proceed with this tool use"` string — making the failure look like a permission problem. The `/image` skill now routes generation through `gen.sh exec` (REST POST to `https://fal.run/<model>` with `Authorization: Key $FAL_KEY`) instead. The MCP server is closed-source (Vercel-hosted stateless API; no upstream fix path); the curl path is the canonical generation method until further notice. Full diagnosis: `docs/specs/088-image-skill-curl-exec/`.
- **gpt-image-2 has a min-pixel floor that drifts landscape/portrait dims.** The model's input schema declares `total pixels between 655,360 and 8,294,400`. `landscape_16_9` (1024×576 = 589,824 px) and `portrait_16_9` (576×1024 = 589,824 px) are below the floor; the model upsamples to **1088×608** (661,504 px). `square_hd` (1024×1024 = 1,048,576 px) sits above the floor — no drift. `gen.sh exec` auto-downscales via `ffmpeg -vf scale=...` when actual returned dims ≠ expected (graceful-degrade: emits `image-skill-advisory:` if ffmpeg is absent, leaves file at upsampled dims). FLUX schnell + Imagen 4 Ultra do not enforce this floor.
- **Hosted MCP is network-dependent.** Unlike the stdio recipes that spawn locally, `https://mcp.fal.ai/mcp` requires a session-start HTTPS handshake. If fal.ai's endpoint is down or the consumer project is behind a strict egress firewall, the MCP doesn't register — discovery tools become unavailable, but generation still works (curl path bypasses MCP entirely; only `FAL_KEY` env is required). The community-package fallback (`piebro/fal-ai-mcp-server` via `npx -y`) is offline-capable if discovery matters.
- **MCP tool surface does NOT reload on mid-session `.mcp.json` edits.** `claude mcp list` reports `✓ Connected` immediately after `.mcp.json` changes (it re-handshakes on demand), BUT the `mcp__fal-ai__*` tools available to the agent are baked in at SessionStart and stay frozen for the session's lifetime. A session that boots without the `fal-ai` block (or with a broken block) cannot get tool access by fixing the file mid-flight — it MUST restart. Verified empirically 2026-05-24 during initial `/image` activation.
- **`Authorization` header shape differs MCP vs REST.** MCP uses `Authorization: Bearer ${FAL_KEY}` (per fal.ai's official MCP setup). The REST API at `fal.run/fal-ai/<model>` uses `Authorization: Key $FAL_KEY` — different prefix word, same key value. Consumer projects adapting the skill to a curl-fallback path must use `Key`, not `Bearer`. Verified empirically 2026-05-24.
- **HTTP transport is the first such recipe in `.mcp.json.example`.** All 4 existing recipes (Playwright, Chrome DevTools, DBHub, Next-devtools) use stdio (`command`/`args`). The `fal-ai` block uses HTTP (`type: "http"`, `url`, `headers`). Don't pattern-match the wrong shape — the canonical key is `type`, not `transport` (verified empirically against `claude mcp add --transport http ...` which writes `"type": "http"` to JSON despite the CLI flag spelling).
- **fal.ai key shape may not match gitleaks default rules.** Unlike OpenAI's `sk-*` or AWS's `AKIA*`, fal.ai keys (`<uuid>:<secret>`) are pattern-distinct. The first activation should test by writing the key to a scratch file and running `gitleaks detect --no-banner` against it — if not caught, add a custom rule to `.githooks/gitleaks.toml`. Mitigated meanwhile by the `${FAL_KEY}` indirection in `.mcp.json.example`.
- **Pricing drift is real.** fal.ai changes prices occasionally. The `references/tier-pricing.md` table is a static snapshot; refresh quarterly via the routine. If the date stamp is >180 days old, treat the displayed cost as a lower bound and verify via fal.ai's current pricing page.
- **Cost runaway from delegated sub-agents.** A sub-agent calling `/image` in a loop is not caught by `.agent0/hooks/delegation-verify.sh` — that validator gates on prod-vs-test classification at close, not on cost. v1 ships with pre-call estimate as the only signal. If empirical observation shows drift, a future spec adds a per-session call counter.
- **Mockup PNGs are gone after `git clean -fdx`.** The `.gitignore` rule means `assets/generated/mockups/*` won't be in git history. The manifest survives (`assets/generated/.manifest.jsonl` is tracked), so prompt + cost + date stay grepable, but the actual PNG is lost. Promotion to `assets/brand/*` is the way to keep one.
- **Promotion is manual.** Mockup → brand asset is `git mv`. No automation. Acceptable — promotion is rare and the explicit step is the correct cognitive break.
- **`.mcp.json` is secret-adjacent.** `FAL_KEY` indirection is the right pattern; never commit a populated `.mcp.json` with literal keys. Same caveat as the DBHub recipe's `DATABASE_URL`.
- **No NSFW filtering at the skill layer.** fal.ai + the underlying providers (OpenAI / Google) enforce their own content policies at the model level. The skill does not re-implement filtering; if a prompt is rejected by the provider, the MCP returns an error and the skill surfaces it verbatim.
- **Sync-harness propagation for the directory tree.** `assets/.gitkeep`, `assets/brand/.gitkeep`, etc. ship to consumer projects via `harness-sync.sh` as part of the standard manifest. The PNG content under `assets/` is NOT synced — content is per-consumer by design (same posture as `.agent0/memory/`).
