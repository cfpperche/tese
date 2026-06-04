---
name: video
description: AI + programmatic video generation (opt-in). Use when the user wants to produce a video for the project — a product demo, changelog/release clip, animated explainer, killer-flow walkthrough, or a generative motion asset. REQUIRED `--mode` flag picks the mechanism - `code` (deterministic - HyperFrames renders an HTML/CSS/JS composition to MP4 locally, zero inference cost, source git-tracked) or `generative` (paid, async - fal.ai video models via REST queue, ledger-based submit/poll, hard `--confirm-cost-usd` gate because clips cost 100-1000x an image). Omitted `--mode` errors with both options. Generative needs FAL_KEY; code needs Node 22+/ffmpeg/headless-Chrome. Not for editing recorded footage. See `.agent0/context/rules/video-gen.md`.
argument-hint: '<--mode=code|generative> [code: scaffold <slug> | render <slug>] [generative: --tier=draft|standard|premium --duration=<sec> --confirm-cost-usd=<max> [--image-url=<url>] [--name=<slug>] "<prompt>"]'
license: MIT
compatibility: Compatible with any agentskills.io-compatible runtime (Claude Code, OpenAI Codex, and others) that can run bash. Code mode requires a local toolchain (Node.js 22+, FFmpeg, headless Chrome via the pinned hyperframes engine) and is runtime-neutral (npx + bash). Generative mode is runtime-neutral (bash + curl + jq against the fal.ai queue REST API) and requires FAL_KEY + network — it does NOT depend on any runtime's native background execution (fire-and-forget ledger). No MCP required.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.1"
---

# /video — AI + programmatic video generation

Opt-in capacity. Two mechanically disjoint modes under one required `--mode` flag — a consumer project that activates neither pays zero cost. The skill is a thin router: it validates `--mode`, then delegates to the mode's helper script. Full capacity rule (activation, storage, manifest, gotchas): `.agent0/context/rules/video-gen.md`. This SKILL.md documents the invocation surface only.

## Argument parsing

User invokes as `/video <--mode=...> <subcommand/flags> ["<prompt>"]`. The raw argument string is `$ARGUMENTS`. Parse it yourself: extract `--mode=<value>` first, then route the remaining tokens to the mode's helper.

**`--mode` is required.** If absent, error clean — no silent default:

```
/video error: --mode is required. Pick one:
  --mode=code        deterministic, $0 inference   (HyperFrames HTML→MP4, source tracked)
  --mode=generative  paid, async                   (fal.ai video, --confirm-cost-usd gated)
```

## Mode: `code` — deterministic (HyperFrames)

Renders an HTML/CSS/JS composition to MP4 locally. Zero inference cost. Depends on the pinned HyperFrames npm **engine** (not the upstream agent-skill). Source is git-tracked; the MP4 is gitignored/regenerable.

Helper: `bash .agent0/skills/video/scripts/code.sh <subcommand>`

- `doctor` — check local deps (Node/ffmpeg/Chrome) before rendering. Wraps `hyperframes doctor`.
- `scaffold <slug>` — copy the Agent0-owned composition template → `assets/video/compositions/<slug>/`. Edit `index.html` per `references/authoring.md`.
- `render <slug> [--name=<out>]` — render → `assets/generated/videos/<date>-<slug>.mp4` + a fingerprinted manifest line. Fails clean if deps are absent.

```bash
bash .agent0/skills/video/scripts/code.sh doctor
bash .agent0/skills/video/scripts/code.sh scaffold release-notes
# (edit assets/video/compositions/release-notes/index.html)
bash .agent0/skills/video/scripts/code.sh render release-notes
```

## Mode: `generative` — paid, async (fal.ai)

Generates a clip via a fal.ai video model. Paid; ~5 min/clip; **fire-and-forget ledger** — `submit` returns a `request_id`, a separate `poll` reaps it. Tier→model resolves from `references/video-tiers.yaml` (no model IDs in this skill). **Hard cost gate:** `prepare` REFUSES without `--confirm-cost-usd ≥ estimate`.

Helper: `bash .agent0/skills/video/scripts/gen.sh <subcommand>`

1. **prepare** — resolve tier, compute estimate, enforce the gate, emit a JSON envelope:
   ```bash
   bash .agent0/skills/video/scripts/gen.sh prepare \
     --tier=draft --duration=5 --confirm-cost-usd=0.50 \
     --image-url="https://.../first-frame.png" "slow push-in on the product hero"
   ```
2. **submit** — POST to the fal queue, persist the `request_id` to the gitignored ledger:
   ```bash
   bash .agent0/skills/video/scripts/gen.sh submit --envelope='<json-from-prepare>'
   ```
3. **poll** — later, reap terminal jobs (downloads the MP4 + records the manifest):
   ```bash
   bash .agent0/skills/video/scripts/gen.sh poll --all     # or --id=<request_id>
   ```

If `FAL_KEY` is unset, every generative subcommand errors clean pointing at activation. Generation routes through the fal.run queue REST API (`Authorization: Key $FAL_KEY`), NOT an MCP. Higgsfield is documented as an optional alternative provider only (`references/video-tiers.yaml`).

## Storage

- Code-mode composition **source** → `assets/video/compositions/<slug>/` (git-tracked — reproducible truth)
- Rendered MP4 (both modes) → `assets/generated/videos/` (gitignored — regenerable)
- Manifest → `assets/generated/.video-manifest.jsonl` (git-tracked — cost/fingerprint history survives even when MP4s don't)
- Generative job ledger → `.agent0/.runtime-state/video-jobs/ledger.jsonl` (gitignored runtime state)

## Cross-references

- `.agent0/context/rules/video-gen.md` — capacity rule (activation, modes, manifest schema, gotchas, refresh discipline)
- `.agent0/skills/video/references/video-tiers.yaml` — refreshable tier→model table (generative)
- `.agent0/skills/video/references/authoring.md` — owned composition-authoring guide (code)
- `.agent0/tools/fal-rest.sh` — shared fal queue REST primitives (also used by a future `/image` migration)
- `.agent0/skills/image/SKILL.md` — sibling skill; the exemplar this mirrors
- `docs/specs/132-video-skill/` — spec + cross-model debate behind this design

## Notes

_Consumer-extension surface — append consumer-local bullets here. Sync flags the file as `!! customized`; the conflict region is mechanically this section: take new upstream verbatim, re-add consumer bullets at the end._

- **Modes are intentionally disjoint.** Code mode never calls fal; generative mode never spawns Chrome. The only shared surface is the `assets/` + manifest convention and the `--mode` router. Do not introduce a shared abstraction beyond that (spec 132 debate, R5).
- **Cost gate is real, not cosmetic.** Generative `prepare` exits non-zero without `--confirm-cost-usd` covering the estimate. A delegated sub-agent cannot generate paid video without that flag. No per-session budget counter in v1 (mirrors `/image`).
- **Determinism is conditional.** Code mode is "same input → same output" only with a pinned engine + identical fonts + external URLs (GSAP CDN) resolving the same. The render fingerprint records the environment; it does not enforce reproducibility.
- **No `/product` or `/prototype` coupling in v1.** Standalone, user-invoked.
