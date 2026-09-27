import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { parseTalentString } from '../src/talentString.js';
import { RaiderIO } from '../src/raiderio.js';
import { pickSeason } from '../src/collect.js';
import { run, DEFAULTS } from '../src/sync.js';
import { writeAddon, toLua } from '../src/writeAddon.js';
import { makeCode, fakeFetch } from './helpers.js';

// ---- Talent strings ---------------------------------------------------------

test('decodes real talent strings from the Raider.IO API docs fixtures', () => {
  // Their spec IDs are known from the API: Fury Warrior 72, Windwalker Monk 269.
  assert.equal(parseTalentString('CgEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgGDjZMz2yMzMjZmxMzMzMjZWmZmZmxsYmZGAAIMwGssY0YGQmFMjFAzgBA').specID, 72);
  assert.equal(parseTalentString('B0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAESkkEtISEAAAAQikkAIJJJJpIpEiQASSSSaJBOAAA').specID, 269);
});

test('same talents exported with a different tree hash group together', () => {
  const a = parseTalentString(makeCode({ specID: 102, hash: 11, content: '1011001' }));
  const b = parseTalentString(makeCode({ specID: 102, hash: 99, content: '1011001' }));
  const c = parseTalentString(makeCode({ specID: 102, hash: 11, content: '1011011' }));
  assert.equal(a.contentKey, b.contentKey);
  assert.notEqual(a.contentKey, c.contentKey);
  assert.equal(parseTalentString('No data - Coming soon!'), null);
  assert.equal(parseTalentString(''), null);
});

// ---- A small fake season ----------------------------------------------------

const BAL = 102; // Balance Druid
const FERAL = 103;
const buildA = makeCode({ specID: BAL, hash: 1, content: '110010101' });
const buildA2 = makeCode({ specID: BAL, hash: 2, content: '110010101' }); // same talents, other patch
const buildB = makeCode({ specID: BAL, hash: 1, content: '111110000' });
const feral = makeCode({ specID: FERAL, hash: 1, content: '1' });
const mage = makeCode({ specID: 64, hash: 1, content: '1' });

const player = (id, specID, loadout) => ({ character: { id, name: `P${id}`, spec: { id: specID } }, role: 'dps', loadout });

function seasonRoutes(extra = {}) {
  return (route, q) => {
    if (route === '/mythic-plus/static-data') {
      return { seasons: [
        { slug: 'season-old', name: 'Old', is_main_season: true, starts: { us: '2025-01-01T00:00:00Z' }, ends: { us: '2026-03-01T00:00:00Z' }, dungeons: [] },
        { slug: 'season-mn-2', name: 'Midnight Season 2', is_main_season: true, starts: { us: '2026-08-01T00:00:00Z' }, ends: { us: null },
          dungeons: [{ slug: 'murder-row', name: 'Murder Row' }, { slug: 'kings-rest', name: "Kings' Rest" }] },
      ] };
    }
    if (route === '/mythic-plus/runs') {
      assert.equal(q.get('season'), 'season-mn-2');
      if (q.get('page') !== '0') return { rankings: [] }; // one page each
      if (q.get('dungeon') === 'murder-row') {
        return { rankings: [
          { rank: 1, run: { mythic_level: 20, roster: [player(1, BAL, buildA), player(2, BAL, buildA2), player(3, FERAL, feral)] } },
          { rank: 2, run: { mythic_level: 19, roster: [player(1, BAL, buildB), player(4, BAL, buildB), player(5, BAL, buildA)] } }, // P1 again: ignored
          { rank: 3, run: { mythic_level: 18, roster: [player(6, 251, mage), player(7, BAL, '')] } }, // mismatch + empty
        ] };
      }
      return { rankings: [{ rank: 1, run: { mythic_level: 15, roster: [player(1, BAL, buildB)] } }] };
    }
    if (route === '/raiding/static-data') {
      return { raids: [{ slug: 'the-venomous-abyss', name: 'The Venomous Abyss', starts: { us: '2026-08-01T00:00:00Z' }, ends: { us: null },
        encounters: [{ slug: 'nymrissa', name: 'Nymrissa Wavecaller' }, { slug: 'sszorak', name: 'Sszorak' }] }] };
    }
    if (route === '/raiding/raid-rankings') {
      return { raidRankings: [
        { guild: { name: 'Guild One', realm: { slug: 'illidan' }, region: { slug: 'us' } }, encountersDefeated: [{ slug: 'nymrissa' }, { slug: 'sszorak' }] },
        { guild: { name: 'Guild Two', realm: { slug: 'draenor' }, region: { slug: 'eu' } }, encountersDefeated: [{ slug: 'nymrissa' }] },
      ] };
    }
    if (route === '/guilds/boss-kill') {
      if (q.get('guild') === 'Guild Two' && q.get('boss') === 'nymrissa' && q.get('difficulty') === 'heroic') {
        return { status: 404, body: {} }; // no recorded kill: must be skipped, not fatal
      }
      const raider = (name, code) => ({ character: { name, realm: { slug: q.get('realm') }, talentLoadout: { loadoutSpecId: BAL, loadoutText: code } } });
      return { roster: [raider(`${q.get('guild')}-a`, buildA), raider(`${q.get('guild')}-b`, buildA), raider(`${q.get('guild')}-c`, buildB)] };
    }
    if (extra[route]) return extra[route](q);
    return { status: 404, body: {} };
  };
}

const testConfig = { ...DEFAULTS, requestDelayMs: 0, cacheDir: null, minSamples: 1, raidDifficulties: ['mythic', 'heroic'] };
const quiet = () => {};

test('Mythic+: counts players not runs, groups patches, skips bad loadouts', async () => {
  const data = await run({ config: testConfig, parts: { mythic: true, raid: false }, log: quiet,
    fetchImpl: fakeFetch(seasonRoutes()), now: new Date('2026-09-26T00:00:00Z') });

  assert.equal(data.season.slug, 'season-mn-2');
  const balance = data.mythic[BAL];
  const murderRow = balance.find((e) => e.target === 'Murder Row');
  // Balance players on Murder Row: P1 (first run, buildA), P2 (buildA2 = A), P4 (B), P5 (A).
  // P1's second appearance and P7's empty loadout don't count.
  assert.equal(murderRow.samples, 4);
  assert.equal(murderRow.builds[0].count, 3);   // A and A2 grouped
  assert.equal(murderRow.builds[0].share, 0.75);
  assert.equal(murderRow.builds[0].code, buildA); // most common exact string
  assert.equal(murderRow.builds[1].count, 1);

  const all = balance[0];
  assert.equal(all.isAll, true);
  assert.equal(all.target, 'All dungeons');
  assert.equal(all.samples, 5); // 4 on Murder Row + P1 on Kings' Rest
  assert.equal(data.mythic[FERAL][1].target, 'Murder Row');
  assert.equal(data.mythic[64], undefined, 'mismatched spec loadout must be dropped');
  assert.equal(data.mythicStats.specMismatch, 1);
  assert.equal(data.mythicStats.unreadable, 1);
});

test('Raid: top guilds per difficulty, missing kills skipped', async () => {
  const data = await run({ config: testConfig, parts: { mythic: false, raid: true }, log: quiet,
    fetchImpl: fakeFetch(seasonRoutes()), now: new Date('2026-09-26T00:00:00Z') });

  assert.deepEqual(data.raids, ['The Venomous Abyss']);
  const mythic = data.raid.mythic[BAL];
  const nym = mythic.find((e) => e.target === 'Nymrissa Wavecaller');
  assert.equal(nym.samples, 6);                  // 2 guilds x 3 raiders
  assert.equal(nym.builds[0].count, 4);          // A: 2 per guild
  assert.equal(nym.builds[0].share, 0.667);
  const heroicNym = data.raid.heroic[BAL].find((e) => e.target === 'Nymrissa Wavecaller');
  assert.equal(heroicNym.samples, 3);            // Guild Two's heroic kill was a 404
  assert.equal(mythic[0].target, 'All bosses');
});

test('minSamples hides thin data', async () => {
  const data = await run({ config: { ...testConfig, minSamples: 4 }, parts: { mythic: true, raid: false }, log: quiet,
    fetchImpl: fakeFetch(seasonRoutes()), now: new Date('2026-09-26T00:00:00Z') });
  const targets = data.mythic[BAL].map((e) => e.target);
  assert.deepEqual(targets, ['All dungeons', 'Murder Row']); // Kings' Rest had 1 player
  assert.equal(data.mythic[FERAL], undefined);
});

test('season picker prefers the current main season', () => {
  const season = pickSeason({ seasons: [
    { slug: 'a', is_main_season: true, starts: { us: '2025-01-01T00:00:00Z' }, ends: { us: '2025-06-01T00:00:00Z' } },
    { slug: 'b', is_main_season: false, starts: { us: '2026-01-01T00:00:00Z' }, ends: { us: null } },
    { slug: 'c', is_main_season: true, starts: { us: '2026-01-01T00:00:00Z' }, ends: { us: null } },
  ] }, new Date('2026-09-01T00:00:00Z'));
  assert.equal(season.slug, 'c');
});

// ---- The API client -----------------------------------------------------------

test('client: waits and retries on 429, adds the key, never caches the key', async () => {
  let hits = 0;
  const fetch = fakeFetch(() => {
    hits++;
    if (hits === 1) return { status: 429, headers: { 'retry-after': '0.01' }, body: {} };
    return { ok: true };
  });
  const dir = await mkdtemp(path.join(tmpdir(), 'lps-'));
  try {
    const api = new RaiderIO({ apiKey: 'SECRET', requestDelayMs: 0, cacheDir: dir, fetch });
    assert.deepEqual(await api.get('/mythic-plus/runs', { page: 0 }), { ok: true });
    assert.equal(fetch.calls.length, 2);
    assert.match(fetch.calls[1], /access_key=SECRET/);
    assert.equal(api.stats.retries, 1);

    // Second call: served from cache, no new request.
    assert.deepEqual(await api.get('/mythic-plus/runs', { page: 0 }), { ok: true });
    assert.equal(fetch.calls.length, 2);
    assert.equal(api.stats.cached, 1);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('client: 401 gives a clear API-key error', async () => {
  const api = new RaiderIO({ requestDelayMs: 0, fetch: fakeFetch(() => ({ status: 401, body: {} })) });
  await assert.rejects(api.get("/mythic-plus/runs", {}), /refused/);
});

// ---- The generated addon ------------------------------------------------------

test('toLua escapes strings and keys', () => {
  assert.equal(toLua('a"b\\c'), '"a\\"b\\\\c"');
  assert.match(toLua({ 102: 1, 'Kings\' Rest': 2, end: 3 }), /\[102\] = 1,[\s\S]*\["Kings' Rest"\] = 2,[\s\S]*\["end"\] = 3,/);
});

test('generated Data.lua loads in Lua 5.1 with the right values', async (t) => {
  let lua = 'lua5.1';
  try { execFileSync(lua, ['-v'], { stdio: 'ignore' }); } catch { t.skip('lua5.1 not installed'); return; }

  const data = await run({ config: testConfig, log: quiet, fetchImpl: fakeFetch(seasonRoutes()), now: new Date('2026-09-26T00:00:00Z') });
  const dir = await mkdtemp(path.join(tmpdir(), 'lps-'));
  try {
    const addonDir = await writeAddon(dir, data);
    const toc = await readFile(path.join(addonDir, 'LoadoutPlannerData.toc'), 'utf8');
    assert.match(toc, /## Interface: 120100/);
    const out = execFileSync(lua, ['-e', `
      dofile(${JSON.stringify(path.join(addonDir, 'Data.lua'))})
      local d = LoadoutPlannerData
      local mr
      for _, e in ipairs(d.mythic[102]) do if e.target == "Murder Row" then mr = e end end
      print(d.source, d.season.slug, mr.samples, mr.builds[1].share, d.raid.heroic[102][1].target)
    `]).toString().trim();
    assert.equal(out, 'raider.io\tseason-mn-2\t4\t0.75\tAll bosses');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
