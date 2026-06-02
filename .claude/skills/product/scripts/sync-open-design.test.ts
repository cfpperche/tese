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
