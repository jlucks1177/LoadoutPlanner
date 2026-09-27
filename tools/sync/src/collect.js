// collect.js
// Gathers "samples": one per player per run/kill, each saying
// "this spec used this talent string on this dungeon/boss".
//
//   Mythic+: the season's leaderboard (/mythic-plus/runs) already lists
//            every roster member's loadout, so one request covers ~20 runs
//            for EVERY spec at once.
//   Raid:    the top guilds for a difficulty (/raiding/raid-rankings), then
//            each guild's kill of each boss (/guilds/boss-kill), whose
//            roster lists each raider's loadout.

import { parseTalentString } from './talentString.js';

const DATE_REGION = 'us'; // season/raid start dates are per region; any is fine for "is it current?"

/** Is something with { starts, ends } (per-region timestamps) running now? */
function isCurrent(item, now) {
  const starts = item.starts && item.starts[DATE_REGION];
  const ends = item.ends && item.ends[DATE_REGION];
  return Boolean(starts) && new Date(starts) <= now && (!ends || new Date(ends) > now);
}

/** Pick the current main Mythic+ season (with its dungeons). */
export function pickSeason(staticData, now = new Date()) {
  const seasons = (staticData && staticData.seasons) || [];
  const main = seasons.filter((s) => s.is_main_season);
  return main.find((s) => isCurrent(s, now)) || main[0] || seasons[0] || null;
}

/** Pick the raids that are current (a season can have more than one). */
export function pickRaids(raidData, now = new Date()) {
  const raids = (raidData && raidData.raids) || [];
  const current = raids.filter((r) => isCurrent(r, now));
  if (current.length > 0) return current;
  // None marked current (e.g. between tiers): take the most recently started.
  const started = raids.filter((r) => r.starts && new Date(r.starts[DATE_REGION]) <= now);
  started.sort((a, b) => new Date(b.starts[DATE_REGION]) - new Date(a.starts[DATE_REGION]));
  return started.slice(0, 1);
}

/**
 * Turn one player's loadout into a sample, or null if it's unusable.
 * `rosterSpecID` is the spec the API says they played; if the string itself
 * says a different spec, the loadout is stale or wrong, so we skip it.
 */
function makeSample(code, rosterSpecID, extra, counters) {
  const parsed = parseTalentString(code);
  if (!parsed) {
    counters.unreadable++;
    return null;
  }
  if (rosterSpecID && parsed.specID !== rosterSpecID) {
    counters.specMismatch++;
    return null;
  }
  return { specID: parsed.specID, code: code.trim(), contentKey: parsed.contentKey, ...extra };
}

/** Mythic+: `pages` leaderboard pages per dungeon. */
export async function collectMythicPlus(api, { season, region, pages, log }) {
  const samples = [];
  const counters = { runs: 0, players: 0, unreadable: 0, specMismatch: 0 };
  for (const dungeon of season.dungeons || []) {
    let dungeonRuns = 0;
    for (let page = 0; page < pages; page++) {
      const data = await api.mythicPlusRuns({ season: season.slug, region, dungeon: dungeon.slug, page });
      const rankings = (data && data.rankings) || [];
      for (const { run } of rankings) {
        if (!run) continue;
        counters.runs++;
        dungeonRuns++;
        for (const member of run.roster || []) {
          counters.players++;
          const specID = member.character && member.character.spec && member.character.spec.id;
          const sample = makeSample(member.loadout, specID, {
            kind: 'mythic',
            target: dungeon.name,
            level: run.mythic_level,
            who: member.character && member.character.id, // to count players, not runs
          }, counters);
          if (sample) samples.push(sample);
        }
      }
      if (rankings.length === 0) break; // no more pages
    }
    log(`  ${dungeon.name}: ${dungeonRuns} runs`);
  }
  return { samples, counters };
}

/** Raid: the top `guilds` guilds per difficulty, each boss they've killed. */
export async function collectRaid(api, { raids, difficulties, region, guilds, log }) {
  const samples = [];
  const counters = { kills: 0, players: 0, unreadable: 0, specMismatch: 0 };
  for (const raid of raids) {
    const bossNames = new Map((raid.encounters || []).map((e) => [e.slug, e.name]));
    for (const difficulty of difficulties) {
      const ranking = await api.raidRankings({ raid: raid.slug, difficulty, region, limit: guilds });
      const entries = ((ranking && ranking.raidRankings) || []).slice(0, guilds);
      log(`  ${raid.name} (${difficulty}): ${entries.length} guilds`);
      for (const entry of entries) {
        const guild = entry.guild;
        if (!guild || !guild.realm || !guild.region) continue;
        for (const defeated of entry.encountersDefeated || []) {
          const kill = await api.guildBossKill({
            raid: raid.slug, difficulty, boss: defeated.slug,
            region: guild.region.slug, realm: guild.realm.slug, guild: guild.name,
          });
          if (!kill) continue;
          counters.kills++;
          for (const member of kill.roster || []) {
            counters.players++;
            const character = member.character || {};
            const loadout = character.talentLoadout || {};
            const sample = makeSample(loadout.loadoutText, loadout.loadoutSpecId, {
              kind: 'raid',
              difficulty,
              raid: raid.name,
              target: bossNames.get(defeated.slug) || defeated.slug,
              who: `${character.name}-${(character.realm && character.realm.slug) || ''}`,
            }, counters);
            if (sample) samples.push(sample);
          }
        }
      }
    }
  }
  return { samples, counters };
}
