#!/usr/bin/env node
// sync.js
// Usage:  npm run sync            (uses ./config.json)
//         node src/sync.js --config path/to/config.json
//         node src/sync.js --no-raid   /  --no-mythic   (skip a part)
//
// Bundle mode (used by the daily GitHub Action): write the data INTO the
// addon itself, so players need no setup at all.
//         node src/sync.js --bundle path/to/LoadoutPlanner --sources parses,raiderio
//
// Steps: find the current season -> collect samples from the leaderboards ->
// tally the most-played builds -> write the LoadoutPlannerData addon.

import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RaiderIO } from './raiderio.js';
import { pickSeason, pickRaids, collectMythicPlus, collectRaid } from './collect.js';
import { aggregate } from './aggregate.js';
import { writeAddon, writeBundle } from './writeAddon.js';
import { collectParses } from './parses.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export const DEFAULTS = {
  apiKey: '',                       // your Raider.IO application key (optional but recommended)
  addonsPath: '',                   // ...\World of Warcraft\_retail_\Interface\AddOns ('' = ./output)
  expansionID: 11,                  // 11 = Midnight (Raider.IO's numbering)
  region: 'world',                  // leaderboard region: world, us, eu, kr, tw
  mythicPlusPages: 5,               // leaderboard pages per dungeon (about 20 runs each)
  raidGuilds: 20,                   // top guilds per difficulty
  raidDifficulties: ['mythic', 'heroic'],
  minSamples: 3,                    // don't publish a build seen on fewer players than this
  buildsPerTarget: 3,               // the top build plus alternatives
  requestDelayMs: 1000,             // pause between requests (be polite)
  cacheHours: 6,                    // reuse downloaded responses this long
};

function parseArgs(argv) {
  const args = { config: path.join(ROOT, 'config.json'), mythic: true, raid: true };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--config') args.config = path.resolve(argv[++i]);
    else if (argv[i] === '--bundle') args.bundle = path.resolve(argv[++i]);
    else if (argv[i] === '--sources') args.sources = argv[++i].split(',').map((x) => x.trim()).filter(Boolean);
    else if (argv[i] === '--no-raid') args.raid = false;
    else if (argv[i] === '--no-mythic') args.mythic = false;
    else if (argv[i] === '--help' || argv[i] === '-h') args.help = true;
  }
  return args;
}

async function loadConfig(file) {
  // In GitHub Actions the key comes from a repository secret, not a file.
  const fromEnv = process.env.RAIDERIO_API_KEY ? { apiKey: process.env.RAIDERIO_API_KEY } : {};
  try {
    return { ...DEFAULTS, ...JSON.parse(await readFile(file, 'utf8')), ...fromEnv };
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.log(`No config at ${file}; using defaults (output to ./output).`);
      return { ...DEFAULTS, ...fromEnv };
    }
    throw new Error(`Couldn't read ${file}: ${error.message}`);
  }
}

/** Where to write. Refuses paths that don't look like an AddOns folder. */
async function outputDir(config) {
  if (!config.addonsPath) return path.join(ROOT, 'output');
  const dir = path.resolve(config.addonsPath);
  if (path.basename(dir).toLowerCase() !== 'addons') {
    throw new Error(`addonsPath should end in "AddOns" (got ${dir}).`);
  }
  try {
    if (!(await stat(dir)).isDirectory()) throw new Error();
  } catch {
    throw new Error(`addonsPath doesn't exist: ${dir}`);
  }
  return dir;
}

export async function run({ config, parts = { mythic: true, raid: true }, log = console.log, fetchImpl, now = new Date() }) {
  const api = new RaiderIO({
    apiKey: config.apiKey,
    baseURL: config.baseURL,
    requestDelayMs: config.requestDelayMs,
    cacheDir: config.cacheDir === undefined ? path.join(ROOT, '.cache') : config.cacheDir,
    cacheHours: config.cacheHours,
    fetch: fetchImpl,
    log,
  });

  const data = { source: 'raider.io', generated: now.toISOString(), region: config.region, mythic: {}, raid: {} };
  let mythicSamples = [];
  let raidSamples = [];
  let dungeonOrder = [];
  let bossOrder = [];

  if (parts.mythic) {
    log('Mythic+: finding the current season...');
    const season = pickSeason(await api.mythicPlusStaticData(config.expansionID), now);
    if (!season) throw new Error('No Mythic+ season found. Check expansionID in config.json.');
    data.season = { slug: season.slug, name: season.name };
    dungeonOrder = (season.dungeons || []).map((d) => d.name);
    log(`Mythic+: ${season.name}, ${dungeonOrder.length} dungeons, ${config.mythicPlusPages} leaderboard pages each`);
    const result = await collectMythicPlus(api, {
      season, region: config.region, pages: config.mythicPlusPages, log,
    });
    mythicSamples = result.samples;
    data.mythicStats = result.counters;
  }

  if (parts.raid) {
    log('Raid: finding the current raid(s)...');
    const raids = pickRaids(await api.raidStaticData(config.expansionID), now);
    data.raids = raids.map((r) => r.name);
    bossOrder = raids.flatMap((r) => (r.encounters || []).map((e) => e.name));
    log(`Raid: ${data.raids.join(', ') || 'none'}; top ${config.raidGuilds} guilds on ${config.raidDifficulties.join(', ')}`);
    const result = await collectRaid(api, {
      raids, difficulties: config.raidDifficulties, region: config.region, guilds: config.raidGuilds, log,
    });
    raidSamples = result.samples;
    data.raidStats = result.counters;
  }

  const tallied = aggregate(
    { mythicSamples, dungeonOrder, raidSamples, bossOrder, difficulties: config.raidDifficulties },
    { minSamples: config.minSamples, keep: config.buildsPerTarget },
  );
  data.mythic = tallied.mythic;
  data.raid = tallied.raid;
  data.api = { ...api.stats };
  return data;
}

/** Current season names from Raider.IO's public static data (no key needed). */
async function seasonNames(api, config, now, log) {
  const names = { dungeonOrder: [], bossOrder: [], season: null, raids: [] };
  try {
    const season = pickSeason(await api.mythicPlusStaticData(config.expansionID), now);
    if (season) {
      names.season = { slug: season.slug, name: season.name };
      names.dungeonOrder = (season.dungeons || []).map((d) => d.name);
    }
    const raids = pickRaids(await api.raidStaticData(config.expansionID), now);
    names.raids = raids.map((r) => r.name);
    names.bossOrder = raids.flatMap((r) => (r.encounters || []).map((e) => e.name));
  } catch (error) {
    log(`  (couldn't read the current season from Raider.IO: ${error.message}; keeping every place)`);
  }
  return names;
}

/** The parses.gg source, in the same data shape as run(). */
export async function runParses({ config, log = console.log, fetchImpl, now = new Date() }) {
  const api = new RaiderIO({
    apiKey: config.apiKey, baseURL: config.baseURL, requestDelayMs: config.requestDelayMs,
    cacheDir: config.cacheDir === undefined ? path.join(ROOT, '.cache') : config.cacheDir,
    cacheHours: config.cacheHours, fetch: fetchImpl, log,
  });
  log('parses.gg: finding the current season...');
  const names = await seasonNames(api, config, now, log);
  const parses = await collectParses({
    fetchImpl: fetchImpl || globalThis.fetch,
    dungeonOrder: names.dungeonOrder, bossOrder: names.bossOrder, log,
  });
  return {
    source: 'parses.gg', generated: now.toISOString(), season: names.season || undefined,
    raids: names.raids, gameBuild: parses.gameBuild || undefined,
    mythic: parses.mythic, raid: parses.raid, stats: parses.stats,
  };
}

async function bundleMain(args, config) {
  const sources = args.sources || ['parses'];
  const bundle = {};
  for (const source of sources) {
    if (source === 'parses') {
      bundle.parses = await runParses({ config });
    } else if (source === 'raiderio') {
      bundle.raiderio = await run({ config, parts: { mythic: args.mythic, raid: args.raid } });
    } else {
      throw new Error(`Unknown source "${source}" (use parses, raiderio).`);
    }
  }
  // Never publish an empty bundle: if a source returned nothing at all (site
  // down, format changed), stop with an error so the daily job fails loudly
  // and the addon keeps its previous builds.
  for (const [name, data] of Object.entries(bundle)) {
    const specs = Object.keys(data.mythic || {}).length
      + Object.values(data.raid || {}).reduce((n, bySpec) => n + Object.keys(bySpec).length, 0);
    if (specs === 0) {
      throw new Error(`${name} returned no builds at all; not updating the bundle.`);
    }
  }
  const { file, changed } = await writeBundle(args.bundle, bundle);
  console.log(changed ? `\nBuilds changed; wrote ${file}` : `\nNo build changes; ${file} left as it was.`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('Usage: node src/sync.js [--config config.json] [--no-raid] [--no-mythic]');
    console.log('       node src/sync.js --bundle <LoadoutPlanner folder> [--sources parses,raiderio]');
    return;
  }
  const config = await loadConfig(args.config);
  if (args.bundle) {
    await bundleMain(args, config);
    return;
  }
  const target = await outputDir(config);
  if (!config.apiKey) {
    console.log('Note: no apiKey in config.json. Anonymous requests have lower limits; see README.');
  }
  const started = Date.now();
  const data = await run({ config, parts: { mythic: args.mythic, raid: args.raid } });
  const written = await writeAddon(target, data);

  const specs = new Set([...Object.keys(data.mythic), ...Object.values(data.raid).flatMap((d) => Object.keys(d))]);
  console.log('');
  console.log(`Done in ${Math.round((Date.now() - started) / 1000)}s: ${data.api.requests} requests, ${data.api.cached} from cache.`);
  console.log(`Builds for ${specs.size} specs written to ${written}`);
  console.log('In game: /reload, then open talents -> Top builds -> Raider.IO.');
}

// Only run when started directly (not when imported by the tests).
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`\nSync failed: ${error.message}`);
    process.exitCode = 1;
  });
}
