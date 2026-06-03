/**
 * Unit tests for the craft-floor anti-slop check (spec 146).
 *
 * Three fixture sets prove the contract:
 *   - slop/        non-purple brand, serif display bound → 5 active P0 (one per deterministic rule)
 *   - purple-brand/ brand declares #4f46e5 → the indigo finding is SUPPRESSED, not active
 *   - noisy/        left-border card + "99.9% uptime" → 0 deterministic findings (those stayed judge-only)
 * Plus unit coverage of the hex/hue helpers and DESIGN.md token parse.
 */

import { describe, expect, test } from "bun:test";
import {
  parseDesignTokens,
  buildReport,
  normHex,
  hexToHue,
  hueFamily,
  type DesignTokens,
} from "./craft-floor-check.ts";

const NO_TOKENS: DesignTokens = { colors: new Set(), serifDisplayBound: false };

describe("hex helpers", () => {
  test("normHex lowercases and expands shorthand", () => {
    expect(normHex("#66F")).toBe("#6666ff");
    expect(normHex("4F46E5")).toBe("#4f46e5");
  });
  test("hexToHue + hueFamily bin the slop families", () => {
    expect(hueFamily(hexToHue("#3b82f6"))).toBe("blue");
    expect(hueFamily(hexToHue("#06b6d4"))).toBe("cyan");
    expect(hueFamily(hexToHue("#8b5cf6"))).toBe("purple");
    expect(hueFamily(hexToHue("#111111"))).toBeNull(); // near-grey → no hue
  });
});

describe("parseDesignTokens", () => {
  test("harvests declared hexes + detects a bound serif display", () => {
    const md = `# Brand\n> Editorial. Warm.\nDisplay font: Playfair Display, serif.\nBrand accent: \`#ff5701\`.\n`;
    const t = parseDesignTokens(md);
    expect(t.colors.has("#ff5701")).toBe(true);
    expect(t.serifDisplayBound).toBe(true);
  });
  test("sans-serif alone does not count as a bound serif", () => {
    const md = `# Brand\nBody + headings: Inter, sans-serif.\nAccent #4f46e5.\n`;
    const t = parseDesignTokens(md);
    expect(t.serifDisplayBound).toBe(false);
  });
});

const SLOP_DESIGN = `# Acme\n> Bold editorial brand.\nDisplay font: Playfair Display, serif — used on all headings.\nBrand accent: \`#ff5701\` (orange).\n`;

const SLOP_HTML = `<!doctype html><html><head><style>
:root { --accent: #ff5701; }
h1 { font-family: Inter, sans-serif; }
.hero { background: linear-gradient(90deg, #3b82f6, #06b6d4); }
.cta { color: #6366f1; }
</style></head><body>
<h1>Welcome</h1>
<h2>🚀 Features</h2>
<p>feature one is great.</p>
</body></html>`;

describe("slop fixture → 5 active P0 (one per deterministic rule)", () => {
  const tokens = parseDesignTokens(SLOP_DESIGN);
  const report = buildReport([{ file: "direction-a.html", html: SLOP_HTML }], tokens, "DESIGN.md");
  const ids = report.findings.map((f) => f.id).sort();

  test("all five deterministic rules fire", () => {
    expect(report.summary.active_p0).toBe(5);
    expect(ids).toEqual([
      "default-indigo-accent",
      "emoji-feature-icon",
      "filler-copy",
      "sans-display-when-serif-bound",
      "trust-gradient",
    ]);
  });
  test("findings carry file + line + snippet", () => {
    for (const f of report.findings) {
      expect(f.file).toBe("direction-a.html");
      expect(f.line).toBeGreaterThan(0);
      expect(f.snippet.length).toBeGreaterThan(0);
    }
  });
});

describe("purple-brand fixture → indigo SUPPRESSED, not active", () => {
  const DESIGN = `# Indigo Co\nAccent token \`--accent: #4f46e5\`.\nHeadings + body: Inter, sans-serif.\n`;
  const HTML = `<style>:root{--accent:#4f46e5;} .btn{background:#4f46e5;}</style><h1>Hi</h1>`;
  const tokens = parseDesignTokens(DESIGN);
  const report = buildReport([{ file: "direction-a.html", html: HTML }], tokens, "DESIGN.md");

  test("brand-declared indigo does not fire as active", () => {
    expect(report.findings.find((f) => f.id === "default-indigo-accent")).toBeUndefined();
    expect(report.suppressed.some((s) => s.id === "default-indigo-accent")).toBe(true);
  });
  test("no serif bound → sans-display rule does not run", () => {
    expect(report.findings.find((f) => f.id === "sans-display-when-serif-bound")).toBeUndefined();
    expect(report.summary.active_p0).toBe(0);
  });
});

describe("noisy fixture → 0 deterministic findings (rules stayed judge-only)", () => {
  // Left-border "AI dashboard tile" + invented metric — neither is a deterministic rule.
  const HTML = `<style>.tile{border-radius:12px;border-left:4px solid #ff5701;}</style>
<div class="tile"><strong>99.9% uptime</strong> and 10x faster.</div>`;
  const report = buildReport([{ file: "atlas.html", html: HTML }], NO_TOKENS, null);

  test("no false positives from the two downgraded tells", () => {
    expect(report.summary.active_p0).toBe(0);
    expect(report.findings).toEqual([]);
  });
});
