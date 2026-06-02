---
paths:
  - ".agent0/.browser-state/**"
  - ".mcp.json"
  - ".mcp.json.example"
  - ".codex/config.toml.example"
---

# Browser auth

Authenticated-content reads happen through Playwright MCP in a headed-login → save → headless-reuse pattern. This rule documents the signaling convention that bridges the human login step (`BROWSER_AUTH_REQUIRED: <host>`), the per-host state directory (`.agent0/.browser-state/<host>.json`), and the X/Twitter shortcut that avoids the full auth path for a common case.

Playwright MCP is the prerequisite — its server block lives in `.mcp.json.example` (Claude) and `.codex/config.toml.example` (Codex); consumer projects opt in by copying the template and removing the `//` markers / flipping `enabled = true`.

## Prerequisites — activating Playwright MCP

Consumer projects that have never enabled the Playwright MCP server will see the agent emit `BROWSER_AUTH_REQUIRED: <host>` correctly, but the suggested next step ("open Playwright MCP in headed mode") cannot run until the MCP is wired up. One-time setup per consumer project:

```bash
cp .mcp.json.example .mcp.json
# edit .mcp.json — remove the leading `//` markers from the `playwright` block
# (keep the other blocks commented unless you need them)
# then RESTART the Claude Code session — MCPs are loaded at session start, not hot-reloaded
```

For Codex CLI in a trusted project, mirror the activation through `.codex/config.toml.example` → `.codex/config.toml`, flipping `enabled = true` on the `[mcp_servers.playwright]` block, then restart Codex.

After restart, the agent has `mcp__playwright__*` tools available and can drive the headed-login flow described below. The state files produced via `page.context().storageState({ path })` persist across sessions; activation is a one-time cost per consumer project.

Diagnostic: if a session shows `BROWSER_AUTH_REQUIRED` but the agent has no `mcp__playwright__*` tools listed, the prerequisite is incomplete — complete activation first, then re-issue the request in a fresh session.

## X/Twitter shortcut (try first)

Before invoking the full auth workflow for an X/Twitter URL of the form `x.com/<user>/status/<id>` or `twitter.com/<user>/status/<id>`, try the public thread-reader services first. Nitter is dead in 2026; use:

1. **Primary:** `https://unrollnow.com/status/<id>` — fetch via `WebFetch`. If the response body is non-empty and contains the thread text, the read succeeds without any auth step.
2. **Backup:** `https://threadreaderapp.com/thread/<id>.html` — same `WebFetch` approach. Use when unrollnow returns empty or an error.

Only if both fail (empty body, HTTP error, or no thread content) fall back to the `BROWSER_AUTH_REQUIRED` signal below. **The shortcut covers the original-poster's thread continuation only** — it does NOT include replies from other users, quote-tweets, or any sub-thread by a different author. If the request needs replies (e.g. "ler post AND replies"), the shortcut is insufficient and the auth flow is required even for public posts. Other paths the shortcut does NOT cover: locked accounts, DM-only content, threadreaderapp returning login page for threads it has not indexed yet (verified empirically 2026-05).

**Reply-set virtualization gotcha (auth flow path).** Once authenticated, X.com renders the reply list with virtualized scrolling — `browser_snapshot` captures only the ~10 replies in the current viewport, NOT the full reply set (a post with `37 replies` shown in the metric may surface only 8-10 in a single snapshot). To collect all replies, drive `browser_press_key("PageDown")` (or `browser_evaluate("() => window.scrollBy(0, 2000)")`) in a loop and snapshot between scrolls until no new article refs appear. Same shape applies to Twitter's quote-tweet feed.

## Signaling convention — `BROWSER_AUTH_REQUIRED: <host>`

When the agent encounters a URL that requires authentication and no saved state exists for that host, it emits the following phrase to the chat:

```
BROWSER_AUTH_REQUIRED: <host>
```

where `<host>` is the bare hostname (e.g. `x.com`, `linkedin.com`). The agent follows the phrase with a one-line next step pointing the human at this rule and naming the exact save command. Example:

```
BROWSER_AUTH_REQUIRED: x.com
Next step: open Playwright MCP in headed mode, log in at x.com, then run
  browser_run_code_unsafe with `page.context().storageState({ path: '...' })`
  to save state to .agent0/.browser-state/x.com.json.
See .agent0/context/rules/browser-auth.md.
```

The phrase is all-caps with a colon-space separator — agents and humans alike can grep for it. The agent does NOT retry the same host until the human signals the state was saved (e.g. by replying "done" or by the agent detecting the state file exists on disk).

## Storage state — `.agent0/.browser-state/<host>.json`

Session state is stored one file per host under `.agent0/.browser-state/`. The directory ships as an empty scaffold (`.gitkeep` sentinel committed); individual state files are gitignored because they contain session cookies and localStorage — equivalent blast radius to a leaked password. Convention:

- Filename: lowercase hostname, `.json` extension. Examples: `x.com.json`, `linkedin.com.json`, `github.com.json`.
- Path: `.agent0/.browser-state/<host>.json` relative to the project root.
- Never commit these files. The `.gitignore` entry `.agent0/.browser-state/*.json` excludes the state files while leaving the `.gitkeep` sentinel tracked (the sentinel does not match `*.json`, so no `!`-exclusion is needed). See `.agent0/context/rules/secrets-scan.md` for the credential-class framing.

## Playwright MCP — headed login, then headless reuse

The full auth lifecycle with Playwright MCP is three steps:

**Step 1 — headed login (human action required)**

Launch Playwright in headed mode so the human can interact with the login form. The MCP block does not need modification; headed vs headless is a per-invocation argument:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--headed"]
    }
  }
}
```

Navigate to the target site, complete the login flow in the browser window. The agent waits for the human to signal completion.

**Step 2 — save state**

Once the human is logged in, ask the agent to capture the Playwright context's storage state. `@playwright/mcp@latest` (verified 2026-05) does NOT expose a dedicated `browser_storage_state` tool — the only access path is `browser_run_code_unsafe`, which runs an arbitrary `async (page) => ...` function in the Playwright server process and gives access to `page.context()`. Playwright's `context.storageState({ path })` writes the full state (including `httpOnly` cookies like `li_at` / `JSESSIONID`) to disk natively:

```js
async (page) => {
  const state = await page.context().storageState({
    path: '/absolute/path/.agent0/.browser-state/<host>.json'
  });
  return { cookies: state.cookies.length, origins: state.origins.length };
}
```

Pass that as the `code` argument to `mcp__playwright__browser_run_code_unsafe`. Use the ABSOLUTE path (Playwright MCP's sandbox restricts file paths to allowed roots and rejects `/tmp/*` etc; the project root is allowed). Verify by checking the file size (~10-30 KB typical) and grepping for the auth cookie (`li_at` for LinkedIn, `auth_token` for X, etc.).

**`browser_run_code_unsafe` is RCE-equivalent** — the description warns it executes arbitrary JavaScript in the Playwright server process. The save step is one of the legitimate uses; do NOT pass user-supplied or web-derived strings as code. The narrow, single-purpose `storageState({ path })` invocation above is the only shape recommended for routine use.

**Step 3 — headless reuse**

Two reuse paths, depending on whether the consumer project wants a static one-host setup or dynamic multi-host:

*Single-host static reuse:* add `--storage-state=<absolute path>` to the Playwright MCP startup args in `.mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--storage-state=/abs/.agent0/.browser-state/<host>.json"]
    }
  }
}
```

This loads the state at MCP boot; subsequent `browser_navigate` calls reach the host already authenticated. Restart the session after editing `.mcp.json` — MCPs load at SessionStart, not hot-reloaded.

*Dynamic multi-host reuse:* use `browser_run_code_unsafe` to load state mid-session:

```js
async (page) => {
  // Note: addCookies + localStorage hydration via context; for httpOnly cookies
  // the --storage-state startup flag remains the more reliable path because
  // re-attaching httpOnly cookies on an already-running context requires
  // navigation to the target origin to bind them.
  const fs = await import('node:fs/promises'); // may be blocked by sandbox
  const state = JSON.parse(await fs.readFile('/abs/.agent0/.browser-state/<host>.json', 'utf8'));
  await page.context().addCookies(state.cookies);
  return 'cookies loaded';
}
```

Caveat: the Playwright MCP sandbox may block `node:fs` imports (verified empirically — both `require('fs/promises')` and `await import('fs/promises')` failed in this dogfood pass on 2026-05). When `fs` is unavailable, the only viable reuse path is the `--storage-state` startup flag. The multi-host workflow then needs to either (a) merge multiple `<host>.json` files into one combined storage-state JSON at consumer-prep time, or (b) restart the session each time a different host is needed.

The reuse step is silent: when `.agent0/.browser-state/<host>.json` exists and is loaded (either via `--storage-state` or via mid-session injection), the agent navigates as authenticated and `BROWSER_AUTH_REQUIRED: <host>` is NOT emitted.

## Expired-state recovery

Storage state expires when the site rotates session tokens — typically within days to weeks depending on the site. The agent recognises expiry when a navigation that previously succeeded now returns 401, 403, or redirects to a login page. On detection:

1. Delete or archive the stale state file: `rm .agent0/.browser-state/<host>.json`.
2. Re-emit `BROWSER_AUTH_REQUIRED: <host>` to the chat.
3. Repeat the headed-login → save cycle.

The agent does NOT retry silently or guess at token refresh; re-authentication requires the human. This is by design — session cookies are credentials, not config.

## When to reach for Chrome DevTools MCP instead

Chrome DevTools MCP is the right choice when you need **observation**, not **driving**: watching network requests during a Playwright-driven session, capturing console logs, running Lighthouse audits, or taking heap snapshots. It is NOT the default for authenticated content reads.

When you need both (drive + observe), run Playwright MCP as the driver and Chrome DevTools MCP as the observer, using a **dedicated `--user-data-dir` Chrome profile** that contains only the accounts relevant to the task — not `--autoConnect`, which attaches to every open tab in your main Chrome and exposes Gmail, banking, and other active sessions to the agent. `--autoConnect` is opt-in for consumer projects that consciously accept that surface; it should NOT appear in a default `.mcp.json` block. The per-host state directory convention (`.agent0/.browser-state/<host>.json`) applies to both Playwright state files and dedicated Chrome profile directories.

## Cross-references

- `.agent0/context/rules/secrets-scan.md` § *Soft advisory* — `.agent0/.browser-state/*.json` are credential-class files; gitleaks treats high-entropy strings inside them as real findings.
- `.agent0/.runtime-state/README.md` — index of project-local state directories; pairs `.agent0/.browser-state/` with this rule.
