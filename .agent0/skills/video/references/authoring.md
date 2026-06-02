# Authoring HyperFrames compositions (Agent0-owned guide)

This is Agent0's **own** authoring layer for `/video --mode=code`. We depend on the
HyperFrames npm **engine** (`render` / `doctor` / `lint`) but deliberately do NOT
install the upstream `heygen-com/hyperframes` agent-skill (`npx skills add ...`) —
that would be a second, un-version-controlled discovery surface (spec 132 debate, R1).
Everything an agent needs to write a correct composition is here.

## Mental model

A composition is one `index.html`. The engine loads it in headless Chrome, seeks a
**paused GSAP timeline** frame-by-frame, screenshots each frame, and encodes to MP4
with ffmpeg. "Same input → same frames → same output" — deterministic, **conditional**
on a pinned engine + Chromium + identical fonts + any external URLs resolving the same
(see § Determinism caveats).

## The contract

1. **Root declares the composition.** One `#root` div with:
   - `data-composition-id="main"` — must match the timeline key in `window.__timelines`
   - `data-start` / `data-duration` — composition window in seconds
   - `data-width` / `data-height` — canvas size (also set on `<body>` CSS + the viewport meta)

2. **Clips are positioned children.** Each animated element is a `.clip` with its own
   `data-start`, `data-duration`, `data-track-index` (z-order / layering). Use absolute
   positioning inside `#root`.

   > **Lint gotcha (HyperFrames pre-1.0):** the lint is **line-based**. Keep all `#root`
   > `data-*` attributes on **one line**, and do **not** put an HTML comment on the line
   > immediately before `<div id="root">` — either triggers a false
   > `root_missing_composition_id` / `root_missing_dimensions`. Render still succeeds, but
   > a clean composition lints with 0 warnings.

3. **Animate with a PAUSED timeline.** Register one paused `gsap.timeline()` at
   `window.__timelines["main"]`. The engine drives playback by seeking — do NOT call
   `.play()`. Time offsets are the third arg to `.from()/.to()` (seconds).

```html
<div id="root" data-composition-id="main" data-start="0" data-duration="5"
     data-width="1920" data-height="1080">
  <div id="title" class="clip" data-start="0" data-duration="5" data-track-index="1">Hello</div>
</div>
<script>
  window.__timelines = window.__timelines || {};
  const tl = gsap.timeline({ paused: true });
  tl.from("#title", { opacity: 0, y: -60, duration: 1, ease: "power3.out" }, 0.2);
  window.__timelines["main"] = tl;
</script>
```

## What HTML/CSS/JS is good at (use `/video --mode=code` for these)

Structured, text/data-heavy motion graphics: product demos with animated screenshots,
changelog / release videos, data-viz from JSON, animated explainers, branded intros/outros,
social clips with captions. NOT for photoreal/organic motion — that's `--mode=generative`.

## Workflow

```bash
/video --mode=code scaffold my-clip          # copies this template → assets/video/compositions/my-clip/
# edit assets/video/compositions/my-clip/index.html  (this guide)
# optional preview:  cd assets/video/compositions/my-clip && npx hyperframes@0.6.64 preview
/video --mode=code render my-clip            # → assets/generated/videos/<date>-my-clip.mp4
```

The composition **source** (`index.html`, project files) is git-tracked — it's the
reproducible truth. The rendered MP4 is gitignored and regenerable.

## Determinism caveats (real, document — don't over-promise)

- **Fonts.** A font present on the author's machine but absent on another renders differently.
  Prefer web-safe stacks or embed fonts; the fingerprint can't pin this.
- **External URLs.** The starter loads GSAP from a CDN. That's network-dependent and not
  byte-stable across time. Vendor GSAP locally for hermetic renders.
- **Chromium version.** Pinned indirectly via the HyperFrames engine pin; a major engine
  bump can shift rendering. The render fingerprint records `hf_version` for forensics.

## Capabilities reference (engine commands)

`npx hyperframes@<pin> <cmd>`: `doctor` (deps), `preview` (live studio), `lint` (validate),
`snapshot` (key-frame PNGs), `inspect` (layout), `render -o out.mp4` (encode),
`render --format webm -o out.webm` (transparent overlay), `cloud` (render on HeyGen cloud
— no local Chrome/ffmpeg, paid). The skill uses `doctor` + `render`; the rest are for
manual authoring/debugging.
