/**
 * craft-floor-check.ts — deterministic anti-AI-slop floor for /product visual artifacts (spec 146)
 *
 * Lives inside the /product skill. Invocation:
 *   bun scripts/craft-floor-check.ts --design <DESIGN.md> <file.html...> [--json]
 *
 * Scans authored visual artifacts (Step 02 lo-fi directions, Step 15b hi-fi) for the
 * 5 deterministically-safe P0 anti-slop tells, suppressing brand-declared exceptions,
 * and emits a JSON report the quality-judge consumes (`craft-floor` = fail iff active_p0>0).
 * Advisory: this gates the quality verdict, never artifact persistence. Rule list +
 * triage authored for Agent0; tells adapted from Open Design craft/anti-ai-slop.md (Apache-2.0).
 *
 * The 2 noisy tells (rounded-card-colored-left-border, invented-metrics) are NOT here —
 * they are judge-only guidance (see references/craft-floor.md), too false-positive-prone for regex.
 */

import { readFileSync } from "node:fs";

export type RuleId =
  | "default-indigo-accent"
  | "trust-gradient"
  | "emoji-feature-icon"
  | "filler-copy"
  | "sans-display-when-serif-bound";

export interface Finding {
  id: RuleId;
  severity: "P0";
  file: string;
  line: number;
  snippet: string;
}

export interface Suppressed {
  id: RuleId;
  file: string;
  reason: string;
}

export interface DesignTokens {
  colors: Set<string>; // normalized 6-digit lowercase hexes declared in the bound DESIGN.md
  serifDisplayBound: boolean;
}

export interface Report {
  version: 1;
  files: string[];
  design_system: {
    path: string | null;
    declared_colors: string[];
    serif_display_bound: boolean;
  };
  summary: { active_p0: number; suppressed: number };
  findings: Finding[];
  suppressed: Suppressed[];
}

// The exact Tailwind-default indigo/violet ramp — the textbook AI accent tell.
export const TAILWIND_INDIGO = ["#6366f1", "#4f46e5", "#4338ca", "#3730a3"];

// Emoji blocks used as feature icons (pictographs/emoticons/transport/dingbats/misc-symbols).
// Deliberately EXCLUDES arrows (U+2190-21FF) and similar functional glyphs.
const EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE0F}]/u;

// --- helpers -------------------------------------------------------------

export function normHex(hex: string): string {
  let h = hex.trim().toLowerCase();
  if (!h.startsWith("#")) h = "#" + h;
  if (/^#[0-9a-f]{3}$/.test(h)) {
    h = "#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3];
  }
  return h;
}

/** hue 0-360 from a 6-digit hex, or null if unparseable / achromatic-ish. */
export function hexToHue(hex: string): number | null {
  const h = normHex(hex);
  const m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/.exec(h);
  if (!m) return null;
  const r = parseInt(m[1], 16) / 255;
  const g = parseInt(m[2], 16) / 255;
  const b = parseInt(m[3], 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  if (d < 0.06) return null; // near-grey: no meaningful hue
  let hue: number;
  if (max === r) hue = ((g - b) / d) % 6;
  else if (max === g) hue = (b - r) / d + 2;
  else hue = (r - g) / d + 4;
  hue *= 60;
  if (hue < 0) hue += 360;
  return hue;
}

/** Coarse family bin for the trust-gradient check; only the three slop families matter. */
export function hueFamily(hue: number | null): "purple" | "blue" | "cyan" | "other" | null {
  if (hue == null) return null;
  if (hue >= 250 && hue < 300) return "purple";
  if (hue >= 200 && hue < 250) return "blue";
  if (hue >= 165 && hue < 200) return "cyan";
  return "other";
}

// Some matchers consume a leading boundary char (newline/space) into the match
// start; advance to the first real content char so line/snippet point at it.
function skipLeadingWs(content: string, index: number): number {
  while (index < content.length && /\s/.test(content[index])) index++;
  return index;
}

function lineOf(content: string, index: number): number {
  index = skipLeadingWs(content, index);
  let n = 1;
  for (let i = 0; i < index && i < content.length; i++) if (content[i] === "\n") n++;
  return n;
}

function lineText(content: string, index: number): string {
  index = skipLeadingWs(content, index);
  const start = content.lastIndexOf("\n", index) + 1;
  let end = content.indexOf("\n", index);
  if (end === -1) end = content.length;
  return content.slice(start, end).trim().slice(0, 200);
}

// --- DESIGN.md token parse ----------------------------------------------

export function parseDesignTokens(designMd: string): DesignTokens {
  const colors = new Set<string>();
  for (const m of designMd.matchAll(/#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b/g)) {
    colors.add(normHex(m[0]));
  }
  // Serif display bound iff a line couples a display/heading cue with "serif".
  let serifDisplayBound = false;
  for (const raw of designMd.split("\n")) {
    const l = raw.toLowerCase();
    if (l.includes("serif") && !l.includes("sans-serif")) {
      if (/(display|heading|headline|\bh1\b|\bh2\b|font-display|title)/.test(l)) {
        serifDisplayBound = true;
        break;
      }
    }
    // also: "--font-display: ... <SerifName>, serif"
    if (/--font-(display|heading|head|title)\s*:/.test(l) && /serif/.test(l) && !/sans-serif/.test(l)) {
      serifDisplayBound = true;
      break;
    }
  }
  return { colors, serifDisplayBound };
}

// --- rule matchers (pure; each returns findings/suppressions for one file) ----

export function checkIndigo(file: string, html: string, tokens: DesignTokens): { findings: Finding[]; suppressed: Suppressed[] } {
  const findings: Finding[] = [];
  const suppressed: Suppressed[] = [];
  const set = new Set(TAILWIND_INDIGO);
  for (const m of html.matchAll(/#[0-9a-fA-F]{6}\b/g)) {
    const hex = normHex(m[0]);
    if (!set.has(hex)) continue;
    if (tokens.colors.has(hex)) {
      suppressed.push({ id: "default-indigo-accent", file, reason: `color ${hex} declared in bound DESIGN.md` });
    } else {
      findings.push({ id: "default-indigo-accent", severity: "P0", file, line: lineOf(html, m.index!), snippet: lineText(html, m.index!) });
    }
  }
  return { findings, suppressed };
}

export function checkTrustGradient(file: string, html: string, tokens: DesignTokens): { findings: Finding[]; suppressed: Suppressed[] } {
  const findings: Finding[] = [];
  const suppressed: Suppressed[] = [];
  for (const m of html.matchAll(/linear-gradient\(([^)]*)\)/gi)) {
    const stops = [...m[1].matchAll(/#[0-9a-fA-F]{3,6}\b/g)].map((s) => normHex(s[0]));
    if (stops.length < 2) continue;
    const fams = new Set(stops.map((s) => hueFamily(hexToHue(s))));
    const isTrust =
      (fams.has("purple") && fams.has("blue")) ||
      (fams.has("blue") && fams.has("cyan")) ||
      (fams.has("purple") && fams.has("cyan"));
    if (!isTrust) continue;
    const allDeclared = stops.every((s) => tokens.colors.has(s));
    if (allDeclared) {
      suppressed.push({ id: "trust-gradient", file, reason: "all gradient stops declared in bound DESIGN.md" });
    } else {
      findings.push({ id: "trust-gradient", severity: "P0", file, line: lineOf(html, m.index!), snippet: lineText(html, m.index!) });
    }
  }
  return { findings, suppressed };
}

export function checkEmojiIcon(file: string, html: string): Finding[] {
  const findings: Finding[] = [];
  // Heading / button inner text, or icon|feature-classed element text.
  const patterns = [
    /<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/gi,
    /<button[^>]*>([\s\S]*?)<\/button>/gi,
    /<[^>]*class\s*=\s*["'][^"']*(?:icon|feature)[^"']*["'][^>]*>([\s\S]*?)<\//gi,
  ];
  for (const re of patterns) {
    for (const m of html.matchAll(re)) {
      if (EMOJI.test(m[1])) {
        findings.push({ id: "emoji-feature-icon", severity: "P0", file, line: lineOf(html, m.index!), snippet: lineText(html, m.index!) });
      }
    }
  }
  return findings;
}

export function checkFiller(file: string, html: string): Finding[] {
  const findings: Finding[] = [];
  const re = /lorem ipsum|feature (?:one|two|three)\b|placeholder text|sample content/gi;
  for (const m of html.matchAll(re)) {
    findings.push({ id: "filler-copy", severity: "P0", file, line: lineOf(html, m.index!), snippet: lineText(html, m.index!) });
  }
  return findings;
}

export function checkSansDisplay(file: string, html: string, tokens: DesignTokens): Finding[] {
  if (!tokens.serifDisplayBound) return [];
  const findings: Finding[] = [];
  // selector targeting display headings, with a font-family assignment in its block.
  const re = /(?:^|[},{>\s])(h[1-3]|\.hero[\w-]*|\.display[\w-]*|\.headline[\w-]*)\b[^{}]*\{[^{}]*font-family\s*:\s*([^;}]+)/gi;
  const SANS = /\b(sans-serif|inter|helvetica|arial|system-ui|-apple-system|roboto|segoe ui|ui-sans-serif)\b/i;
  for (const m of html.matchAll(re)) {
    const value = m[2];
    if (SANS.test(value) && !/\bserif\b(?!-)/i.test(value.replace(/sans-serif/gi, ""))) {
      findings.push({ id: "sans-display-when-serif-bound", severity: "P0", file, line: lineOf(html, m.index!), snippet: lineText(html, m.index!) });
    }
  }
  return findings;
}

// --- report builder ------------------------------------------------------

export function buildReport(
  inputs: { file: string; html: string }[],
  tokens: DesignTokens,
  designPath: string | null,
): Report {
  const findings: Finding[] = [];
  const suppressed: Suppressed[] = [];
  for (const { file, html } of inputs) {
    const indigo = checkIndigo(file, html, tokens);
    const grad = checkTrustGradient(file, html, tokens);
    findings.push(...indigo.findings, ...grad.findings, ...checkEmojiIcon(file, html), ...checkFiller(file, html), ...checkSansDisplay(file, html, tokens));
    suppressed.push(...indigo.suppressed, ...grad.suppressed);
  }
  return {
    version: 1,
    files: inputs.map((i) => i.file),
    design_system: {
      path: designPath,
      declared_colors: [...tokens.colors].sort(),
      serif_display_bound: tokens.serifDisplayBound,
    },
    summary: { active_p0: findings.length, suppressed: suppressed.length },
    findings,
    suppressed,
  };
}

// --- CLI -----------------------------------------------------------------

function parseArgs(argv: string[]): { design: string | null; json: boolean; files: string[] } {
  let design: string | null = null;
  let json = false;
  const files: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--design") design = argv[++i] ?? null;
    else if (a === "--json") json = true;
    else files.push(a);
  }
  return { design, json, files };
}

function main(argv: string[]): number {
  const { design, json, files } = parseArgs(argv);
  if (files.length === 0) {
    process.stderr.write("usage: bun scripts/craft-floor-check.ts --design <DESIGN.md> <file.html...> [--json]\n");
    return 2;
  }
  const tokens = design ? parseDesignTokens(readFileSync(design, "utf-8")) : { colors: new Set<string>(), serifDisplayBound: false };
  const inputs = files.map((file) => ({ file, html: readFileSync(file, "utf-8") }));
  const report = buildReport(inputs, tokens, design);
  if (json) {
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  } else {
    process.stdout.write(`craft-floor: ${report.summary.active_p0} active P0, ${report.summary.suppressed} suppressed across ${report.files.length} file(s)\n`);
    for (const f of report.findings) process.stdout.write(`  ! ${f.id}  ${f.file}:${f.line}  ${f.snippet}\n`);
  }
  return 0; // advisory — never non-zero; the judge owns the verdict
}

if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}
