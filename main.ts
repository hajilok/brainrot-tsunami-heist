// Brainrot Tsunami Heist — the make.fun entry packager (Node 22, standard library only).
//
// The game itself is this directory's Rojo project, built into game.rbxl with
//   rojo build default.project.json --output game.rbxl
// and this program hands it in. It copies game.rbxl, src/, screenshots/ and
// PLAY.json from beside this file into the output directory (default /output,
// overridden outside the grader by MAKEFUN_OUTPUT_DIR) and writes
// out/dossier.json, the summary the judge reads, with the vendored make.fun
// library unchanged.
//
// Every name under the output starts with a letter, a digit or _ and holds only
// letters, digits, . _ and -: the grader fails an entry whose output holds any
// other, so a file such as .gitkeep or .DS_Store copied in fails it. src/ and
// screenshots/ are therefore copied without any name that starts with a dot, at
// any depth.
//
// Run it as the grader does, writing out/ in place of /output:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

/** The directory this program and the game live in (the repository root). */
const here = fileURLToPath(new URL('.', import.meta.url));

/** cpSync's filter: leave out every file and directory whose name starts with a dot (.gitkeep, .DS_Store, .git). */
const notDotted = (path: string): boolean => !basename(path).startsWith('.');

/** The place PLAY.json names: the public play link and the Roblox ids behind it. */
export interface EntryManifest {
  url: string;
  place_id: number;
  universe_id: number;
}

/** What packageEntry writes and reports back for the entry log. */
export interface PackageResult {
  outputDir: string;
  manifest: EntryManifest;
  dossierBytes: number;
}

/** Reads and shape-checks PLAY.json, returning its url, place_id and universe_id. */
export function readEntryManifest(filePath: string): EntryManifest {
  const parsed = JSON.parse(readFileSync(filePath, 'utf8')) as Partial<EntryManifest>;
  if (typeof parsed.url !== 'string' || typeof parsed.place_id !== 'number' || typeof parsed.universe_id !== 'number') {
    throw new Error(`PLAY.json at ${filePath} must hold url (string), place_id (number) and universe_id (number)`);
  }
  return { url: parsed.url, place_id: parsed.place_id, universe_id: parsed.universe_id };
}

/**
 * Checks PLAY.json before the dossier is built: the url must be a Roblox play
 * link whose place id matches place_id, and both ids must be positive safe
 * integers. Throws instead of packing a manifest the gate would refuse.
 */
export function verifyEntryManifest(manifest: EntryManifest): void {
  const match = manifest.url.match(/roblox\.com\/games\/(\d+)/);
  if (match === null) {
    throw new Error(`PLAY.json url is not a Roblox play link: ${manifest.url}`);
  }
  if (!Number.isSafeInteger(manifest.place_id) || manifest.place_id <= 0) {
    throw new Error(`PLAY.json place_id must be a positive integer, not ${manifest.place_id}`);
  }
  if (!Number.isSafeInteger(manifest.universe_id) || manifest.universe_id <= 0) {
    throw new Error(`PLAY.json universe_id must be a positive integer, not ${manifest.universe_id}`);
  }
  if (Number(match[1]) !== manifest.place_id) {
    throw new Error(`PLAY.json url place id ${match[1]} does not match place_id ${manifest.place_id}`);
  }
}

/**
 * Copies the entry's files into outputDir and writes its dossier.json.
 *
 * game.rbxl, PLAY.json, src/ and screenshots/ come from sourceDir (this
 * directory by default). The dossier is built from what was just copied, with
 * the scorer's own caps: only text_max_bytes shapes the bytes; the rest refuse
 * an entry the scorer would refuse (more than 4 screenshots or one over
 * 256 KiB; a place of more than 500000 instances, whose scripts' sources come to
 * over 8 MiB or whose scripts' paths come to over 1048576 characters, in all).
 */
export function packageEntry(
  outputDir: string = process.env.MAKEFUN_OUTPUT_DIR ?? '/output',
  sourceDir: string = here,
): PackageResult {
  const gamePath = join(sourceDir, 'game.rbxl');
  if (!existsSync(gamePath)) {
    throw new Error(`${gamePath} is missing: build it with "rojo build default.project.json --output game.rbxl"`);
  }

  mkdirSync(outputDir, { recursive: true });

  copyFileSync(gamePath, join(outputDir, 'game.rbxl'));
  copyFileSync(join(sourceDir, 'PLAY.json'), join(outputDir, 'PLAY.json'));
  cpSync(join(sourceDir, 'src'), join(outputDir, 'src'), { recursive: true, filter: notDotted });

  mkdirSync(join(outputDir, 'screenshots'), { recursive: true });
  if (existsSync(join(sourceDir, 'screenshots'))) {
    cpSync(join(sourceDir, 'screenshots'), join(outputDir, 'screenshots'), { recursive: true, filter: notDotted });
  }

  const manifest = readEntryManifest(join(sourceDir, 'PLAY.json'));
  verifyEntryManifest(manifest);

  const dossier = buildDossier(outputDir, {
    text_max_bytes: 65536,
    screenshots: { max: 4, max_bytes: 262144 },
    max_instances: 500000,
    scripts_max_source_bytes: 8388608,
    scripts_max_path_chars: 1048576,
  });
  writeFileSync(join(outputDir, 'dossier.json'), dossier);

  return { outputDir, manifest, dossierBytes: dossier.length };
}

const result = packageEntry();
console.log(
  `Brainrot Tsunami Heist packed to ${result.outputDir}: ` +
  `place ${result.manifest.place_id}, universe ${result.manifest.universe_id}, ` +
  `dossier ${result.dossierBytes} bytes.`,
);
