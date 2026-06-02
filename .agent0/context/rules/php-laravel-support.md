---
paths:
  - "composer.json"
  - "composer.lock"
  - "artisan"
  - "**/composer.json"
  - "phpunit.xml"
  - "phpunit.xml.dist"
  - "Pest.php"
---

# PHP / Laravel support

This rule is an **index**, not the canonical source. Each Agent0 capacity — validator, TDD, lint, MCP recipes — has its own rule doc that documents the per-stack behavior in full. This page exists so a new reader on a Laravel consumer project can find every PHP-aware touchpoint in one place. The canonical per-capacity docs are linked under each section below; read them when you need depth, this page for orientation.

PHP detection in Agent0 is triggered by **`composer.json` at the project root** (validator). The capacities below ship dormant in a non-PHP consumer project and activate the moment those signals exist — no env-var to set, no opt-in.

## 1. Validator detects PHP

`.agent0/validators/run.sh` recognises `composer.json` after the rust elif (PHP slotted late in the chain so JS-leading mixed-stack monorepos route to JS via lockfile precedence). Detection chooses the test runner:

- `composer.json` declares `pestphp/pest` in `require-dev` or `require` → `command_str='vendor/bin/pest --colors=never'`
- Otherwise → `command_str='vendor/bin/phpunit --colors=never'`

`--colors=never` disables ANSI at source so the validator's output stays simple. Canonical doc: this rule + the validator's elif chain at `.agent0/validators/run.sh`.

## 2. TDD patterns recognise PHP test files

`.agent0/validators/run.sh`'s TDD warning path adds `php) default_patterns='tests/* *Test.php *_test.php' ;;` to the per-stack pattern table. This covers PHPUnit and Pest naming conventions plus Laravel's `tests/Feature/` and `tests/Unit/` layout. A delegated sub-agent that edits prod-PHP (e.g. `app/Models/User.php`) without touching any pattern-matched test file in the same diff triggers a `tdd-advisory:` line on the next turn.

Canonical doc: `.agent0/context/rules/tdd.md` § *From scenarios to tests* (per-language test-pattern table).

## 3. Lint validator runs Pint + PHPStan

`.agent0/validators/run.sh` lint extension adds a `php` branch after the Python branch:

- `composer.json` declares `laravel/pint` in `require-dev` (or `require`) AND `vendor/bin/pint` is executable → append `vendor/bin/pint --test` (test mode — no auto-fix).
- `composer.json` declares `phpstan/phpstan` OR `larastan/larastan` (in `require-dev` or `require`) AND `vendor/bin/phpstan` is executable → append `vendor/bin/phpstan analyse --no-progress`.
- Either declared + binary missing → emit `lint-advisory: <linter> declared in composer.json but not installed — run \`composer install\`` to stderr.

PHP is the first stack where TWO lint primitives (Pint + PHPStan) can fire in a single run. Both contribute to the composed `command_str`; both can emit advisories on missing binaries; advisories are concatenated with newlines so each gets its own stderr line.

Canonical doc: `.agent0/context/rules/lint-validator.md` § *What fires, what advises* (PHP paragraph).

## 4. Laravel Boost MCP template

`.mcp.json.example` (Claude Code) and `.codex/config.toml.example` (Codex CLI) ship a `laravel-boost` MCP server block, disabled by default. Activation in a Laravel consumer project: `composer require laravel/boost --dev && php artisan boost:install` inside the Laravel project, then copy the relevant `.example` file (or merge the block into an existing config) and remove the `//` markers / flip `enabled = true`.

Pairs naturally with the `playwright` block for browser-driven E2E and the `dbhub` block when the consumer project also has a real DATABASE_URL. Activation is consumer-driven — Agent0 does not auto-detect or auto-suggest. Consult the upstream Laravel Boost README ([github.com/laravel/boost](https://github.com/laravel/boost)) for tool-list specifics and security stance.

## 5. CLAUDE.md capacity index

CLAUDE.md folds PHP/Laravel detection inline into the capacity sections that enumerate stacks (validator, lint) — it carries no dedicated PHP/Laravel chapter. This rule doc is the canonical PHP/Laravel reference; it is path-scoped (frontmatter `paths:` on `composer.json` / `artisan` / `phpunit.xml` / `Pest.php`) and auto-loads the moment a consumer project's PHP signals are touched, so a consumer project needs no CLAUDE.md pointer to discover it.

## What this does NOT add

- **No new validator stack other than PHP.** Symfony, CodeIgniter, Yii, Laminas, etc. — all out of scope for v1. A future spec can extend detection if the demand surfaces.
- **No php-cs-fixer detection separate from Pint.** Pint wraps php-cs-fixer; supporting both would duplicate signal. Pure php-cs-fixer projects (no Pint dependency) hit silent-skip on lint.
- **No PHP-aware monorepo walk.** The validator's "first lockfile wins" remains — a consumer project with composer.json AND package.json routes to whichever elif matches first (currently JS first, PHP late). Multi-stack monorepo PHP+JS is a future spec territory.
- **No editor-time / on-save integration.** Same posture as every other Agent0 capacity — validator runs at sub-agent edit boundaries via hooks, not in real time.
- **No managed `composer install` orchestration.** Agent0 surfaces missing binaries as advisories; the human (or agent under override) decides when to install.

## Cross-references

- `.agent0/context/rules/lint-validator.md` — Pint + PHPStan rules
- `.agent0/context/rules/tdd.md` — PHP test patterns
- `.mcp.json.example` / `.codex/config.toml.example` — Laravel Boost MCP template block (`[mcp_servers.laravel-boost]`)
- `.agent0/validators/run.sh` — the validator's PHP elif
- `.agent0/tests/validator-php/` — the test surface that locks the behavior

## Gotchas

- **Lockfile precedence vs PHP.** The validator's elif chain is `bun → pnpm → npm → python → go → rust → php`. A monorepo with `bun.lock` at root and `composer.json` in `services/api/` routes to bun (first match wins). The PHP detection only fires when `composer.json` is at root AND no JS/Python/Go/Rust manifest precedes it. This is the documented limitation; proper multi-stack walking is a future capacity.
- **Pest detection trumps PHPUnit.** Pest declares `phpstunit/phpunit` as a transitive dep (Pest is built on PHPUnit). Both will appear in `composer.lock`. The validator's check on the *direct* declaration of `pestphp/pest` in composer.json correctly picks Pest in that case; if a consumer project wants the bare PHPUnit invocation despite having Pest installed, drop the Pest declaration from composer.json (the precedent: a single test runner per project).
- **`vendor/bin/*` checks are filesystem probes.** A consumer project that ran `composer install` but later moved its `vendor/` dir (or is using a non-standard installer like `composer-bin-plugin`) will see "declared but missing" advisories. Symlink `vendor/bin/<tool>` to the actual binary or accept the noise. Same shape as Biome's "missing under monorepo hoisting" gotcha.
- **`composer test` exit-code passthrough.** Composer wraps the script defined in `composer.json` `scripts.test`. Composer's behaviour: if the script exits non-zero, composer exits non-zero — so the validator running `composer test` gets a faithful exit code.
- **`laravel-boost` MCP requires PHP + artisan in the working dir.** The MCP launches `php artisan boost:mcp` — if the agent's working dir is outside the Laravel project, the command fails. Consumer projects with multi-root layouts (e.g. monorepo with Laravel under `apps/api/`) must set the MCP working dir or stay inside the Laravel root when invoking boost tools.
