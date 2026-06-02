---
name: image
description: AI image generation via the fal.ai REST API (opt-in). Use when the user wants to produce a mockup, brand asset, or hero image for the project. Three tiers cover the cost/quality spectrum - draft (FLUX schnell, ~$0.003/img, jpg, throwaway), brand-text (gpt-image-2, $0.04-0.20/img, png, crisp typography), brand-photo (Imagen 4 Ultra, ~$0.06/img, png, photo-real). Tier flag is REQUIRED - omitted tier errors with the three options. Optional --aspect=square|landscape|portrait (default square) sets image_size. Output paths are mechanical (draft → gitignored assets/generated/mockups/, brand-* → tracked assets/brand/), extension matches tier's default content-type. Every call prints estimated cost BEFORE generation fires. Activation - set FAL_KEY in env (generation needs only the key; the fal-ai MCP recipe is optional, discovery-only). See .agent0/context/rules/image-gen.md.
argument-hint: <--tier=draft|brand-text|brand-photo> [--aspect=square|landscape|portrait] [--name=<slug>] "<prompt>"
license: MIT
compatibility: Compatible with any agentskills.io-compatible runtime (Claude Code, OpenAI Codex, and ~35 others). Generation is runtime-neutral (bash + curl + jq against the fal.run REST API); requires the FAL_KEY env var + network. The fal-ai MCP (hosted at mcp.fal.ai/mcp) is optional — it surfaces model-discovery tools under each runtime's own namespace. No Python; ffmpeg optional for dimension reconciliation.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.3"
---

# /image — AI image generation

Generate images via the fal.ai REST API. Opt-in capacity — consumer projects that never set `FAL_KEY` pay zero cost. The skill is a thin wrapper: it parses the tier flag, derives the output path, prints the estimated cost, then delegates to `gen.sh` (which POSTs to the fal.run REST endpoint via the shared `.agent0/tools/fal-rest.sh` — NOT the MCP; see spec 088 for why). Cost discipline: every call prints `estimated: $X.XXX for <model> at <resolution>` BEFORE generation fires, so a parent agent or human can ctrl-c if the estimate is wrong-shape.

See `.agent0/context/rules/image-gen.md` for the full capacity rule (activation, tier semantics, storage policy, manifest shape, override marker, trust posture, community fallbacks). This SKILL.md documents the invocation surface only.

## Argument parsing

User invokes as `/image <--tier=...> [--name=<slug>] "<prompt>"`. The raw argument string is `$ARGUMENTS`. Parse it yourself: extract `--tier=<value>`, optional `--name=<value>`, and the prompt (the remaining non-flag tokens, typically a quoted string). Do not rely on `$1` / `$2` — order is flag-then-prompt OR prompt-then-flag, both work.

Required flag:

- `--tier=draft` — `fal-ai/flux/schnell`, ~$0.003/img, returns JPEG, output to `assets/generated/mockups/<YYYY-MM-DD>-<slug>.jpg` (gitignored)
- `--tier=brand-text` — `fal-ai/gpt-image-2`, $0.04-0.20/img, returns PNG, output to `assets/brand/<slug>.png` (tracked)
- `--tier=brand-photo` — `fal-ai/imagen4/ultra`, ~$0.06/img, returns PNG, output to `assets/brand/<slug>.png` (tracked)

Optional flags:

- `--aspect=square|landscape|portrait` — image aspect ratio (default `square`). Maps to fal.ai's `image_size` enum: square→`square_hd` (1024×1024), landscape→`landscape_16_9` (1024×576, ideal for banners/heroes), portrait→`portrait_16_9` (576×1024, ideal for mobile/vertical).
- `--name=<slug>` — override the auto-derived slug. Use when the prompt produces a messy or non-ASCII filename. Kebab-case required (`^[a-z][a-z0-9-]*$`); script errors if invalid.

If `--tier` is missing, error with the three-option message:

```
/image error: --tier is required. Pick one:
  --tier=draft       cheap mockup       (~$0.003/img, FLUX schnell)
  --tier=brand-text  premium with text  ($0.04-0.20/img, gpt-image-2)
  --tier=brand-photo premium photo-real (~$0.06/img, Imagen 4 Ultra)
```

If `FAL_KEY` is unset OR `.mcp.json` is missing the `fal-ai` block, error with a one-screen message pointing at `.mcp.json.example` and `.agent0/context/rules/image-gen.md` § *Activation*. No silent fallback.

## Invocation flow

1. **Parse args.** Validate `--tier`, extract prompt, resolve `--name` or auto-derive (`kebab(first 5 words)`).
2. **Resolve model + cost.** Read tier → model endpoint and approx cost from `.agent0/skills/image/references/tier-pricing.md`. Compute output path.
3. **Print cost estimate.** Emit `estimated: $X.XXX for <model> at <dims>` to stdout BEFORE the generation call. This is the contract surface; do not skip. (Done by `gen.sh prepare`.)
4. **Invoke `gen.sh exec`.** Pass the JSON envelope emitted by `prepare` to `bash .agent0/skills/image/scripts/gen.sh exec --envelope='<json>'`. The helper POSTs to `https://fal.run/<model>` with `Authorization: Key $FAL_KEY`, downloads the returned image to `output_path`, and on gpt-image-2 dim drift auto-downscales via `ffmpeg` (or emits an advisory if ffmpeg is absent). Generation goes through REST curl, NOT the fal-ai MCP's `run_model` tool — see § *Notes* for the hybrid rationale and spec 088 for the diagnosis. Collision suffix (`-2`, `-3`, ...) is applied at `prepare` time.
5. **Append manifest.** Call `gen.sh record` with the envelope's tier/model/cost/prompt + the exec receipt's output_path + dimensions. One JSONL line per call into `assets/generated/.manifest.jsonl` with the 9-field schema (`ts`, `session_id`, `tier`, `model`, `cost_usd`, `prompt`, `output_path`, `dimensions`, `status`). On `exec` failure, still call `record` with `--status=failure` so the audit trail survives.
6. **Report.** Print the output path and a brief one-line summary.

## Helper script

All logic lives in `.agent0/skills/image/scripts/gen.sh`. Three subcommands form the agent-driven pipeline. The script resolves the project root from `CLAUDE_PROJECT_DIR` if set, else falls back to `git rev-parse --show-toplevel` — so passing the env var is optional and runtime-agnostic:

```bash
# 1. prepare — validate inputs, print cost estimate, emit JSON envelope
bash .agent0/skills/image/scripts/gen.sh prepare \
  --tier=<value> [--name=<slug>] [--aspect=<...>] "<prompt>"
# (capture the JSON envelope from stdout's last line)

# 2. exec — POST to fal.run REST, download image, reconcile dims, emit JSON receipt
FAL_KEY="$FAL_KEY" \
  bash .agent0/skills/image/scripts/gen.sh exec --envelope='<json-from-prepare>'

# 3. record — append manifest line (success or failure, both are recorded)
bash .agent0/skills/image/scripts/gen.sh record \
  --tier=<from-envelope> --model=<...> --cost=<...> --prompt="<...>" \
  --output=<from-receipt> --dims=<from-receipt> [--status=success|failure]
```

The 3-stage shape is deliberate — generation is the network-bound step, `prepare` is the contract surface (cost print + path derivation), `record` is the audit step. The agent coordinates the three calls and surfaces failures from `exec` verbatim.

## Examples

```bash
# Cheap mockup for prototype work (default square)
/image --tier=draft "dashboard with three charts and a sidebar nav"

# Landscape banner mockup (1024×576)
/image --tier=draft --aspect=landscape "developer at desk with code on screens, banner composition"

# Brand logo with crisp text (default square)
/image --tier=brand-text --name=hero-logo "minimalist logo for Agent0, monospace 'A0', deep blue"

# Photo-real hero banner for marketing page (1024×576)
/image --tier=brand-photo --aspect=landscape --name=hero "team of engineers collaborating in a sunlit modern office, candid photo"

# Portrait mobile-screen mockup (576×1024)
/image --tier=draft --aspect=portrait "mobile app onboarding flow screen, clean modern design"
```

## Cross-references

- `.agent0/context/rules/image-gen.md` — capacity rule (activation, semantics, gotchas, community fallbacks)
- `.agent0/skills/image/references/tier-pricing.md` — static cost table (refresh quarterly)
- `.agent0/skills/image/scripts/gen.sh` — runtime helper
- `.mcp.json.example` / `.codex/config.toml.example` — `fal-ai` MCP server block (HTTP transport, `bearer_token_env_var = "FAL_KEY"`)

## Notes

_Consumer-extension surface — append consumer-local bullets to this section. Sync flags the file as `!! customized` (sha-compare is section-blind), but the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end. See `.agent0/context/rules/harness-sync.md` § Consumer-extension convention._

- **Hybrid MCP + REST architecture.** The fal-ai MCP recipe (optional now; `.mcp.json` for Claude Code, `.codex/config.toml` for Codex) covers discovery tools — `search_models`, `get_model_schema`, `get_pricing`, `recommend_model` — which the agent uses to pick the right tier intelligently. Each runtime surfaces these under its own tool namespace (e.g. `mcp__fal-ai__search_models` in Claude Code); reference them by their fal.ai names. Generation routes through `gen.sh exec` (curl POST to `https://fal.run/<model>`) instead of the MCP's `run_model`. The split exists because the hosted MCP's generation path was empirically diagnosed broken on 2026-05-25 (hangs ≥990s on gpt-image-2; CC client mis-renders the timeout as "user rejected"). See spec 088 for the full diagnosis. Consumer projects without the MCP recipe still get full generation capability — only discovery is unavailable.
- **Brand-tier prompts should compose from a consumer-local brand contract** (e.g. `docs/brand/styleguide.md`), not be ad-hoc. Image generators drift toward the stock median for vague prompts ("a banner" → generic SaaS banner, not your brand); the contract turns prompt-writing into transcription and makes drift visible at the contract level instead of at the asset. If your consumer project has no contract document, the prompt is ad-hoc — flag this in the call summary. `draft` tier is exempt. See `.agent0/context/rules/image-gen.md` § *Brand-tier prompt composition*.
- The skill does NOT integrate with `/product` or `/prototype` in v1. Standalone — user invokes explicitly. Cross-skill coupling is deferred until either skill explicitly asks for image-gen.
- The skill does NOT enforce per-session cost budgets in v1. Pre-call cost printing is the only signal. Add a counter if empirical sub-agent drift surfaces.
- The skill does NOT cache prompt → output mappings. Every call hits fal.run. Deduplication is the user's responsibility.
