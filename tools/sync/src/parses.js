// parses.js
// The parses.gg source: most-played builds from logged kills and keys.
//
// parses.gg publishes an export endpoint made for exactly this, and says its
// data is "free for anyone to read, download whole, or build against. No
// account, no key, no quota." (quoted in ArchonTalentsData's README, which
// uses the same endpoint; its MIT-licensed adapter was the reference here).
//
//   GET https://parses.gg/api/builds/export?tier={tier}&cohort=all
//   { gameBuild, specs: [ { specId, classId, encounters: [
//       { encounterId, label, exportCode, count, sample } ] } ] }
//
// One request per difficulty covers every spec: five requests in total.
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

async function fetchTier(fetchImpl, tier, log) {
  const url = `${ENDPOINT}?tier=${encodeURIComponent(tier)}&cohort=all`;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetchImpl(url, { headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' } });
      if (response.ok) return await response.json();
      if (response.status < 500 && response.status !== 429) {
        log(`  parses.gg ${tier}: HTTP ${response.status}, skipped`);
        return null;
      }
    } catch (error) {
      if (attempt === 3) {
        log(`  parses.gg ${tier}: ${error.message}, skipped`);
        return null;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** attempt));
  }
  return null;
}

/**
 * Collect parses.gg builds for the current season.
 * @param {object} options
 * @param {string[]} options.dungeonOrder  current dungeon names ([] = keep all)
 * @param {string[]} options.bossOrder     current raid boss names ([] = keep all)
 * @returns data in LoadoutPlannerData shape:
 *   { mythic: { [specID]: entries }, raid: { lfr|normal|heroic|mythic: { [specID]: entries } } }
 *   entries = [{ target, isAll, samples, builds: [{ code, count, share }] }]
 */
export async function collectParses({ fetchImpl = globalThis.fetch, dungeonOrder = [], bossOrder = [], log = () => {} }) {
  const result = { mythic: {}, raid: {}, gameBuild: null, stats: { kept: 0, outOfSeason: 0, unreadable: 0 } };

  for (const { bucket, tier } of PARSES_TIERS) {
    const payload = await fetchTier(fetchImpl, tier, log);
    if (!payload) continue;
    result.gameBuild = result.gameBuild || payload.gameBuild || null;

    const isDungeon = bucket === 'mythic';
    const order = isDungeon ? dungeonOrder : bossOrder;
    const current = new Map(order.map((name) => [norm(name), name]));
    let kept = 0;

    for (const spec of payload.specs || []) {
      const specID = Number(spec.specId);
      const perTarget = [];
      let aggregate = null;

      for (const encounter of spec.encounters || []) {
        const code = typeof encounter.exportCode === 'string' ? encounter.exportCode.trim() : '';
        const parsed = parseTalentString(code);
        if (!parsed || parsed.specID !== specID) {
          result.stats.unreadable++;
          continue;
        }
        const count = Number(encounter.count);
        const sample = Number(encounter.sample);
        const hasCounts = Number.isFinite(count) && Number.isFinite(sample) && sample > 0 && count <= sample;
        const entryBuild = {
          code,
          count: hasCounts ? count : undefined,
          share: hasCounts ? Math.round((count / sample) * 1000) / 1000 : undefined,
        };
        const samples = hasCounts ? sample : undefined;

        if (encounter.encounterId === null || encounter.encounterId === undefined) {
          aggregate = { samples, build: entryBuild };
          continue;
        }
        // Keep only this season's places; name them the way the journal does.
        const name = current.size > 0 ? current.get(norm(encounter.label)) : encounter.label;
        if (!name) {
          result.stats.outOfSeason++;
          continue;
        }
        perTarget.push({ target: name, isAll: false, samples, builds: [entryBuild] });
      }

      // The aggregate spans every season's content, so only trust it when
      // this spec has current-season data behind it.
      if (perTarget.length === 0) continue;
      perTarget.sort((a, b) => order.indexOf(a.target) - order.indexOf(b.target));
      const entries = aggregate
        ? [{ target: isDungeon ? 'All dungeons' : 'All bosses', isAll: true, samples: aggregate.samples, builds: [aggregate.build] }, ...perTarget]
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
  return result;
}
