/**
 * Unit tests for the OD vendor sync engine.
 *
 * Covers the pure, exported pieces — `computeTreeChecksum`, `validateManifestShape`,
 * `validateDesignMd` — plus `verifyManifest` drift detection against a fixture tree.
 * The network-bound subcommands (`--check`/`--bump`/`--apply`) are not exercised
 * here; `--verify` is the prepublishOnly gate and is the one that must be airtight.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, writeFile, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import {
  computeTreeChecksum,
  validateManifestShape,
  validateDesignMd,
  verifyManifest,
  resolveChangedVendoredScope,
  COMPARE_FILE_CAP,
  buildCatalogVendors,
  pinnedContentAlreadyApplied,
  scanStaleCounts,
  computeOrphans,
  topLevelBundles,
  findReferencedOrphans,
  assertDisjointRoots,
} from "./sync-open-design.js";

let tmpRoot: string;

beforeEach(async () => {
  tmpRoot = await mkdtemp(join(tmpdir(), "od-sync-test-"));
});

afterEach(async () => {
  await rm(tmpRoot, { recursive: true, force: true });
});

function sha256(buf: Buffer | string): string {
  return `sha256:${createHash("sha256").update(buf).digest("hex")}`;
}

describe("computeTreeChecksum", () => {
  test("is order-independent (sorts before hashing)", () => {
    const a = computeTreeChecksum(["sha256:ccc", "sha256:aaa", "sha256:bbb"]);
    const b = computeTreeChecksum(["sha256:aaa", "sha256:bbb", "sha256:ccc"]);
    expect(a).toBe(b);
  });

  test("changes when any per-file checksum changes", () => {
    const base = computeTreeChecksum(["sha256:aaa", "sha256:bbb"]);
    const drifted = computeTreeChecksum(["sha256:aaa", "sha256:bbX"]);
    expect(drifted).not.toBe(base);
  });

  test("returns a sha256:-prefixed digest", () => {
    expect(computeTreeChecksum(["sha256:aaa"])).toMatch(/^sha256:[0-9a-f]{64}$/);
  });
});

describe("validateManifestShape", () => {
  test("accepts a manifest carrying the required fields", () => {
    expect(() =>
      validateManifestShape({
        pinned_sha: null,
        last_check_sha: null,
        last_check_at: null,
        vendored_paths: [],
      }),
    ).not.toThrow();
  });

  test("throws naming the first missing required field", () => {
    expect(() => validateManifestShape({ pinned_sha: "x" })).toThrow(
      /missing required field/,
    );
  });
});

describe("validateDesignMd — substance gate", () => {
  // A vendored DESIGN.md is validated for *consumable substance*, not heading text
  // (spec 135: no consumer reads specific H2 names — generateDsIndex reads mood+hex,
  // step 02-prototype reads prose). Required surface = a usable palette + enough
  // structure that the file isn't a truncated stub.
  const palette = "tokens: bg `#0a0a0a` / fg `#fafafa` / primary `#3b82f6` / accent `#f59e0b`";
  function ds(headings: string[], body = palette): string {
    return headings.map((h) => `## ${h}`).join("\n") + "\n\n" + body + "\n";
  }

  test("accepts abbreviated upstream headings (## 2. Color, no literal 'palette')", () => {
    const md = ds([
      "1. Visual Theme & Atmosphere",
      "2. Color",
      "3. Typography",
      "4. Components",
      "5. Layout & Composition",
    ]);
    expect(validateDesignMd(md)).toEqual([]);
  });

  test("accepts wechat-style vocabulary (no literal 'layout' / 'visual theme')", () => {
    const md = ds([
      "Brand Identity",
      "Color Palette",
      "Typography",
      "Spacing System",
      "Components",
      "Dark Mode",
    ]);
    expect(validateDesignMd(md)).toEqual([]);
  });

  test("accepts a monochrome system (black + white, 2 hex) — spacex/figma case", () => {
    const md = ds(
      ["Brand Identity", "Color Palette", "Typography", "Components"],
      "pure black `#000000` on spectral white `#f0f0fa`, no other color",
    );
    expect(validateDesignMd(md)).toEqual([]);
  });

  test("rejects a degenerate file with no palette", () => {
    const md = ds(["Overview", "Notes", "More"], "just prose, no hex colors at all");
    const problems = validateDesignMd(md);
    expect(problems.some((p) => p.includes("palette"))).toBe(true);
  });

  test("rejects a truncated file with too few H2 sections", () => {
    const md = "## Only One Heading\n\n" + palette;
    const problems = validateDesignMd(md);
    expect(problems.some((p) => p.includes("structure"))).toBe(true);
  });

  test("counts unique hex only — matches generateDsIndex palette_summary semantics", () => {
    const md = ds(["A", "B", "C"], "#111111 #111111 #111111"); // 1 unique hex
    expect(validateDesignMd(md).some((p) => p.includes("palette"))).toBe(true);
  });
});

describe("resolveChangedVendoredScope — --check truncation guard", () => {
  const vendoredSrcs = ["design-systems/", "skills/", "packages/contracts/src/prompts/system.ts"];

  test("precise: filters the changed-file list to vendored scope", () => {
    const changed = ["README.md", "design-systems/flat/DESIGN.md", "packages/contracts/src/prompts/system.ts", "src/app.ts"];
    const r = resolveChangedVendoredScope(changed, vendoredSrcs, true);
    expect(r.imprecise).toBe(false);
    expect(r.reason).toBe("precise");
    expect(r.display).toEqual(["design-systems/flat/DESIGN.md", "packages/contracts/src/prompts/system.ts"]);
  });

  test("precise: genuine no-change yields an empty display", () => {
    const changed = ["README.md", "src/app.ts", "docs/guide.md"];
    const r = resolveChangedVendoredScope(changed, vendoredSrcs, true);
    expect(r.imprecise).toBe(false);
    expect(r.display).toEqual([]);
  });

  // Bug A regression: a diff that hits GitHub's 300-file compare cap is likely
  // truncated — a precise filter could falsely report "no changes in vendored
  // paths". Over-report ALL vendored srcs instead of trusting the partial list.
  test("truncated: a capped file list over-reports all vendored paths", () => {
    const changed = Array.from({ length: COMPARE_FILE_CAP }, (_, i) => `unrelated/file-${i}.ts`);
    const r = resolveChangedVendoredScope(changed, vendoredSrcs, true);
    expect(r.imprecise).toBe(true);
    expect(r.reason).toBe("truncated");
    expect(r.display).toEqual(vendoredSrcs);
  });

  test("unavailable: no gh result over-reports all vendored paths", () => {
    const r = resolveChangedVendoredScope([], vendoredSrcs, false);
    expect(r.imprecise).toBe(true);
    expect(r.reason).toBe("unavailable");
    expect(r.display).toEqual(vendoredSrcs);
  });

  test("an empty changed-file list with gh available is treated as unavailable, not 'no changes'", () => {
    // gh returned zero filenames — indistinguishable from an error; never conclude "in sync".
    const r = resolveChangedVendoredScope([], vendoredSrcs, true);
    expect(r.imprecise).toBe(true);
    expect(r.display).toEqual(vendoredSrcs);
  });
});

describe("verifyManifest — drift detection", () => {
  /** Stage a fixture vendor tree: one single-file entry + one recursive tree. */
  async function stageFixture() {
    const singleRel = "vendor/open-design/prompts/system.ts";
    const singlePath = join(tmpRoot, singleRel);
    await mkdir(join(tmpRoot, "vendor/open-design/prompts"), { recursive: true });
    const singleContent = "// vendored\nexport const x = 1;\n";
    await writeFile(singlePath, singleContent);

    const treeDir = join(tmpRoot, "design-systems");
    await mkdir(join(treeDir, "foo"), { recursive: true });
    await mkdir(join(treeDir, "bar"), { recursive: true });
    const fooContent = "# foo DESIGN\n";
    const barContent = "# bar DESIGN\n";
    await writeFile(join(treeDir, "foo", "DESIGN.md"), fooContent);
    await writeFile(join(treeDir, "bar", "DESIGN.md"), barContent);
    // a .gitkeep must be ignored by the walk
    await writeFile(join(treeDir, ".gitkeep"), "");

    const treeChecksum = computeTreeChecksum([sha256(fooContent), sha256(barContent)]);

    const manifest = {
      $schema: "x",
      upstream_url: "https://example.com",
      pinned_sha: null,
      pinned_at: null,
      last_check_sha: null,
      last_check_at: null,
      license_attribution: [],
      history: [],
      vendored_paths: [
        { src: "x", dst: singleRel, kind: "prompt-source", checksum: sha256(singleContent) },
        { src: "y", dst: "design-systems/", kind: "design-system-tree", recursive: true, checksum: treeChecksum },
      ],
    };
    return { manifest, singlePath, treeDir };
  }

  test("reports ok for every path of an untouched tree", async () => {
    const { manifest } = await stageFixture();
    const results = verifyManifest(manifest as never, tmpRoot);
    expect(results).toHaveLength(2);
    expect(results.every((r) => r.ok)).toBe(true);
  });

  test("detects a hand-edit to a single-file entry", async () => {
    const { manifest, singlePath } = await stageFixture();
    await appendFile(singlePath, "// tampered\n");
    const results = verifyManifest(manifest as never, tmpRoot);
    const single = results.find((r) => r.dst.endsWith("system.ts"))!;
    expect(single.ok).toBe(false);
    expect(single.actual).not.toBe(single.expected);
  });

  test("detects a hand-edit inside a recursive tree", async () => {
    const { manifest, treeDir } = await stageFixture();
    await appendFile(join(treeDir, "foo", "DESIGN.md"), "tampered");
    const results = verifyManifest(manifest as never, tmpRoot);
    const tree = results.find((r) => r.dst === "design-systems/")!;
    expect(tree.ok).toBe(false);
  });

  test("flags a vendored path that is missing on disk", async () => {
    const { manifest } = await stageFixture();
    await rm(join(tmpRoot, "vendor/open-design/prompts/system.ts"));
    const results = verifyManifest(manifest as never, tmpRoot);
    const single = results.find((r) => r.dst.endsWith("system.ts"))!;
    expect(single.ok).toBe(false);
    expect(single.note).toMatch(/missing/);
  });
});

// ── Fix 2: catalogue regen (acceptance 4) ──────────────────────────────────────
describe("buildCatalogVendors — preserve curated, add mechanical", () => {
  const vp = (n: string) => `prefix/design-systems/${n}/DESIGN.md`;
  const cat = (n: string) => (n === "newcat" ? "Themed & Unique" : null);

  test("preserves a curated entry verbatim (category/mood/palette kept, vendor_path refreshed)", () => {
    const curated = {
      name: "airbnb",
      category: "E-Commerce & Retail",
      mood: "Travel marketplace.",
      palette_primary: "Rausch (#ff385c)",
      vendor_path: "stale/path.md",
    };
    const out = buildCatalogVendors(
      [{ name: "airbnb", mood: "MECHANICAL mood that must be ignored", palette_summary: ["#000000"] }],
      { airbnb: curated },
      cat,
      vp,
    );
    expect(out).toHaveLength(1);
    expect(out[0].category).toBe("E-Commerce & Retail");
    expect(out[0].mood).toBe("Travel marketplace.");
    expect(out[0].palette_primary).toBe("Rausch (#ff385c)");
    expect(out[0].vendor_path).toBe(vp("airbnb")); // refreshed, not the stale path
  });

  test("adds a new system mechanically (category from categoryOf, mood + first hex from ds)", () => {
    const out = buildCatalogVendors(
      [{ name: "newcat", mood: "  Fresh mood  ", palette_summary: ["#abcdef", "#123456"] }],
      {},
      cat,
      vp,
    );
    expect(out[0]).toEqual({
      name: "newcat",
      category: "Themed & Unique",
      mood: "Fresh mood",
      palette_primary: "#abcdef",
      vendor_path: vp("newcat"),
    });
  });

  test("new system with no category falls back to Uncategorized; no palette → empty primary", () => {
    const out = buildCatalogVendors(
      [{ name: "bare", mood: "x", palette_summary: [] }],
      {},
      cat,
      vp,
    );
    expect(out[0].category).toBe("Uncategorized");
    expect(out[0].palette_primary).toBe("");
  });

  test("output is sorted by name", () => {
    const out = buildCatalogVendors(
      [
        { name: "zeta", mood: "", palette_summary: [] },
        { name: "alpha", mood: "", palette_summary: [] },
      ],
      {},
      cat,
      vp,
    );
    expect(out.map((v) => v.name)).toEqual(["alpha", "zeta"]);
  });
});

// ── Fix 1: content-true idempotence fast-path (acceptance 1/2/3) ────────────────
describe("pinnedContentAlreadyApplied — cheap no-op fast-path", () => {
  const ok = (dst: string) => ({ dst, ok: true, expected: "x", actual: "x" });
  const drift = (dst: string) => ({ dst, ok: false, expected: "x", actual: "y" });
  const hist = (...shas: string[]) =>
    shas.map((sha) => ({ event: "apply" as const, sha, at: "t", reason: "r" }));

  test("true when all paths verify AND the latest apply sha equals pinned_sha", () => {
    expect(
      pinnedContentAlreadyApplied([ok("a"), ok("b")], hist("OLD", "NEW"), "NEW"),
    ).toBe(true);
  });

  test("false when pinned_sha moved past the last apply (the --bump case)", () => {
    // bump set pinned_sha=NEW but the last apply was still OLD → must NOT no-op
    expect(
      pinnedContentAlreadyApplied([ok("a")], hist("OLD"), "NEW"),
    ).toBe(false);
  });

  test("false on any on-disk verify drift even if shas line up", () => {
    expect(
      pinnedContentAlreadyApplied([ok("a"), drift("b")], hist("NEW"), "NEW"),
    ).toBe(false);
  });

  test("false when pinned_sha is null or no apply history exists", () => {
    expect(pinnedContentAlreadyApplied([ok("a")], hist("NEW"), null)).toBe(false);
    expect(pinnedContentAlreadyApplied([ok("a")], [], "NEW")).toBe(false);
    expect(pinnedContentAlreadyApplied([], hist("NEW"), "NEW")).toBe(false);
  });

  test("uses the LATEST apply, ignoring non-apply history events", () => {
    const mixed = [
      { event: "bump" as const, sha: "NEW", at: "t", reason: "r" },
      { event: "apply" as const, sha: "OLD", at: "t", reason: "r" },
      { event: "bump" as const, sha: "NEW", at: "t", reason: "r" },
    ];
    // last apply is OLD, pinned is NEW → not applied yet
    expect(pinnedContentAlreadyApplied([ok("a")], mixed, "NEW")).toBe(false);
  });
});

// ── Fix 3: stale-count advisory (acceptance 5) ──────────────────────────────────
describe("scanStaleCounts — flag doc lines whose count != catalogue size", () => {
  test("flags a stale '73 systems' line when current is 150", () => {
    const hits = scanStaleCounts([{ path: "a.md", text: "see the available 73 systems here" }], 150);
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ path: "a.md", line: 1, found: 73 });
  });

  test("ignores a line whose count already matches the catalogue", () => {
    expect(scanStaleCounts([{ path: "a.md", text: "the available 150 systems" }], 150)).toEqual([]);
  });

  test("flags the '73 `DESIGN.md` directories' phrasing", () => {
    const hits = scanStaleCounts([{ path: "p.md", text: "vendor lives at X (73 `DESIGN.md` directories)" }], 150);
    expect(hits).toHaveLength(1);
    expect(hits[0].found).toBe(73);
  });

  test("matches 'design systems' with the optional 'design' word", () => {
    const hits = scanStaleCounts([{ path: "a.md", text: "all 73 design systems are vendored" }], 150);
    expect(hits).toHaveLength(1);
  });

  test("returns no hits for lines with no count pattern", () => {
    expect(scanStaleCounts([{ path: "a.md", text: "no numbers about the catalogue here" }], 150)).toEqual([]);
  });

  test("reports the right line number across a multi-line doc", () => {
    const text = "line one\nline two\nthe 73 design systems line\nline four";
    const hits = scanStaleCounts([{ path: "a.md", text }], 150);
    expect(hits).toHaveLength(1);
    expect(hits[0].line).toBe(3);
  });

  test("does NOT false-flag 'system-design' or 'shortlist 1-4 systems' prose", () => {
    const noise = [
      { path: "a.md", text: "Step 08 system-design feeds Step 12" },
      { path: "b.md", text: "shortlist 1-4 systems per direction" },
    ];
    expect(scanStaleCounts(noise, 150)).toEqual([]);
  });
});

// ── Spec 142: orphan-prune pure cores ──────────────────────────────────────────
describe("computeOrphans — on-disk minus staged (set difference)", () => {
  test("returns dst-relative paths present on disk but not in the staged set", () => {
    const onDisk = ["web-prototype/SKILL.md", "ad-creative/SKILL.md", "orbit-gmail/x.md"];
    const staged = ["web-prototype/SKILL.md"];
    expect(computeOrphans(onDisk, staged)).toEqual(["ad-creative/SKILL.md", "orbit-gmail/x.md"]);
  });

  test("empty when on-disk is a subset of staged", () => {
    expect(computeOrphans(["a/x", "b/y"], ["a/x", "b/y", "c/z"])).toEqual([]);
  });

  test("result is sorted (deterministic)", () => {
    expect(computeOrphans(["z/1", "a/1", "m/1"], [])).toEqual(["a/1", "m/1", "z/1"]);
  });
});

describe("topLevelBundles — unique first path segments", () => {
  test("collapses files to their bundle dir, unique + sorted", () => {
    const rel = ["web-prototype/SKILL.md", "web-prototype/assets/template.html", "ad-creative/SKILL.md"];
    expect(topLevelBundles(rel)).toEqual(["ad-creative", "web-prototype"]);
  });

  test("a top-level file maps to itself", () => {
    expect(topLevelBundles(["INDEX.json", "ad-creative/SKILL.md"])).toEqual(["INDEX.json", "ad-creative"]);
  });
});

describe("findReferencedOrphans — intersection with referenced names", () => {
  test("returns orphan bundles that a live file references (block set)", () => {
    const orphans = ["ad-creative", "web-prototype", "orbit-gmail"];
    const referenced = new Set(["web-prototype", "saas-landing"]);
    expect(findReferencedOrphans(orphans, referenced)).toEqual(["web-prototype"]);
  });

  test("empty when no orphan is referenced (the post-143 happy path)", () => {
    const orphans = ["ad-creative", "apple-hig", "orbit-gmail"];
    const referenced = new Set(["web-prototype", "saas-landing"]);
    expect(findReferencedOrphans(orphans, referenced)).toEqual([]);
  });
});

describe("assertDisjointRoots — reject overlapping recursive dst prefixes", () => {
  test("passes for disjoint roots", () => {
    expect(() =>
      assertDisjointRoots(["design-systems/", "vendor/open-design/skills/", "vendor/open-design/frames/"]),
    ).not.toThrow();
  });

  test("throws when one root is a path-prefix of another", () => {
    expect(() => assertDisjointRoots(["vendor/open-design/", "vendor/open-design/skills/"])).toThrow(
      /overlap/i,
    );
  });

  test("a shared name-prefix that is NOT a path-segment prefix is fine", () => {
    // "skills" vs "skills-extra" — not a path-segment ancestor
    expect(() => assertDisjointRoots(["a/skills/", "a/skills-extra/"])).not.toThrow();
  });
});
