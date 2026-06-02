<!-- vendored from open-design@c128ffd53bba3f3080b2d0b7d656d1634016e10a:skills/slack-gif-creator/SKILL.md · do not edit -->
---
name: slack-gif-creator
description: |
  Create animated GIFs optimized for Slack with validators for size constraints and composable animation primitives.
triggers:
  - "slack gif"
  - "animated gif"
  - "reaction gif"
  - "tiny gif"
od:
  mode: image
  category: image-generation
  upstream: "https://github.com/anthropics/skills/tree/main/slack-gif-creator"
---

# slack-gif-creator

> Curated from Anthropic's official skills repository.

## What it does

Create animated GIFs optimized for Slack with validators for size constraints and composable animation primitives.

## Source

- Upstream: https://github.com/anthropics/skills/tree/main/slack-gif-creator
- Category: `image-generation`

## How to use

This catalogue entry advertises the skill in Open Design so the agent
discovers it during planning. To run the full upstream workflow with
its original assets, scripts, and references, install the upstream
bundle into your active agent's skills directory:

```bash
# Inspect the upstream README for exact paths
open https://github.com/anthropics/skills/tree/main/slack-gif-creator
```

Then ask the agent to invoke this skill by name (`slack-gif-creator`) or with
one of the trigger phrases listed in this skill's frontmatter.
