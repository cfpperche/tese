---
paths:
  - ".agent0/skills/video/**"
  - ".agent0/tools/fal-rest.sh"
  - "assets/video/**"
  - "assets/generated/videos/**"
---

# Video generation

Opt-in capacity for producing video, sibling to `/image`. The `/video` skill has **two mechanically disjoint modes** behind a required `--mode` flag, because "make a video" splits into two unrelated mechanisms:

- **`code`** — deterministic. The HyperFrames npm engine (HeyGen, Apache-2.0) renders an HTML/CSS/JS composition to MP4 via headless Chrome + ffmpeg. **Zero inference cost** (token-only). Source is git-tracked; the MP4 is gitignored/regenerable. Best for structured, text/data-driven motion graphics: product demos, changelog/release videos, animated explainers, killer-flow walkthroughs.
- **`generative`** — paid, async. fal.ai video models (Kling/Veo/Wan-class) via the queue REST API. ~5 min/clip, **fire-and-forget ledger** (submit→poll). A clip costs $0.50–$3 — 100–1000× an image — so a **hard cost gate** (`--confirm-cost-usd`) replaces `/image`'s passive cost print. Best for photoreal/organic motion an HTML composition can't fake.

A consumer project that activates neither pays zero cost. The skill is a thin router; mode helpers do the work. This rule is the capacity contract; `.agent0/skills/video/SKILL.md` documents the invocation surface.

## Why this shape (and not Remotion / Higgsfield / one-mode)

Chosen via a cross-model debate (Claude Code ↔ Codex CLI; `docs/specs/132-video-skill/debate.md`):

- **HyperFrames over Remotion** — Remotion is free only for ≤3-person orgs (paid license above), a per-consumer gate that fights harness propagation. HyperFrames is Apache-2.0, no threshold, and HTML is more reliable for LLM-authored compositions.
- **Own the authoring layer, depend on the engine** — we use the pinned `hyperframes@<pin>` npm engine but ship our **own** composition template + `references/authoring.md` rather than installing the upstream `heygen-com/hyperframes` agent-skill (a second un-version-controlled discovery surface).
- **Extend fal.ai, not Higgsfield** — `/image` already rides fal.ai, which already hosts video models. Higgsfield is documented as an optional alternative provider only (`references/video-tiers.yaml`), never the foundation.
- **One skill, two disjoint modes** — the cohesive noun is "video"; the split is internal. No shared abstraction beyond the `--mode` router + `assets/`/manifest convention.

## Activation

Per-mode, one-time per consumer project:

**Code mode** — needs a local toolchain only (no key, no MCP):
- Node.js 22+, FFmpeg + FFprobe, headless Chrome (the engine manages a puppeteer copy).
- Verify with `bash .agent0/skills/video/scripts/code.sh doctor` (wraps `hyperframes doctor`).
- Nothing to install ahead of time — `npx hyperframes@<pin>` fetches the pinned engine on first render.

**Generative mode** — needs `FAL_KEY` (same key as `/image`):
- Mint at [fal.ai](https://fal.ai) → Dashboard → API Keys; `export FAL_KEY="<uuid>:<secret>"`.
- Generation uses the fal.run **queue** REST API directly (curl + jq) — the `fal-ai` MCP recipe is optional (discovery only), reused from `/image`'s `.mcp.json.example` block.
- No session restart needed for the REST path (only the optional discovery MCP loads at session start).

Without activation, every subcommand errors clean with a pointer back here. No silent fallback.

## Mode semantics

| | `code` | `generative` |
|---|---|---|
| Engine | HyperFrames (pinned npm) | fal.ai queue REST |
| Cost | $0 inference | tier × duration (see `video-tiers.yaml`) |
| Latency | local render (seconds–minutes) | ~5 min/clip, async |
| Determinism | yes (conditional — see Gotchas) | no |
| Gate | none (free) | hard `--confirm-cost-usd ≥ estimate` |
| Source tracked? | yes (`assets/video/compositions/<slug>/`) | n/a (prompt in manifest) |

## Tier table (generative)

`references/video-tiers.yaml` is the **oracle** for tier→model resolution — the skill body and `gen.sh` carry NO model IDs. Date-stamped + refreshable: `gen.sh` emits a `video-advisory:` when the snapshot is older than `stale_after_days` (60). v1 seeds `draft` (Wan-class ~$0.10/s), `standard` (Kling-class ~$0.11/s), `premium` (Veo-class ~$0.40/s). Verify the current endpoint id via fal discovery before first use; bump the snapshot when prices/IDs move.

## Storage policy

- `assets/video/compositions/<slug>/` → **git-tracked**. Code-mode composition source is the reproducible truth.
- `assets/generated/videos/*` → **gitignored** (`.gitignore` + `!.gitkeep`). Rendered/generated MP4s are regenerable; the manifest is the historical record.
- `assets/generated/.video-manifest.jsonl` → **git-tracked**. One line per render/clip (success and failure), so cost + fingerprint history survives even when MP4s don't.
- `.agent0/.runtime-state/video-jobs/ledger.jsonl` → **gitignored** runtime state. The generative submit→poll job ledger.

## Manifest schema

One JSONL line per render/clip. Shared core fields align with `/image`'s manifest + `.agent0/delegation-audit.jsonl` (`ts`, `session_id`, `model`, `status`) for cross-domain forensics.

- **Code mode:** `ts`, `session_id`, `mode:"code"`, `slug`, `source_path`, `output_path`, `fingerprint` (object: `hf_version`, `source_sha256`, `output_sha256`, `ffmpeg`, `node`, `viewport`, `duration`, `render_cmd`), `status`.
- **Generative mode:** `ts`, `session_id`, `mode:"generative"`, `model`, `cost_estimate_usd`, `cost_actual_usd`, `prompt`, `output_path`, `request_id`, `status`.

The render fingerprint is recorded as **fields only**. There is intentionally **no drift-checker tool** in v1 (re-hashing committed source vs last render is speculative observability — deferred until rule-of-three demand).

## Cost gate (generative)

`gen.sh prepare` computes `estimate = price_per_second × duration` and **refuses** unless `--confirm-cost-usd ≥ estimate`. The confirmation binds to the prepared envelope (model + duration + cost). Code mode is exempt (free). Estimate vs actual: **record-and-warn, never hard-fail mid-flight** — by the time an overrun is detectable the job is already billed; the manifest records both `cost_estimate_usd` and `cost_actual_usd` and emits a `video-advisory:` if actual exceeds the ceiling. No per-session budget counter in v1 (mirrors `/image`).

## Refresh discipline

`video-tiers.yaml` snapshot + the `hyperframes@<pin>` engine pin both drift. A quarterly/monthly `.agent0/routines/` entry should re-run the fal pricing/catalog lookup and check for HyperFrames releases (`npx hyperframes@<pin> upgrade`). Bump deliberately, not ad-hoc — a major HyperFrames bump can change render output.

## Gotchas

- **Determinism is conditional.** "Same input → same output" assumes a pinned engine + identical fonts + external URLs (the starter loads GSAP from a CDN) resolving the same. The fingerprint records the environment but cannot enforce reproducibility. Vendor fonts/GSAP for hermetic renders.
- **HyperFrames is project-based.** `code.sh scaffold` copies a full mini-project (`index.html` + `hyperframes.json` + `package.json` + `meta.json`), not a loose HTML file. `render` runs from inside the composition dir.
- **HyperFrames is pre-1.0 (v0.6.x).** Flags/behavior can shift between minors; the pin + refresh routine mitigate.
- **fal video is async + two-hop.** `submit` returns a `request_id`; the result JSON carries a CDN URL, downloaded in a second hop. Never block the session polling — `poll` is a separate invocation.
- **REST auth is `Key`, not `Bearer`.** `Authorization: Key $FAL_KEY` for the queue REST API (the discovery MCP uses `Bearer`). Same caveat as `/image`.
- **Cost runaway from a delegated sub-agent.** The confirm gate is per-call; v1 ships no per-session counter. A sub-agent still cannot generate paid video without `--confirm-cost-usd`.
- **`hyperframes cloud` exists** (render without local Chrome/ffmpeg, paid) but is NOT wired into `code.sh` v1 — code mode is local-only by design (zero marginal cost).

## Cross-references

- `.agent0/skills/video/SKILL.md` — invocation surface (canonical; symlinked into `.claude/skills/` + `.agents/skills/`)
- `.agent0/skills/video/references/video-tiers.yaml` — refreshable tier→model oracle
- `.agent0/skills/video/references/authoring.md` — owned composition-authoring guide
- `.agent0/tools/fal-rest.sh` — shared fal queue REST primitives (a follow-up spec migrates `/image` onto this)
- `.agent0/context/rules/image-gen.md` — sibling capacity; the exemplar this mirrors
- `docs/specs/132-video-skill/` — spec, plan, cross-model debate
