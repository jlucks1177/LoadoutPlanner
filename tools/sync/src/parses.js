// parses.js
// The parses.gg source: most-played builds from logged kills and keys.
//
// parses.gg publishes an export endpoint made for exactly this, and says its
// data is "free for anyone to read, download whole, or build against. No
// account, no key, no quota." (quoted in ArchonTalentsData's README, which
// uses the same endpoint; its MIT-licensed adapter was the reference here).
//
//   GET https://parses.gg/api/builds/export?tier={tier}&cohort={cohort}
//   { gameBuild, specs: [ { specId, classId, encounters: [
//       { encounterId, label, exportCode, count, sample } ] } ] }
//
// COHORTS (since v0.19): "all" = every logged player, "top10" = the top 10%
// by performance (also "top1" and "half"). "all" shows what the AVERAGE
// player runs, which often isn't the build good players use, so we ask for
// top10 first and fall back to "all" only where the top 10% has too little
// data (common early in a tier, or for rare specs). Each entry records which
// cohort it came from, and the addon shows it.
//
// Two requests per difficulty (top10 + all), ten in total.
// encounterId null = the aggregate over the whole difficulty.
//
// parses.gg's tiers are per difficulty, not per season, so responses also
// contain LAST season's dungeons and raids. We keep only the current
// season's, by name, using Raider.IO's public static data (no key needed).

import { parseTalentString } from './talentString.js';

const ENDPOINT = 'https://parses.gg/api/builds/export';
const USER_AGENT = 'LoadoutPlannerSync/1.0 (WoW addon build data)';

// Our buckets -> parses.gg tier codes (per ArchonTalentsData's maps.mjs:
// d14/d15/d16/d17 = Normal/Heroic/Mythic/LFR raid, b10 = keystones 10+).
export const PARSES_TIERS = [
  { bucket: 'mythic', tier: 'b10' },
  { bucket: 'lfr', tier: 'd17' },
  { bucket: 'normal', tier: 'd14' },
  { bucket: 'heroic', tier: 'd15' },
  { bucket: 'mythic_raid', tier: 'd16' },
];

/** "Nek'zali the Soulcoiler" and "Nekzali the soulcoiler" compare equal. */
export const norm = (name) => String(name || '').toLowerCase().replace(/[^a-z0-9]/g, '');

export const PREFERRED_COHORT = 'top10';
export const FALLBACK_COHORT = 'all';
// Below this many top-10% players, a build is too thin to trust over the
// wider "all players" data.
export const MIN_TOP_SAMPLE = 5;

async function fetchTier(fetchImpl, tier, cohort, log) {
  const url = `${ENDPOINT}?tier=${encodeURIComponent(tier)}&cohort=${encodeURIComponent(cohort)}`;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetchImpl(url, { headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' } });
      if (response.ok) return await response.json();
      if (response.status < 500 && response.status !== 429) {
        log(`  parses.gg ${tier}/${cohort}: HTTP ${response.status}, skipped`);
        return null;
      }
    } catch (error) {
      if (attempt === 3) {
        log(`  parses.gg ${tier}/${cohort}: ${error.message}, skipped`);
        return null;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** attempt));
  }
  return null;
}

/**
 * One cohort's response -> Map(specID -> { aggregate, targets: Map(name -> entry) }).
 * Only this season's places are kept, named the way the journal does.
 */
function readPayload(payload, current, cohort, stats) {
  const bySpec = new Map();
  for (const spec of (payload && payload.specs) || []) {
    const specID = Number(spec.specId);
    const perSpec = { aggregate: null, targets: new Map() };
    for (const encounter of spec.encounters || []) {
      const code = typeof encounter.exportCode === 'string' ? encounter.exportCode.trim() : '';
      const parsed = parseTalentString(code);
      if (!parsed || parsed.specID !== specID) {
        stats.unreadable++;
        continue;
      }
      const count = Number(encounter.count);
      const sample = Number(encounter.sample);
      const hasCounts = Number.isFinite(count) && Number.isFinite(sample) && sample > 0 && count <= sample;
      const entry = {
        samples: hasCounts ? sample : undefined,
        cohort,
        builds: [{
          code,
          count: hasCounts ? count : undefined,
          share: hasCounts ? Math.round((count / sample) * 1000) / 1000 : undefined,
        }],
      };
      if (encounter.encounterId === null || encounter.encounterId === undefined) {
        perSpec.aggregate = entry;
        continue;
      }
      const name = current.size > 0 ? current.get(norm(encounter.label)) : encounter.label;
      if (!name) {
        stats.outOfSeason++;
        continue;
      }
      perSpec.targets.set(name, entry);
    }
    bySpec.set(specID, perSpec);
  }
  return bySpec;
}

/** The top-10% entry if it has enough players behind it, else the "all" one. */
function pick(top, all, stats) {
  if (top && (top.samples === undefined || top.samples >= MIN_TOP_SAMPLE)) {
    stats.topCohort++;
    return top;
  }
  if (all) {
    stats.fallback++;
    return all;
  }
  if (top) stats.topCohort++;
  return top || null;
}

/**
 * Collect parses.gg builds for the current season.
 * @param {object} options
 * @param {string[]} options.dungeonOrder  current dungeon names ([] = keep all)
 * @param {string[]} options.bossOrder     current raid boss names ([] = keep all)
 * @returns data in LoadoutPlannerData shape:
 *   { mythic: { [specID]: entries }, raid: { lfr|normal|heroic|mythic: { [specID]: entries } } }
 *   entries = [{ target, isAll, samples, cohort, builds: [{ code, count, share }] }]
 */
export async function collectParses({ fetchImpl = globalThis.fetch, dungeonOrder = [], bossOrder = [], log = () => {} }) {
  const result = { mythic: {}, raid: {}, gameBuild: null,
    stats: { kept: 0, outOfSeason: 0, unreadable: 0, topCohort: 0, fallback: 0 } };

  for (const { bucket, tier } of PARSES_TIERS) {
    const topPayload = await fetchTier(fetchImpl, tier, PREFERRED_COHORT, log);
    const allPayload = await fetchTier(fetchImpl, tier, FALLBACK_COHORT, log);
    if (!topPayload && !allPayload) continue;
    result.gameBuild = result.gameBuild || (topPayload && topPayload.gameBuild) || (allPayload && allPayload.gameBuild) || null;

    const isDungeon = bucket === 'mythic';
    const order = isDungeon ? dungeonOrder : bossOrder;
    const current = new Map(order.map((name) => [norm(name), name]));
    // Count skipped entries once (from the widest cohort), not per cohort.
    const scratch = { unreadable: 0, outOfSeason: 0 };
    const top = readPayload(topPayload, current, PREFERRED_COHORT, allPayload ? scratch : result.stats);
    const all = readPayload(allPayload, current, FALLBACK_COHORT, allPayload ? result.stats : scratch);
    let kept = 0;

    for (const specID of new Set([...top.keys(), ...all.keys()])) {
      const t = top.get(specID) || { aggregate: null, targets: new Map() };
      const a = all.get(specID) || { aggregate: null, targets: new Map() };
      const perTarget = [];
      for (const name of new Set([...t.targets.keys(), ...a.targets.keys()])) {
        const chosen = pick(t.targets.get(name), a.targets.get(name), result.stats);
        if (chosen) perTarget.push({ target: name, isAll: false, ...chosen });
      }
      // The aggregate spans every season's content, so only trust it when
      // this spec has current-season data behind it.
      if (perTarget.length === 0) continue;
      perTarget.sort((x, y) => order.indexOf(x.target) - order.indexOf(y.target));
      const aggregate = pick(t.aggregate, a.aggregate, result.stats);
      const entries = aggregate
        ? [{ target: isDungeon ? 'All dungeons' : 'All bosses', isAll: true, ...aggregate }, ...perTarget]
        : perTarget;

      if (isDungeon) {
        result.mythic[specID] = entries;
      } else {
        const difficulty = bucket === 'mythic_raid' ? 'mythic' : bucket;
        result.raid[difficulty] = result.raid[difficulty] || {};
        result.raid[difficulty][specID] = entries;
      }
      kept += entries.length;
    }
    result.stats.kept += kept;
    log(`  parses.gg ${bucket.padEnd(11)} (${tier}): ${kept} builds`);
  }
  log(`  parses.gg: ${result.stats.topCohort} from the top 10% of players, ${result.stats.fallback} from all players (too few top players)`);
  return result;
}
