import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { runParses, DEFAULTS } from '../src/sync.js';
import { writeBundle } from '../src/writeAddon.js';
import { makeCode, fakeFetch } from './helpers.js';

const BAL = 102;
const code = (variant) => makeCode({ specID: BAL, hash: 3, content: variant.repeat(20) });

// A fake parses.gg + the two Raider.IO static-data calls used to find the season.
function routes() {
  return (route, q) => {
    if (route === '/mythic-plus/static-data') {
      return { seasons: [{ slug: 'season-mn-2', name: 'Midnight Season 2', is_main_season: true,
        starts: { us: '2026-08-01T00:00:00Z' }, ends: { us: null },
        dungeons: [{ slug: 'murder-row', name: 'Murder Row' }, { slug: 'kings-rest', name: "Kings' Rest" }] }] };
    }
    if (route === '/raiding/static-data') {
      return { raids: [{ slug: 'the-venomous-abyss', name: 'The Venomous Abyss', starts: { us: '2026-08-01T00:00:00Z' }, ends: { us: null },
        encounters: [{ slug: 'nymrissa', name: 'Nymrissa Wavecaller' }, { slug: 'nekzali', name: "Nek'zali the Soulcoiler" }] }] };
    }
    if (route === '/api/builds/export') {
      const tier = q.get('tier');
      assert.equal(q.get('cohort'), 'all');
      if (tier === 'b10') {
        return { gameBuild: '12.1.0.1', specs: [{ specId: BAL, classId: 11, encounters: [
          { encounterId: null, label: 'All Dungeons', exportCode: code('10'), count: 300, sample: 500 },
          { encounterId: 587, label: 'Murder Row', exportCode: code('10'), count: 40, sample: 50 },
          { encounterId: 249, label: 'Kings Rest', exportCode: code('11'), count: 9, sample: 30 }, // no apostrophe: still matches
          { encounterId: 12, label: 'Skyreach', exportCode: code('01'), count: 5, sample: 5 },      // last season: dropped
          { encounterId: 13, label: 'Murder Row', exportCode: makeCode({ specID: 64, content: '1' }) }, // wrong spec: dropped
        ] }, { specId: 103, classId: 11, encounters: [
          { encounterId: null, label: 'All Dungeons', exportCode: makeCode({ specID: 103, content: '1' }) }, // aggregate only: dropped
        ] }] };
      }
      if (tier === 'd16') {
        return { specs: [{ specId: BAL, classId: 11, encounters: [
          { encounterId: 3470, label: "Nek'zali the Soulcoiler", exportCode: code('00'), count: 3, sample: 4 },
        ] }] };
      }
      if (tier === 'd14') return { status: 500, body: {} }; // flaky tier: retried, then skipped
      return { specs: [] };
    }
    return { status: 404, body: {} };
  };
}

const config = { ...DEFAULTS, requestDelayMs: 0, cacheDir: null };
const quiet = () => {};

test('parses.gg: current season only, names like the journal, shares from count/sample', async () => {
  const data = await runParses({ config, log: quiet, fetchImpl: fakeFetch(routes()), now: new Date('2026-09-26T00:00:00Z') });
  assert.equal(data.source, 'parses.gg');
  assert.equal(data.season.slug, 'season-mn-2');

  const balance = data.mythic[BAL];
  assert.deepEqual(balance.map((e) => e.target), ['All dungeons', 'Murder Row', "Kings' Rest"]);
  assert.equal(balance[0].isAll, true);
  assert.equal(balance[1].samples, 50);
  assert.equal(balance[1].builds[0].share, 0.8);
  assert.equal(data.mythic[103], undefined, 'an aggregate with no current-season data is not trusted');
  assert.equal(data.stats.outOfSeason, 1);
  assert.equal(data.stats.unreadable, 1);

  assert.equal(data.raid.mythic[BAL][0].target, "Nek'zali the Soulcoiler");
  assert.equal(data.raid.normal, undefined, 'a failing tier is skipped, not fatal');
});

test('bundle: written once, left alone when builds are unchanged', async (t) => {
  const dir = await mkdtemp(path.join(tmpdir(), 'lpb-'));
  try {
    const fetchImpl = fakeFetch(routes());
    const first = await runParses({ config, log: quiet, fetchImpl, now: new Date('2026-09-26T00:00:00Z') });
    const one = await writeBundle(dir, { parses: first });
    assert.equal(one.changed, true);

    // Next day, same builds: no change, so the daily job won't publish.
    const second = await runParses({ config, log: quiet, fetchImpl, now: new Date('2026-09-27T00:00:00Z') });
    assert.equal((await writeBundle(dir, { parses: second })).changed, false);

    // A build changes: written again.
    second.mythic[BAL][1].builds[0].share = 0.9;
    assert.equal((await writeBundle(dir, { parses: second })).changed, true);

    const lua = 'lua5.1';
    try { execFileSync(lua, ['-v'], { stdio: 'ignore' }); } catch { t.skip('lua5.1 not installed'); return; }
    const out = execFileSync(lua, ['-e', `
      dofile(${JSON.stringify(path.join(dir, 'Data', 'Builtin.lua'))})
      local p = LoadoutPlannerBuiltin.parses
      print(p.source, p.mythic[102][2].target, p.mythic[102][2].builds[1].share)
    `]).toString().trim();
    assert.equal(out, 'parses.gg\tMurder Row\t0.9');
    assert.match(await readFile(path.join(dir, 'Data', 'Builtin.lua'), 'utf8'), /-- content-hash: [0-9a-f]{40}/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
