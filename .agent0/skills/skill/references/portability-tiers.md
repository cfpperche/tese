# Skill portability tiers

Agent0 classifies every first-party skill into one of three tiers, declared in the SKILL.md frontmatter under `metadata.portability-tier`. The tier signals to consumers (humans + other runtimes) how widely the skill works without modification.

## The three tiers

### Tier 1 — `cc-native`

**Definition.** The skill's body references Claude Code-specific paths, environment variables, hooks, or tools. It works correctly only inside a Claude Code session where those primitives exist.

**Signals in the body:**
- References to `.agent0/context/rules/*.md`, `.agent0/memory/*.md`, `.claude/hooks/*.sh`, `.agent0/reminders.yaml`, `.agent0/HANDOFF.md`
- The `${CLAUDE_SKILL_DIR}` or `$CLAUDE_PROJECT_DIR` env vars
- CC-only tools invoked by name (`TaskCreate`, `ExitPlanMode`, the `Skill` tool recursive call, `ScheduleWakeup`)
- Calls into CC settings (`.claude/settings.json`) or per-session state (`.agent0/.session-state/`)

**Canonical `compatibility:` text:**

> Designed for Claude Code. Body references `.claude/` conventional paths and CC-specific tools; portable to any runtime that maps a `.claude/`-analog directory and surfaces the referenced tools.

**Agent0 examples (post-port):** `remind`, `sdd`, `brainstorm`, `skill` (the meta-skill itself), `update-config`, `keybindings-help`.

### Tier 2 — `agentskills-portable`

**Definition.** The skill's body uses only primitives that any agentskills.io-compatible runtime exposes — file IO (read/write/edit), shell execution, web fetch. Paths the skill reads from or writes to are either passed as arguments, derived from a configurable env var with a documented fallback, or computed from the skill's own bundled `references/` / `assets/`.

**Signals in the body:**
- No `.claude/` paths in the body
- No CC-specific tool names (no `TaskCreate`, no `Skill`-recursive, etc.)
- Where state needs to persist, it goes to a path derived from the skill's own directory or a documented env var (e.g. `${SKILL_STATE_DIR:-.}/state.json`)

**Canonical `compatibility:` text:**

> Compatible with any agentskills.io-compatible runtime (Claude Code, Hermes Agent, OpenAI Codex, Cursor, Goose, OpenCode, and ~35 others). Uses only universal primitives (file IO, shell, web).

**Agent0 examples:** none yet. Future candidates: `simplify` (review changed code — needs path arg only), `init` (write a CLAUDE.md scaffold), refactored versions of current cc-native skills.

### Tier 3 — `runtime-agnostic`

**Definition.** Everything `agentskills-portable` requires, plus no assumption that the host OS is Linux or that `bash` is the shell. Either (a) all bundled scripts have parallel implementations (e.g., `scripts/validate.sh` + `scripts/validate.ps1`) or (b) the skill bundles its logic in a runtime-agnostic language (Python, JavaScript) and depends only on its interpreter being present.

**Signals in the body:**
- No bash-specific syntax in scripts unless mirrored in PowerShell
- File path separators handled portably (no hard-coded `/`)
- Any dependency declared with cross-platform install paths

**Canonical `compatibility:` text:**

> Compatible with any agentskills.io-compatible runtime, on Linux, macOS, or Windows. Bundled logic is OS-agnostic.

**Agent0 examples:** none yet. This tier is aspirational for v1; only worth declaring when a real cross-OS consumer demands it.

## Decision flowchart

```
                ┌─────────────────────────────────────────────┐
                │  Does the body reference .claude/, hooks,   │
                │  ${CLAUDE_SKILL_DIR}, or CC-only tools?     │
                └──────────────────┬──────────────────────────┘
                                   │
                       ┌───────────┴───────────┐
                       │                       │
                      yes                     no
                       │                       │
                       ▼                       ▼
                  cc-native              ┌────────────────────────────┐
                                         │  Does every bundled script │
                                         │  have a Windows-compatible │
                                         │  parallel OR is the logic  │
                                         │  in a portable language?   │
                                         └─────────────┬──────────────┘
                                                       │
                                          ┌────────────┴────────────┐
                                          │                         │
                                         no                        yes
                                          │                         │
                                          ▼                         ▼
                              agentskills-portable          runtime-agnostic
```

## How to apply the tier

In the SKILL.md frontmatter:

```yaml
---
name: example-skill
description: …
license: MIT
compatibility: <canonical text from this file, matching the tier>
metadata:
  agent0-portability-tier: cc-native | agentskills-portable | runtime-agnostic
---
```

The validator (`scripts/validate.sh`) does NOT verify that the body actually matches the declared tier — declared tier is operator-asserted intent, not mechanically derived. Drift between declared tier and actual body is a documentation bug; report via `/skill audit` flagging mismatches when it detects body signals inconsistent with the declared tier.

## Why three tiers and not two

Two tiers (CC-only vs portable) collapses a real distinction: a Linux-bash skill that runs in Hermes is portable to *most* runtimes but not to a Windows-only environment. The third tier holds the OS-portability bar separate so a consumer project can confidently say "this works on every supported runtime AND every supported OS" without re-auditing.

## Why the namespace is `agent0-` prefixed

Decision: **use `agent0-portability-tier` (kebab-case namespace), not bare `portability-tier`.**

Evidence (2026-05-17 research, Phase C task #10):
- agentskills.io spec § `metadata`: "Clients can use this to store additional properties not defined by the Agent Skills spec. We recommend making your key names reasonably unique to avoid accidental conflicts."
- No prior claim found on `portability-tier` across the agentskills.io spec, the GitHub `agentskills/agentskills` repo, or community docs surveyed.
- However, `portability-tier` is generic enough that an upstream convention could claim it differently within a year. Bare key → silent semantic collision risk.

Trade: kebab-namespaced key is 8 chars longer per occurrence but defends. Validator parsing is unaffected (validator only checks the 6 spec fields, not metadata sub-keys). All Agent0 skills and templates use `agent0-portability-tier`.

## On `argument-hint` placement

Decision: **`argument-hint:` stays at top-level of frontmatter; do NOT nest under `metadata:`.**

Evidence (2026-05-17, Phase C task #11, via claude-code-guide agent):
- Official Claude Code skills docs (https://code.claude.com/docs/en/skills.md) define `argument-hint` as a **top-level** frontmatter field rendered by CC for slash-command autocomplete. The docs do not document a nested form.
- Nesting under `metadata:` would silently break CC's typing-hint render — the field is read at top-level only.

Since the agentskills.io spec does not explicitly forbid unknown top-level keys (the 6 documented fields are the *defined* set, not an *exhaustive* set), keeping `argument-hint:` at top-level is dual-correct: CC renders it; other runtimes that strictly validate the 6 spec fields ignore it harmlessly; validators that whitelist-reject unknown keys would be over-strict per common YAML-frontmatter convention and are not represented in the current 40+ agentskills.io runtimes surveyed.

The port operation in `scripts/port-frontmatter.sh` therefore leaves `argument-hint:` untouched at top-level when it encounters it.

## Per-skill multi-runtime migration runbook (spec 121)

To make a skill consumable by both Claude Code and Codex CLI, relocate its body to the canonical
`.agent0/skills/<slug>/` home and register a discovery symlink per runtime. Checklist:

1. **Classify the tier.** `cc-native` (uses `AskUserQuestion`, `${CLAUDE_SKILL_DIR}`, or the `Skill`-tool invocation model with no Codex analogue) → **does not migrate**; stays physically in `.claude/skills/<slug>/`. `agentskills-portable` / `runtime-agnostic` → proceed.
2. **Neutralize CC-only primitives.** Route deterministic work through `.agent0/tools/*` (Codex shells out the same way); resolve bundled resources **relative to the SKILL.md path**, never via `${CLAUDE_SKILL_DIR}` (removed in Codex). If an `AskUserQuestion` gate is essential and can't degrade to plain-prose questions, the skill is `cc-native` — stop.
3. **Move the source:** `git mv .claude/skills/<slug>/SKILL.md .agent0/skills/<slug>/SKILL.md` (+ any `scripts/`/`references/`/`assets/`); remove the now-empty `.claude/skills/<slug>/`.
4. **Create relative discovery symlinks:** `.claude/skills/<slug>` → `../../.agent0/skills/<slug>` and `.agents/skills/<slug>` → `../../.agent0/skills/<slug>`.
5. **Optional `agents/openai.yaml`:** add only when Codex UI metadata, MCP dependencies, or `policy.allow_implicit_invocation` control is needed — broad skills set `allow_implicit_invocation: false` (default is true) so they fire only on explicit `/skills` / `$<slug>`.
6. **Verify both runtimes:** Claude discovers via `.claude/skills/` + `Skill` tool; Codex via `codex debug prompt-input` listing `.agents/skills/<slug>` + explicit `$<slug>` (implicit invocation tested separately). Confirm both resolve to the one canonical `SKILL.md`.

sync-harness propagation of the model (manifest entries, the `sync_skill_discovery_links` pass, the
symlink-hostile copy fallback) is documented in `.agent0/context/rules/harness-sync.md` § *Skill discovery-link
propagation*. `vuln-audit` is the reference migration (spec 121).
