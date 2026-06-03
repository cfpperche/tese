/**
 * sync-open-design.ts — vendored open-design sync engine
 *
 * Lives inside the /product skill. Paths resolve from the skill root via
 * `import.meta.url`, invocation is `bun scripts/sync-open-design.ts` (no tsx shebang).
 *
 * Four subcommands:
 *   --check               Read-only: fetch upstream HEAD SHA, diff vs pinned, write daily report
 *   --bump <sha>          Manifest-only: update pinned_sha + history entry
 *   --apply               Write vendored content from tarball at pinned_sha
 *   --verify              Recompute per-path checksums vs MANIFEST.json; exit non-zero on drift
 *
 * SHA fetch strategy: `git ls-remote` (no GitHub API auth, no rate limit).
 * File diff strategy: `gh api repos/nexu-io/open-design/compare/<a>...<b>` when both SHAs
 *   are known — fallback to listing all vendored_paths as "potentially changed" when pinned_sha
 *   is null or gh is unavailable.
 */

import fs from 'node:fs/promises';
import { existsSync, mkdirSync, createWriteStream, readFileSync } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { promisify } from 'node:util';
import { pipeline } from 'node:stream';

const streamPipeline = promisify(pipeline);

// ── Paths ────────────────────────────────────────────────────────────────────
// Script lives at <skill-root>/scripts/sync-open-design.ts — `..` resolves to <skill-root>.
const SKILL_ROOT = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const MANIFEST_PATH = path.join(SKILL_ROOT, 'vendor/open-design/MANIFEST.json');
const RUNTIME_DIR = path.join(SKILL_ROOT, 'runtime/od-sync');
const DS_INDEX_PATH = path.join(SKILL_ROOT, 'vendor/open-design/.cache/ds-index.json');
const CATALOG_INDEX_PATH = path.join(SKILL_ROOT, 'references/od-catalog-index.json');
const DESIGN_SYSTEMS_DIR = path.join(SKILL_ROOT, 'design-systems');
// Repo-relative prefix the pipeline-facing catalogue stores in `vendor_path`
// (steps 02/14 reference this literal). Fallback when no existing catalogue
// declares a `source`; matches the one-off /tmp/gen-catalog.py reference impl.
const CATALOG_VENDOR_PREFIX = '.claude/skills/product/design-systems';
const UPSTREAM_URL = 'https://github.com/nexu-io/open-design';
const UPSTREAM_GIT = `${UPSTREAM_URL}.git`;

// ── Types ────────────────────────────────────────────────────────────────────
interface VendoredPath {
  src: string;
  dst: string;
  kind: string;
  recursive?: boolean;
  checksum: string | null;
}

interface HistoryEntry {
  event: 'bump' | 'apply' | 'check';
  sha: string;
  at: string;
  reason: string;
}

interface Manifest {
  $schema: string;
  upstream_url: string;
  pinned_sha: string | null;
  pinned_at: string | null;
  last_check_sha: string | null;
  last_check_at: string | null;
  vendored_paths: VendoredPath[];
  license_attribution: { path: string; license: string; source: string }[];
  history: HistoryEntry[];
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Minimum-viable field-presence check (ajv not available as a dependency;
 * required fields per schemas/od-vendor-manifest.schema.json).
 * Exported for direct unit testing.
 */
export function validateManifestShape(obj: unknown): void {
  const REQUIRED_FIELDS: (keyof Manifest)[] = [
    'pinned_sha',
    'last_check_sha',
    'last_check_at',
    'vendored_paths',
  ];
  for (const field of REQUIRED_FIELDS) {
    if (!(field in (obj as Record<string, unknown>))) {
      throw new Error(`manifest schema violation: missing required field ${field}`);
    }
  }
}

async function readManifest(): Promise<Manifest> {
  const raw = await fs.readFile(MANIFEST_PATH, 'utf-8');
  const parsed = JSON.parse(raw) as Manifest;
  validateManifestShape(parsed);
  return parsed;
}

/**
 * Compute a tree-level checksum from the sorted list of per-file checksums.
 * Deterministic regardless of file-walk order.
 * Exported for direct unit testing.
 */
export function computeTreeChecksum(fileChecksums: string[]): string {
  const sorted = [...fileChecksums].sort();
  return `sha256:${crypto.createHash('sha256').update(sorted.join('')).digest('hex')}`;
}

async function writeManifest(m: Manifest): Promise<void> {
  const tmp = MANIFEST_PATH + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(m, null, 2) + '\n', 'utf-8');
  await fs.rename(tmp, MANIFEST_PATH);
}

function nowISO(): string {
  return new Date().toISOString();
}

function todayDateStr(): string {
  return new Date().toISOString().slice(0, 10);
}

function ensureRuntimeDir(): void {
  mkdirSync(RUNTIME_DIR, { recursive: true });
}

/** Fetch upstream HEAD SHA via git ls-remote (no auth, no rate limit). */
export function fetchUpstreamHead(gitUrl = UPSTREAM_GIT): string {
  const result = spawnSync('git', ['ls-remote', gitUrl, 'HEAD'], {
    encoding: 'utf-8',
    timeout: 30_000,
  });
  if (result.status !== 0) {
    throw new Error(`git ls-remote failed: ${result.stderr?.trim() || 'unknown error'}`);
  }
  const line = result.stdout?.trim().split('\n')[0] ?? '';
  const sha = line.split('\t')[0];
  if (!sha || !/^[0-9a-f]{40}$/.test(sha)) {
    throw new Error(`Unexpected git ls-remote output: ${result.stdout}`);
  }
  return sha;
}

/** Validate a SHA exists at upstream. Tries `git ls-remote` first (named refs only),
 * falls back to `gh api repos/.../commits/<sha>` for arbitrary commit SHAs. */
export function shaExistsUpstream(sha: string, gitUrl = UPSTREAM_GIT): boolean {
  const result = spawnSync('git', ['ls-remote', gitUrl, sha], {
    encoding: 'utf-8',
    timeout: 30_000,
  });
  if (result.status === 0 && result.stdout.trim().length > 0) return true;

  const ghResult = spawnSync(
    'gh',
    ['api', `repos/nexu-io/open-design/commits/${sha}`, '--jq', '.sha'],
    { encoding: 'utf-8', timeout: 20_000 },
  );
  return ghResult.status === 0 && ghResult.stdout.trim() === sha;
}

/** SHA-256 hex of a Buffer. */
function sha256hex(buf: Buffer): string {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

/** Provenance comment prefix for a given file extension. */
function provenanceHeader(sha: string, srcPath: string, ext: string): string | null {
  const comment = `vendored from open-design@${sha}:${srcPath} · do not edit`;
  if (['.md', '.html'].includes(ext)) return `<!-- ${comment} -->\n`;
  if (['.ts', '.tsx'].includes(ext)) return `// ${comment}\n`;
  return null; // .json, binaries — checksum-only
}

/**
 * Required H2 section substrings for a DESIGN.md file (case-insensitive).
 *
 * Substring checks cover both the numbered upstream section names
 * (`## 1. Visual Theme & Atmosphere`) and the unnumbered starter-file variants.
 * Original section keywords were too narrow and matched 0/72 files — relaxed to
 * match the real section names emitted by open-design@454e8373.
 */
// The vendored design-systems/<name>/DESIGN.md catalogue is consumed two ways, and
// NEITHER depends on specific H2 heading text (consumer audit — spec 135 notes.md):
//   - machine: `generateDsIndex` reads `mood` (a blockquote/title) + `palette_summary`
//     (the first #RRGGBB hex codes). The palette is the one hard structured dependency.
//   - LLM: step 02-prototype `Read`s the whole file as prose and is robust to heading
//     renames (`## 2. Color` reads the same as `## 2. Color Palette & Roles`).
// So the gate validates *consumable substance*, not heading names: a usable palette
// plus a corruption tripwire (enough H2 sections that the file isn't a truncated stub).
// The earlier hand-maintained REQUIRED_H2_SUBSTRINGS list enforced a contract no
// consumer read and false-rejected legitimate systems (`wechat`, abbreviated-heading
// systems) — see spec 135.
//
// Hex detection is `#RRGGBB`-only, deliberately matching `generateDsIndex`'s
// `palette_summary` exactly — if a future upstream system expressed colors only as
// oklch()/hsl(), BOTH this gate and the index would need updating together, and this
// gate failing is the correct early signal.
//
// MIN_PALETTE_HEX = 2: a monochrome system (black + white) is a legitimate, common
// pattern (`spacex` #000000 + #f0f0fa; `figma` #000000 + #ffffff). The floor catches a
// palette-less/truncated file (0-1 hex) without false-rejecting mono systems. Section
// floor sits below every observed real system (claude/flat 9, wechat 8). Both surfaced
// during spec 135 validation, where 3 would have wrongly rejected spacex + figma.
export const MIN_PALETTE_HEX = 2;
export const MIN_H2_SECTIONS = 3;

/**
 * Validate a vendored DESIGN.md carries consumable substance. Returns a list of
 * human-readable problems (empty array = OK). Signature is intentionally unchanged
 * so `cmdApply` Phase A and its `report.schemaFailures` wiring keep working.
 */
export function validateDesignMd(content: string): string[] {
  const problems: string[] = [];

  const uniqueHex = new Set(
    (content.match(/#[0-9a-fA-F]{6}\b/g) ?? []).map((h) => h.toLowerCase()),
  ).size;
  if (uniqueHex < MIN_PALETTE_HEX) {
    problems.push(`palette: ${uniqueHex} unique hex color(s), need >=${MIN_PALETTE_HEX}`);
  }

  const h2Count = content.split('\n').filter((line) => line.startsWith('## ')).length;
  if (h2Count < MIN_H2_SECTIONS) {
    problems.push(`structure: ${h2Count} H2 section(s), need >=${MIN_H2_SECTIONS}`);
  }

  return problems;
}

/**
 * GitHub's `compare` REST endpoint caps the returned `.files[]` array at 300
 * entries and offers no working pagination for it (`--paginate` only expands the
 * commit list). A diff at or above this cap may be silently truncated.
 */
export const COMPARE_FILE_CAP = 300;

export interface ChangedVendoredScope {
  /** Lines to render under "Files changed in vendored scope". */
  display: string[];
  /** true when the result is an over-report (we could not enumerate precisely). */
  imprecise: boolean;
  reason: 'precise' | 'truncated' | 'unavailable';
}

/**
 * Decide which vendored paths to flag as changed from a `gh compare` file list.
 *
 * A drift detector must never emit a false "no changes". Two cases force an
 * over-report of ALL vendored srcs (imprecise) instead of trusting the list:
 *   - gh unavailable / empty output  → we have no list at all.
 *   - list length ≥ COMPARE_FILE_CAP → GitHub likely truncated it, so a precise
 *     filter could miss vendored-scope changes that fell past the cap (Bug A:
 *     1738-commit diff returned 300 unrelated files, zero design-systems/ → a
 *     false "no changes in vendored paths").
 * Only a reliably-complete list is filtered precisely.
 */
export function resolveChangedVendoredScope(
  changedFiles: string[],
  vendoredSrcs: string[],
  ghAvailable: boolean,
): ChangedVendoredScope {
  if (!ghAvailable || changedFiles.length === 0) {
    return { display: vendoredSrcs, imprecise: true, reason: 'unavailable' };
  }
  if (changedFiles.length >= COMPARE_FILE_CAP) {
    return { display: vendoredSrcs, imprecise: true, reason: 'truncated' };
  }
  const display = changedFiles.filter((f) => vendoredSrcs.some((src) => f.startsWith(src)));
  return { display, imprecise: false, reason: 'precise' };
}

/** Recursively list all files under `dir`, excluding `.gitkeep` scaffold markers
 * (vendor subdirs carry `.gitkeep` so they exist in fresh clones; those markers are
 * never part of the upstream tarball and never enter a manifest tree checksum). */
function walkFiles(dir: string): string[] {
  const result = spawnSync('find', [dir, '-type', 'f'], { encoding: 'utf-8', timeout: 30_000 });
  if (result.status !== 0) return [];
  return result.stdout
    .trim()
    .split('\n')
    .filter(Boolean)
    .filter((f) => path.basename(f) !== '.gitkeep');
}

// ── --check ──────────────────────────────────────────────────────────────────

async function cmdCheck(): Promise<void> {
  const manifest = await readManifest();
  ensureRuntimeDir();

  const upstreamHead = fetchUpstreamHead();
  const reportLines: string[] = [
    `# OD Sync Check — ${todayDateStr()}`,
    '',
    `**upstream HEAD:** \`${upstreamHead}\``,
    `**pinned_sha:**    \`${manifest.pinned_sha ?? 'null'}\``,
    '',
  ];

  if (!manifest.pinned_sha) {
    reportLines.push('> No pin yet — run `--bump <sha> --reason "..."` first.');
    reportLines.push('');
    reportLines.push('## Vendored paths');
    reportLines.push('_(none — MANIFEST.vendored_paths is empty)_');
  } else if (manifest.pinned_sha === upstreamHead) {
    reportLines.push('> Pinned SHA matches upstream HEAD — **in sync**.');
  } else {
    reportLines.push(`> Pinned SHA differs from upstream HEAD.`);
    reportLines.push('');

    // Attempt gh compare to list changed files; fall back gracefully when gh is
    // absent or rate-limited (consumers running --check won't reliably have gh).
    let changedFiles: string[] = [];
    const ghResult = spawnSync(
      'gh',
      [
        'api',
        `repos/nexu-io/open-design/compare/${manifest.pinned_sha}...${upstreamHead}`,
        '--jq',
        '.files[].filename',
      ],
      { encoding: 'utf-8', timeout: 20_000 },
    );

    const ghAvailable = ghResult.status === 0 && Boolean(ghResult.stdout.trim());
    if (ghAvailable) {
      changedFiles = ghResult.stdout.trim().split('\n').filter(Boolean);
    }

    const vendoredSrcs = manifest.vendored_paths.map((vp) => vp.src);
    const scope = resolveChangedVendoredScope(changedFiles, vendoredSrcs, ghAvailable);

    if (scope.imprecise) {
      const why =
        scope.reason === 'truncated'
          ? `diff exceeds GitHub's ${COMPARE_FILE_CAP}-file compare cap (truncated)`
          : '`gh` compare unavailable or rate-limited';
      reportLines.push(
        `> ${why} — cannot enumerate precisely; listing all vendored paths as **potentially changed**. Run \`--apply\` to reconcile.`,
      );
    }

    reportLines.push('## Files changed in vendored scope');
    if (scope.display.length === 0) {
      reportLines.push('_(no changes in vendored paths)_');
    } else {
      scope.display.forEach((f) => reportLines.push(`- \`${f}\``));
    }
  }

  reportLines.push('');
  reportLines.push('## Vendored paths');
  if (manifest.vendored_paths.length === 0) {
    reportLines.push('_(none)_');
  } else {
    manifest.vendored_paths.forEach((vp) => {
      reportLines.push(
        `- \`${vp.src}\` → \`${vp.dst}\` (kind: ${vp.kind}, checksum: ${vp.checksum ?? 'not yet applied'})`,
      );
    });
  }

  const reportPath = path.join(RUNTIME_DIR, `${todayDateStr()}.md`);
  await fs.writeFile(reportPath, reportLines.join('\n') + '\n', 'utf-8');
  console.log(`Report written → ${reportPath}`);

  // Mutate manifest: update last_check_sha + last_check_at only
  manifest.last_check_sha = upstreamHead;
  manifest.last_check_at = nowISO();
  await writeManifest(manifest);

  console.log(`last_check_sha updated to ${upstreamHead}`);
}

// ── --bump ───────────────────────────────────────────────────────────────────

async function cmdBump(sha: string, reason: string): Promise<void> {
  if (!/^[0-9a-f]{40}$/.test(sha)) {
    throw new Error(`Invalid SHA format: "${sha}". Must be 40-character lowercase hex.`);
  }
  if (!reason) {
    throw new Error('--reason is required for --bump. Provide a human-readable explanation.');
  }

  console.log(`Validating SHA ${sha} exists upstream…`);
  if (!shaExistsUpstream(sha)) {
    throw new Error(`SHA ${sha} not found upstream at ${UPSTREAM_GIT}`);
  }

  const manifest = await readManifest();
  const at = nowISO();

  manifest.pinned_sha = sha;
  manifest.pinned_at = at;
  manifest.history.push({ event: 'bump', sha, at, reason });

  await writeManifest(manifest);

  console.log(`Bumped pinned_sha → ${sha}`);
  console.log(`Reason: ${reason}`);
  console.log(`Recorded in MANIFEST history.`);
}

// ── --apply ──────────────────────────────────────────────────────────────────

/**
 * Two-phase atomic apply:
 *
 * Phase A: Build all output content in memory + validate ALL DESIGN.md files.
 *          Write to a staging dir. On any schema failure → leave staging, throw,
 *          do not touch live vendor.
 *
 * Phase B: Only reached when Phase A passes with zero failures. Move each staged
 *          file to its final dst via rename. Update manifest checksums.
 *
 * Invariant: live vendor files are never touched until ALL validation passes.
 */
async function cmdApply(): Promise<void> {
  const manifest = await readManifest();

  if (!manifest.pinned_sha) {
    throw new Error('pinned_sha is null — run `--bump <sha> --reason "..."` first.');
  }

  const sha = manifest.pinned_sha;
  ensureRuntimeDir();

  const tarballPath = path.join(RUNTIME_DIR, `tarball-${sha}.tar.gz`);
  const extractDir = path.join(RUNTIME_DIR, `extracted-${sha}`);
  const stagingDir = path.join(RUNTIME_DIR, `staging-${sha}`);
  const archiveRoot = `open-design-${sha}`;

  // ── Idempotence fast-path (network-free) — spec 141 ───────────────────────
  // On-disk is provably == content-at-pinned-sha when every path verifies AND the
  // last apply recorded this pinned_sha. After a `--bump` the latest apply lags
  // pinned_sha → this is false → we fall through to download + stage + content-
  // compare (the slow-path after Phase A). This replaces the old gate that
  // compared on-disk against the STALE manifest checksums and blind-skipped
  // recursive trees (`if (vp.recursive) continue`) — the two bugs that made a
  // `--bump`+`--apply` false-no-op. `verifyManifest` content-compares trees correctly.
  if (pinnedContentAlreadyApplied(verifyManifest(manifest, SKILL_ROOT), manifest.history, sha)) {
    console.log('no-op (already in sync)');
    return;
  }

  // ── Download tarball ─────────────────────────────────────────────────────
  if (!existsSync(tarballPath)) {
    const tarUrl = `${UPSTREAM_URL}/archive/${sha}.tar.gz`;
    console.log(`Downloading ${tarUrl} …`);
    const response = await fetch(tarUrl);
    if (!response.ok) {
      throw new Error(`Failed to download tarball: ${response.status} ${response.statusText}`);
    }
    const writer = createWriteStream(tarballPath);
    await streamPipeline(response.body as unknown as NodeJS.ReadableStream, writer);
    console.log(`Tarball saved → ${tarballPath}`);
  } else {
    console.log(`Reusing cached tarball at ${tarballPath}`);
  }

  // ── Extract tarball ──────────────────────────────────────────────────────
  mkdirSync(extractDir, { recursive: true });
  const tarResult = spawnSync('tar', ['-xzf', tarballPath, '-C', extractDir], {
    encoding: 'utf-8',
    timeout: 60_000,
  });
  if (tarResult.status !== 0) {
    throw new Error(`tar extraction failed: ${tarResult.stderr?.trim()}`);
  }
  console.log(`Extracted to ${extractDir}`);

  // ── Phase A: stage + validate ALL files (no live dst writes yet) ─────────
  const at = nowISO();
  const report: {
    added: string[];
    updated: string[];
    removed: string[];
    schemaFailures: string[];
  } = { added: [], updated: [], removed: [], schemaFailures: [] };

  const staged: Array<{ dstFull: string; stagedPath: string; checksum: string; vp: VendoredPath }> = [];
  const updatedPaths: VendoredPath[] = [];

  mkdirSync(stagingDir, { recursive: true });
  console.log(`Staging to ${stagingDir} …`);

  for (const vp of manifest.vendored_paths) {
    const srcFull = path.join(extractDir, archiveRoot, vp.src);
    const dstFull = path.join(SKILL_ROOT, vp.dst);

    if (vp.recursive) {
      const walkResult = spawnSync('find', [srcFull, '-type', 'f'], {
        encoding: 'utf-8',
        timeout: 10_000,
      });
      if (walkResult.status !== 0 || !existsSync(srcFull)) {
        report.removed.push(vp.src);
        updatedPaths.push(vp);
        continue;
      }

      const files = walkResult.stdout.trim().split('\n').filter(Boolean);
      for (const fileSrc of files) {
        const relPath = path.relative(path.join(extractDir, archiveRoot), fileSrc);
        const fileDst = path.join(SKILL_ROOT, vp.dst, path.relative(vp.src, relPath));

        const entry = await stageFile({
          fileSrc,
          fileDst,
          sha,
          srcPath: relPath,
          stagingDir,
          report,
          vp,
        });
        if (entry) staged.push(entry);
      }
      updatedPaths.push({ ...vp });
    } else {
      if (!existsSync(srcFull)) {
        report.removed.push(vp.src);
        updatedPaths.push(vp);
        continue;
      }
      const entry = await stageFile({
        fileSrc: srcFull,
        fileDst: dstFull,
        sha,
        srcPath: vp.src,
        stagingDir,
        report,
        vp,
      });
      if (entry) staged.push(entry);
    }
  }

  if (report.schemaFailures.length > 0) {
    const failures = report.schemaFailures.join(', ');
    throw new Error(
      `DESIGN.md schema validation failed for: ${failures}.\n` +
      `Staging preserved at ${stagingDir} for inspection. Manifest not updated.`,
    );
  }

  // ── Slow-path no-op — spec 141 ────────────────────────────────────────────
  // Reached only when the fast-path could not decide (a `--bump` moved pinned_sha,
  // or on-disk drift). The staged checksums ARE the content at pinned_sha (header-
  // included, tree-aware). If every vendored path's staged checksum already equals
  // its on-disk checksum AND nothing was removed from the tarball, on-disk is
  // already == pinned content → short-circuit before the Phase B rename + manifest
  // rewrite. (Tarball is cached, so a repeated post-bump no-op stays cheap.)
  const wouldBeChecksum = new Map<VendoredPath, string>();
  for (const vp of manifest.vendored_paths) {
    const entries = staged.filter((e) => e.vp === vp);
    if (entries.length === 0) continue;
    wouldBeChecksum.set(
      vp,
      vp.recursive ? computeTreeChecksum(entries.map((e) => e.checksum)) : entries[0].checksum,
    );
  }
  const onDiskNow = verifyManifest(manifest, SKILL_ROOT);
  const stagedMatchesOnDisk =
    report.removed.length === 0 &&
    manifest.vendored_paths.every((vp) => {
      const wb = wouldBeChecksum.get(vp);
      if (wb === undefined) return false;
      return onDiskNow.find((r) => r.dst === vp.dst)?.actual === wb;
    });
  if (stagedMatchesOnDisk && manifest.vendored_paths.length > 0) {
    console.log('no-op (already in sync — staged content matches on-disk)');
    await fs.rm(stagingDir, { recursive: true, force: true });
    return;
  }

  // ── Orphan-prune planning (spec 142) — compute + guard BEFORE any Phase B write ──
  // An orphan = a dst file on disk absent from the staged set (the content at
  // pinned_sha). Compute per recursive vp and run the referenced-bundle guard now,
  // so a hard-block throws before any live mutation (live vendor left intact).
  const recursiveVps = manifest.vendored_paths.filter((vp) => vp.recursive);
  assertDisjointRoots(recursiveVps.map((vp) => vp.dst));
  const orphansByVp = new Map<VendoredPath, string[]>();
  for (const vp of recursiveVps) {
    const dstRootAbs = path.join(SKILL_ROOT, vp.dst);
    if (!existsSync(dstRootAbs)) continue;
    const stagedRel = staged
      .filter((e) => e.vp === vp)
      .map((e) => path.relative(dstRootAbs, e.dstFull));
    const onDiskRel = walkFiles(dstRootAbs).map((f) => path.relative(dstRootAbs, f));
    const orphans = computeOrphans(onDiskRel, stagedRel);
    if (orphans.length > 0) orphansByVp.set(vp, orphans);
  }
  const allOrphanBundles = topLevelBundles([...orphansByVp.values()].flat());
  if (allOrphanBundles.length > 0) {
    const referenced = findReferencedOrphans(allOrphanBundles, scanReferencedBundles(allOrphanBundles));
    if (referenced.length > 0) {
      throw new Error(
        `orphan-prune blocked: ${referenced.length} orphaned bundle(s) still referenced by pipeline templates — ` +
        `${referenced.join(', ')}. Re-point the vendor mapping or update the references first. Live vendor left untouched.`,
      );
    }
  }

  // ── Phase B: atomic move staging → final dst ─────────────────────────────
  console.log(`Validation passed (${staged.length} files). Moving staging → dst …`);
  for (const { dstFull, stagedPath, checksum, vp } of staged) {
    const existed = existsSync(dstFull);
    if (existed) {
      report.updated.push(dstFull);
    } else {
      report.added.push(dstFull);
    }

    mkdirSync(path.dirname(dstFull), { recursive: true });
    await fs.rename(stagedPath, dstFull);

    vp.checksum = checksum;
  }

  // For tree (recursive) entries, replace the last-file checksum with a
  // deterministic tree digest over all per-file checksums.
  const treeVps = new Set(staged.filter((e) => e.vp.recursive).map((e) => e.vp));
  for (const treeVp of treeVps) {
    const fileChecksums = staged.filter((e) => e.vp === treeVp).map((e) => e.checksum);
    treeVp.checksum = computeTreeChecksum(fileChecksums);
  }

  await fs.rm(stagingDir, { recursive: true, force: true });

  // ── Orphan prune (spec 142) — move to trash journal, finalized after success ──
  // The tree checksums above are staged-only, so the manifest already describes the
  // post-prune dst. Move orphans OUTSIDE the vendored root (a quarantine inside it
  // would be re-hashed by verifyManifest/walkFiles) so a mid-write crash is a local
  // restore, not a re-download. The journal is rm'd once manifest+report succeed.
  const trashDir = path.join(RUNTIME_DIR, `pruned-${sha.slice(0, 12)}`);
  const prunedRel: string[] = [];
  for (const [vp, orphans] of orphansByVp) {
    const dstRootAbs = path.join(SKILL_ROOT, vp.dst);
    for (const rel of orphans) {
      const to = path.join(trashDir, vp.dst, rel);
      mkdirSync(path.dirname(to), { recursive: true });
      await fs.rename(path.join(dstRootAbs, rel), to);
      prunedRel.push(path.join(vp.dst, rel));
    }
    // sweep now-empty dirs left under the dst root (never the root itself)
    spawnSync('find', [dstRootAbs, '-mindepth', '1', '-type', 'd', '-empty', '-delete'], {
      timeout: 30_000,
    });
  }
  if (prunedRel.length > 0) {
    console.log(`Pruned ${prunedRel.length} orphan file(s) → journal ${trashDir}`);
  }

  // ── Atomic manifest update ───────────────────────────────────────────────
  manifest.history.push({ event: 'apply', sha, at, reason: 'auto-apply' });
  for (const up of updatedPaths) {
    const vp = manifest.vendored_paths.find((v) => v.src === up.src);
    if (vp && vp.checksum) up.checksum = vp.checksum;
  }

  await writeManifest(manifest);

  // ── Regenerate both consumed indices (spec 141) ──────────────────────────
  // ds-index.json is the engine/MCP cache; od-catalog-index.json is the
  // pipeline-facing curated catalogue steps 02 + 14 actually Read. The old
  // `--apply` regenerated only the former, leaving new systems invisible to
  // /product — acceptance 4 fixes that by regenerating both.
  await generateDsIndex(sha);
  const catalogCount = await generateCatalogIndex();

  // ── Stale-count advisory (acceptance 5) ───────────────────────────────────
  // Non-blocking: flag tracked OD docs whose hard-coded system count no longer
  // matches the catalogue. Reports only — never edits, never fails the apply.
  const staleHits = await scanAllowlistStaleCounts(catalogCount);

  // ── Write apply report ───────────────────────────────────────────────────
  const reportPath = path.join(RUNTIME_DIR, `apply-${sha.slice(0, 12)}.md`);
  const reportLines = [
    `# OD Sync Apply — ${sha.slice(0, 12)}`,
    '',
    `**sha:** \`${sha}\``,
    `**at:** ${at}`,
    `**catalogue systems:** ${catalogCount}`,
    '',
    `## Added (${report.added.length})`,
    ...report.added.map((f) => `- \`${f}\``),
    '',
    `## Updated (${report.updated.length})`,
    ...report.updated.map((f) => `- \`${f}\``),
    '',
    `## Removed from tarball (${report.removed.length})`,
    ...report.removed.map((f) => `- \`${f}\``),
    '',
    `## Pruned orphans (${prunedRel.length})`,
    ...(prunedRel.length === 0
      ? ['_none — on-disk recursive trees matched the pinned content_']
      : prunedRel.map((f) => `- \`${f}\``)),
    '',
    `## Stale count advisory (${staleHits.length})`,
    ...(staleHits.length === 0
      ? ['_none — all checked docs reference the current count_']
      : staleHits.map((h) => `- \`${h.path}:${h.line}\` says ${h.found}, expected ${catalogCount} — \`${h.text}\``)),
    '',
  ];
  await fs.writeFile(reportPath, reportLines.join('\n') + '\n', 'utf-8');
  if (staleHits.length > 0) {
    console.warn(`stale-count advisory: ${staleHits.length} doc line(s) reference an outdated system count (see apply report).`);
  }
  console.log(`Apply report → ${reportPath}`);

  // ── Finalize prune: success → drop the trash journal (was a crash-recovery aid) ──
  if (prunedRel.length > 0) {
    await fs.rm(trashDir, { recursive: true, force: true });
  }

  console.log(
    `Done: ${report.added.length} added, ${report.updated.length} updated, ${report.removed.length} removed, ${prunedRel.length} pruned.`,
  );
}

interface StageFileArgs {
  fileSrc: string;
  fileDst: string;
  sha: string;
  srcPath: string;
  stagingDir: string;
  report: { added: string[]; updated: string[]; removed: string[]; schemaFailures: string[] };
  vp: VendoredPath;
}

interface StageFileResult {
  dstFull: string;
  stagedPath: string;
  checksum: string;
  vp: VendoredPath;
}

/**
 * Phase A worker: validate + build output bytes + write to stagingDir.
 * Does NOT touch the final dst. Returns a StageFileResult for Phase B,
 * or null if schema validation failed (failure recorded in report.schemaFailures).
 */
async function stageFile({
  fileSrc,
  fileDst,
  sha,
  srcPath,
  stagingDir,
  report,
  vp,
}: StageFileArgs): Promise<StageFileResult | null> {
  const ext = path.extname(fileSrc).toLowerCase();
  const rawBytes = await fs.readFile(fileSrc);

  const isDesignMd =
    (vp.kind === 'design-system-tree' || srcPath.endsWith('DESIGN.md')) &&
    path.basename(fileSrc) === 'DESIGN.md';

  if (isDesignMd) {
    const content = rawBytes.toString('utf-8');
    const problems = validateDesignMd(content);
    if (problems.length > 0) {
      report.schemaFailures.push(`${srcPath} (${problems.join('; ')})`);
      return null;
    }
  }

  const header = provenanceHeader(sha, srcPath, ext);
  const outBytes = header ? Buffer.concat([Buffer.from(header, 'utf-8'), rawBytes]) : rawBytes;

  const checksum = `sha256:${sha256hex(outBytes)}`;

  const relToDst = path.relative(SKILL_ROOT, fileDst);
  const stagedPath = path.join(stagingDir, relToDst);
  mkdirSync(path.dirname(stagedPath), { recursive: true });
  await fs.writeFile(stagedPath, outBytes);

  return { dstFull: fileDst, stagedPath, checksum, vp };
}

// ── --verify ─────────────────────────────────────────────────────────────────

export interface VerifyResult {
  dst: string;
  ok: boolean;
  expected: string | null;
  actual: string | null;
  note?: string;
}

/**
 * Recompute the on-disk checksum for every `vendored_paths[]` entry and compare
 * it to the value recorded in the manifest. Pure (no process.exit) so tests can
 * drive it against a fixture tree. Exported for direct unit testing.
 *
 * Tree entries are hashed exactly the way `--apply` produced them: walk the dst
 * dir (excluding `.gitkeep`), sha256 each file *including* its provenance header,
 * then `computeTreeChecksum` over the sorted per-file digests.
 */
export function verifyManifest(manifest: Manifest, root: string): VerifyResult[] {
  return manifest.vendored_paths.map((vp) => {
    const dstFull = path.join(root, vp.dst);
    if (!existsSync(dstFull)) {
      return { dst: vp.dst, ok: false, expected: vp.checksum, actual: null, note: 'missing on disk' };
    }
    let actual: string;
    if (vp.recursive) {
      const checksums = walkFiles(dstFull).map((f) => `sha256:${sha256hex(readFileSync(f))}`);
      actual = computeTreeChecksum(checksums);
    } else {
      actual = `sha256:${sha256hex(readFileSync(dstFull))}`;
    }
    return { dst: vp.dst, ok: actual === vp.checksum, expected: vp.checksum, actual };
  });
}

/**
 * Cheap, network-free idempotence fast-path for `--apply` (spec 141, acceptance 1/2).
 *
 * Returns true ONLY when on-disk content is provably equal to the content at
 * `pinnedSha`, decided without downloading the tarball:
 *   - every vendored path verifies against the manifest (on-disk == recorded
 *     checksums, recursive trees included — `verifyManifest` already handles those), AND
 *   - the most recent `apply` history event recorded `pinnedSha`.
 * When both hold, on-disk == content-at-last-apply == content-at-pinned-sha by
 * transitivity. After a `--bump` the latest apply sha lags `pinnedSha`, so this
 * returns false and the caller falls to the download+stage slow-path — which is
 * exactly the bug the old manifest-compare gate masked (it false-no-op'd the bump).
 * Exported for direct unit testing.
 */
export function pinnedContentAlreadyApplied(
  verifyResults: VerifyResult[],
  history: HistoryEntry[],
  pinnedSha: string | null,
): boolean {
  if (!pinnedSha) return false;
  if (verifyResults.length === 0) return false;
  if (!verifyResults.every((r) => r.ok)) return false;
  const applies = history.filter((h) => h.event === 'apply');
  const lastApply = applies.length > 0 ? applies[applies.length - 1] : null;
  return lastApply?.sha === pinnedSha;
}

/**
 * Scan doc text for hard-coded catalogue-size counts that no longer match the
 * current system count (spec 141, acceptance 5). Pure + exported for unit testing;
 * the `--apply` report calls it over a fixed allowlist of OD-related docs and lists
 * any hit so a count change does not silently rot the prose. Reports only.
 *
 * Patterns are deliberately context-specific (not a bare `<N> systems`) so the
 * scan does not false-flag prose like "Step 08 system-design" or "shortlist 1-4
 * systems": only `<N> design systems`, `available <N> systems`, and
 * `<N> [`]DESIGN.md` — the catalogue-size phrasings the 73→150 advance left stale.
 * A line is flagged iff it carries a matched count != currentCount.
 */
export interface StaleCountHit {
  path: string;
  line: number;
  text: string;
  found: number;
}

const STALE_COUNT_PATTERNS = [
  /\b(\d+)\s+design\s+systems?\b/gi,
  /\bavailable\s+(\d+)\s+systems?\b/gi,
  /\b(\d+)\s+`?DESIGN\.md/gi,
];

export function scanStaleCounts(
  files: { path: string; text: string }[],
  currentCount: number,
): StaleCountHit[] {
  const hits: StaleCountHit[] = [];
  for (const f of files) {
    f.text.split('\n').forEach((lineText, i) => {
      const found: number[] = [];
      for (const re of STALE_COUNT_PATTERNS) {
        for (const m of lineText.matchAll(re)) found.push(Number(m[1]));
      }
      const stale = found.find((n) => n !== currentCount);
      if (stale !== undefined) {
        hits.push({ path: f.path, line: i + 1, text: lineText.trim(), found: stale });
      }
    });
  }
  return hits;
}

// ── Orphan-prune pure cores (spec 142) ─────────────────────────────────────────
// An "orphan" is a dst file present on disk but absent from the staged set (the
// content at pinned_sha). `--apply` historically never deleted them, so an
// upstream removal lingered forever and poisoned `verifyManifest`'s dst walk.
// These are pure + exported for unit testing; the FS walk + the move-to-trash
// prune execution live in cmdApply.

/** dst-relative paths on disk minus the staged set, sorted (deterministic). */
export function computeOrphans(onDiskRel: string[], stagedRel: string[]): string[] {
  const staged = new Set(stagedRel);
  return onDiskRel.filter((p) => !staged.has(p)).sort();
}

/** Unique first path segment (bundle dir, or a top-level file) per rel path, sorted. */
export function topLevelBundles(relPaths: string[]): string[] {
  return [...new Set(relPaths.map((p) => p.split('/')[0]).filter(Boolean))].sort();
}

/**
 * Orphan bundles a live non-vendor file still references (set intersection), sorted.
 * A non-empty result is a hard-block condition: pruning a referenced bundle would
 * leave the repo pointing at a deleted path (spec 142 OQ2 — block, don't silently delete).
 */
export function findReferencedOrphans(orphanBundles: string[], referencedNames: Set<string>): string[] {
  return orphanBundles.filter((b) => referencedNames.has(b)).sort();
}

/**
 * Throw if any recursive dst root is a path-segment ancestor of another — a parent
 * root would otherwise treat a child root's files as orphans and cross-delete them
 * (spec 142 nested-root guard). Today the roots are disjoint; this makes it an invariant.
 */
export function assertDisjointRoots(recursiveDsts: string[]): void {
  const norm = recursiveDsts.map((d) => d.replace(/\/+$/, ''));
  for (let i = 0; i < norm.length; i++) {
    for (let j = 0; j < norm.length; j++) {
      if (i === j) continue;
      if ((norm[j] + '/').startsWith(norm[i] + '/')) {
        throw new Error(
          `vendored-root overlap: "${recursiveDsts[i]}" is an ancestor of "${recursiveDsts[j]}" — orphan-prune would cross-delete`,
        );
      }
    }
  }
}

/**
 * FS wrapper for the referenced-bundle guard: of the candidate orphan bundle names,
 * return the set a live pipeline template (or SKILL.md) still references by path
 * (`skills/<bundle>` as a path segment). A non-empty result hard-blocks the prune.
 */
function scanReferencedBundles(candidates: string[]): Set<string> {
  const found = new Set<string>();
  if (candidates.length === 0) return found;
  const files = [
    ...walkFiles(path.join(SKILL_ROOT, 'templates/pipeline')),
    path.join(SKILL_ROOT, 'SKILL.md'),
  ].filter((f) => existsSync(f) && /\.(md|markdown|ts|tsx|json)$/.test(f));
  let blob = '';
  for (const f of files) {
    try {
      blob += readFileSync(f, 'utf-8');
    } catch {
      /* unreadable file → skip */
    }
  }
  for (const b of candidates) {
    const esc = b.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // referenced iff "skills/<bundle>" appears as a path segment (not a longer name)
    if (new RegExp(`skills/${esc}(?![\\w-])`).test(blob)) found.add(b);
  }
  return found;
}

async function cmdVerify(): Promise<void> {
  const manifest = await readManifest();
  const results = verifyManifest(manifest, SKILL_ROOT);
  const mismatches = results.filter((r) => !r.ok);

  if (mismatches.length > 0) {
    console.error(`OD vendor verify FAILED — ${mismatches.length}/${results.length} path(s) drifted:`);
    for (const m of mismatches) {
      console.error(`  - ${m.dst}`);
      console.error(`      expected: ${m.expected ?? '(none)'}`);
      console.error(`      actual:   ${m.actual ?? '(missing)'}${m.note ? ` (${m.note})` : ''}`);
    }
    console.error('');
    console.error('Vendored content drifted from MANIFEST.json. Re-run');
    console.error('  bun scripts/sync-open-design.ts --apply');
    console.error('from the pinned SHA to restore, or revert the hand-edit.');
    process.exit(1);
  }

  console.log(`OD vendor verify OK — ${results.length} path(s) match MANIFEST.json`);
}

// ── DS index generation ──────────────────────────────────────────────────────

interface DsIndexEntry {
  name: string;
  mood: string;
  palette_summary: string[];
}

/**
 * Generate `vendor/open-design/.cache/ds-index.json` — a one-line-per-system
 * digest the MCP `product_design_systems_index` tool returns without walking the
 * filesystem per call. Called at the end of `--apply`; also runnable standalone
 * via `--gen-ds-index` for the spec-027 bootstrap.
 *
 * Per system: `name` (dir name), `mood` (the non-Category `>` blockquote line
 * under the title, or the `#` title as fallback), `palette_summary` (first 6
 * unique 6-hex colors found in the file).
 */
export async function generateDsIndex(pinnedSha: string | null): Promise<number> {
  const entries: DsIndexEntry[] = [];
  const dirents = await fs.readdir(DESIGN_SYSTEMS_DIR, { withFileTypes: true });

  for (const d of dirents.sort((a, b) => a.name.localeCompare(b.name))) {
    if (!d.isDirectory()) continue;
    const designMd = path.join(DESIGN_SYSTEMS_DIR, d.name, 'DESIGN.md');
    if (!existsSync(designMd)) continue;

    const content = await fs.readFile(designMd, 'utf-8');
    const lines = content.split('\n');

    let mood = '';
    for (const line of lines) {
      const t = line.trim();
      if (t.startsWith('>') && !/^>\s*category:/i.test(t)) {
        mood = t.replace(/^>\s*/, '').trim();
        break;
      }
    }
    if (!mood) {
      const title = lines.find((l) => l.trim().startsWith('# '));
      mood = title ? title.replace(/^#\s*/, '').trim() : d.name;
    }

    const hexes = content.match(/#[0-9a-fA-F]{6}\b/g) ?? [];
    const palette_summary = [...new Set(hexes.map((h) => h.toLowerCase()))].slice(0, 6);

    entries.push({ name: d.name, mood, palette_summary });
  }

  const index = {
    generated_at: nowISO(),
    pinned_sha: pinnedSha,
    count: entries.length,
    systems: entries,
  };

  mkdirSync(path.dirname(DS_INDEX_PATH), { recursive: true });
  await fs.writeFile(DS_INDEX_PATH, JSON.stringify(index, null, 2) + '\n', 'utf-8');
  console.log(`DS index written → ${DS_INDEX_PATH} (${entries.length} systems)`);
  return entries.length;
}

// ── Pipeline-facing catalogue generation (spec 141, acceptance 4) ──────────────

interface CatalogVendor {
  name: string;
  category: string;
  mood: string;
  palette_primary: string;
  vendor_path: string;
}

/**
 * Build the `vendors[]` array for `references/od-catalog-index.json` from the
 * generated ds-index, preserving curation and adding new systems mechanically.
 * Pure + exported for unit testing (the FS read/write lives in `generateCatalogIndex`).
 *
 * Per system: a name already present in `existingByName` is preserved VERBATIM
 * (curated `category`/`mood`/`palette_primary` kept; only `vendor_path` refreshed),
 * so a hand-named palette like "Rausch (#ff385c)" survives a regen. A new system is
 * built mechanically — `category` from `categoryOf` (→ "Uncategorized" when absent),
 * `mood` + first `palette_summary` hex from the ds entry. Sorted by name.
 *
 * Mirrors the one-off /tmp/gen-catalog.py reference impl exactly.
 */
export function buildCatalogVendors(
  dsSystems: DsIndexEntry[],
  existingByName: Record<string, CatalogVendor>,
  categoryOf: (name: string) => string | null,
  vendorPathOf: (name: string) => string,
): CatalogVendor[] {
  const vendors: CatalogVendor[] = dsSystems.map((s) => {
    const existing = existingByName[s.name];
    if (existing) {
      return { ...existing, vendor_path: vendorPathOf(s.name) };
    }
    return {
      name: s.name,
      category: categoryOf(s.name) ?? 'Uncategorized',
      mood: (s.mood ?? '').trim(),
      palette_primary: s.palette_summary[0] ?? '',
      vendor_path: vendorPathOf(s.name),
    };
  });
  return vendors.sort((a, b) => a.name.localeCompare(b.name));
}

/** Read the `> Category:` line from a vendored DESIGN.md, or null if absent. */
function readDesignCategory(name: string): string | null {
  const designMd = path.join(DESIGN_SYSTEMS_DIR, name, 'DESIGN.md');
  if (!existsSync(designMd)) return null;
  for (const line of readFileSync(designMd, 'utf-8').split('\n')) {
    const m = line.match(/^>\s*Category:\s*(.+?)\s*$/i);
    if (m) return m[1];
  }
  return null;
}

/**
 * Regenerate `references/od-catalog-index.json` (the pipeline-facing catalogue
 * steps 02-prototype + 14-design-system actually `Read`) from the freshly-written
 * ds-index. Called at the end of `--apply`; also runnable standalone via
 * `--gen-catalog` for bootstrap/repair — the same dual-exposure as `generateDsIndex`
 * / `--gen-ds-index`. Returns the system count written.
 */
export async function generateCatalogIndex(): Promise<number> {
  const dsIndex = JSON.parse(await fs.readFile(DS_INDEX_PATH, 'utf-8')) as {
    systems: DsIndexEntry[];
  };

  let existingByName: Record<string, CatalogVendor> = {};
  let source = `${CATALOG_VENDOR_PREFIX}/`;
  if (existsSync(CATALOG_INDEX_PATH)) {
    const prior = JSON.parse(await fs.readFile(CATALOG_INDEX_PATH, 'utf-8')) as {
      source?: string;
      vendors: CatalogVendor[];
    };
    existingByName = Object.fromEntries((prior.vendors ?? []).map((v) => [v.name, v]));
    if (prior.source) source = prior.source;
  }

  const prefix = source.replace(/\/$/, '');
  const vendorPathOf = (name: string) => `${prefix}/${name}/DESIGN.md`;
  const vendors = buildCatalogVendors(dsIndex.systems, existingByName, readDesignCategory, vendorPathOf);

  const out = {
    version: 1,
    snapshot_date: todayDateStr(),
    source,
    vendors,
  };
  mkdirSync(path.dirname(CATALOG_INDEX_PATH), { recursive: true });
  await fs.writeFile(CATALOG_INDEX_PATH, JSON.stringify(out, null, 2) + '\n', 'utf-8');
  console.log(`Catalogue index written → ${CATALOG_INDEX_PATH} (${vendors.length} systems)`);
  return vendors.length;
}

/**
 * Fixed allowlist of tracked OD-related docs whose prose hard-codes the catalogue
 * system count. Scoping the stale-count scan to these (rather than the whole repo)
 * keeps `scanStaleCounts`'s deliberately-loose count regex from false-flagging
 * unrelated numbers. Paths are SKILL_ROOT-relative.
 */
const STALE_COUNT_DOC_ALLOWLIST = [
  'SKILL.md',
  'templates/pipeline/02-prototype/prompt.md',
  'templates/pipeline/02-prototype/references/od-bridge.md',
  'templates/pipeline/14-design-system/prompt.md',
];

/** Read the allowlist docs and flag any line whose count != currentCount. */
async function scanAllowlistStaleCounts(currentCount: number): Promise<StaleCountHit[]> {
  const files: { path: string; text: string }[] = [];
  for (const rel of STALE_COUNT_DOC_ALLOWLIST) {
    const full = path.join(SKILL_ROOT, rel);
    if (!existsSync(full)) continue;
    files.push({ path: rel, text: await fs.readFile(full, 'utf-8') });
  }
  return scanStaleCounts(files, currentCount);
}

// ── CLI entry point ──────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const cmd = args[0];

  try {
    if (cmd === '--check') {
      await cmdCheck();
    } else if (cmd === '--bump') {
      const sha = args[1];
      if (!sha) throw new Error('Usage: --bump <sha> --reason "..."');
      const reasonIdx = args.indexOf('--reason');
      const reason = reasonIdx !== -1 ? args[reasonIdx + 1] : '';
      await cmdBump(sha, reason);
    } else if (cmd === '--apply') {
      await cmdApply();
    } else if (cmd === '--verify') {
      await cmdVerify();
    } else if (cmd === '--gen-ds-index') {
      const manifest = await readManifest();
      await generateDsIndex(manifest.pinned_sha);
    } else if (cmd === '--gen-catalog') {
      await generateCatalogIndex();
    } else {
      console.error(`Usage:
  bun scripts/sync-open-design.ts --check
  bun scripts/sync-open-design.ts --bump <sha> --reason "..."
  bun scripts/sync-open-design.ts --apply
  bun scripts/sync-open-design.ts --verify
  bun scripts/sync-open-design.ts --gen-ds-index
  bun scripts/sync-open-design.ts --gen-catalog`);
      process.exit(1);
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`Error: ${msg}`);
    process.exit(1);
  }
}

// Only run as CLI entrypoint — skip when imported by the test runner.
const isMain =
  process.argv[1] &&
  (process.argv[1].endsWith('sync-open-design.ts') ||
    process.argv[1].endsWith('sync-open-design.js'));

if (isMain) {
  main();
}
