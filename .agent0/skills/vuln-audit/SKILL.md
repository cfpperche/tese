---
name: vuln-audit
description: On-demand detector for known-vulnerable INSTALLED dependencies in this project, across whatever ecosystems it has (npm/bun, PyPI, Go, crates, Packagist, RubyGems, Maven, NuGet). Use when the user wants to check whether locked dependencies have published CVEs/advisories ("scan for vulnerable deps", "audit dependencies", "any known CVEs in our packages?", "vuln check before release"). Wraps the runtime-neutral .agent0/tools/vuln-audit.sh (engine - osv-scanner). Reports + proposes upgrades; never auto-fixes, never gates install or commit. Flags - [path] --json --exit-code --severity <low|moderate|high|critical>. See .agent0/context/rules/vuln-audit.md.
argument-hint: "[path] [--json] [--exit-code] [--severity <low|moderate|high|critical>]"
license: MIT
compatibility: Designed for Claude Code. Core logic is the runtime-neutral bash tool `.agent0/tools/vuln-audit.sh` (osv-scanner + jq); the skill is a thin invocation wrapper, portable to any runtime that can run the tool. Codex CLI invokes the tool directly.
metadata:
  agent0-portability-tier: agentskills-portable
  version: "0.1"
---

# /vuln-audit — known-vulnerability detector

Thin wrapper over `.agent0/tools/vuln-audit.sh`. The tool is the engine; this skill decides when to run it and how to surface the result. See `.agent0/context/rules/vuln-audit.md` for the full capacity contract (trigger surface, engine choice, status model, non-goals).

## When to run

Run on demand when the user asks to check dependency vulnerabilities, or proactively before a release / when reviewing a PR that bumps dependencies. **Do not** wire this into a commit or install gate — it is detection + proposal only (spec 112 → 120 philosophy: don't gate lib usage; detect vulnerable installed libs and act).

## What to do

1. **Parse `$ARGUMENTS`** — pass them straight through to the tool. All are optional:
   - `[path]` — directory to scan (default: repo root `.`).
   - `--json` — structured output (for wrappers/tests; shape-only, not a wire contract).
   - `--exit-code` — map result status to a non-zero exit (`findings`=1, `unavailable`=2, `failed`=3) for consumer-owned CI. Omit for the default advisory behavior (always exit 0).
   - `--severity <low|moderate|high|critical>` — report only findings at or above this floor.

2. **Invoke the tool:**
   ```bash
   bash .agent0/tools/vuln-audit.sh $ARGUMENTS
   ```

3. **Surface the result** — relay the tool's report. The first line is `status=<clean|findings|unavailable|failed>`:
   - **`clean`** — say so plainly, naming the ecosystems scanned.
   - **`findings`** — summarise per finding: package@version, severity, advisory id/CVE, fixed version, and whether it's a direct or transitive dependency. For fixable direct deps, **propose** the upgrade target — do NOT edit any manifest/lockfile yourself.
   - **`unavailable`** — osv-scanner isn't installed. Relay the install hint; offer to proceed once installed. Do not treat this as "clean".
   - **`failed`** — the engine errored. Relay the diagnostic; suggest re-running the raw command.
   - **`skipped/unsupported` lockfiles** — always relay these (e.g. a legacy `bun.lockb` that needs migrating to text `bun.lock`); a partially-covered scan is not a clean one.

4. **Source-completeness caveat** — when reporting `clean`, frame it honestly: "no known-vulnerable dependencies found *by the OSV-backed engine*", not "no vulnerabilities exist". Independent scanners overlap only ~60–65%.

## Remediation discipline

The capacity proposes; the human disposes. Never run `osv-scanner fix --apply`, `npm audit fix`, `bun audit fix`, or edit a manifest/lockfile as part of this skill. If the user wants the upgrade applied, that is a separate, explicit action they confirm.

## Notes

_Consumer-extension surface — append consumer-local bullets here. Sync flags the file as customized but the conflict region is mechanically this section._

- A recurring cadence is out of scope for v1 — to run this periodically, wire `/routine` to invoke the tool (the documented deferred path; see `.agent0/context/rules/vuln-audit.md`).
- Real-binary install: https://google.github.io/osv-scanner/installation/
