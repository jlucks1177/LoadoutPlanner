// aggregate.js
// From samples to "most-played builds", per spec and per dungeon/boss.
//
// Rules:
//   * one vote per PLAYER per target: a top player who ran the same dungeon
//     30 times counts once (their highest-ranked run, which comes first)
//   * builds are grouped by content (see talentString.js), so the same
//     talents exported on two patches count as one build
//   * each group is shown with its most common exact string
//   * "share" = fraction of that spec's players on this target who used it
//   * an "All ..." entry combines every target (one vote per player per
//     target, so it weights each dungeon/boss by how many players ran it)

/** Tally a list of samples into ranked builds. */
function rank(samples, keep) {
  const groups = new Map(); // contentKey -> { count, codes: Map(code -> count) }
  for (const sample of samples) {
    let group = groups.get(sample.contentKey);
    if (!group) {
      group = { count: 0, codes: new Map() };
      groups.set(sample.contentKey, group);
    }
    group.count++;
    group.codes.set(sample.code, (group.codes.get(sample.code) || 0) + 1);
  }
  const total = samples.length;
  return [...groups.values()]
    .sort((a, b) => b.count - a.count)
    .slice(0, keep)
    .map((group) => {
      const [code] = [...group.codes.entries()].sort((a, b) => b[1] - a[1])[0];
      return { code, count: group.count, share: Math.round((group.count / total) * 1000) / 1000 };
    });
}

/** Keep the first sample per (target, player). */
function onePerPlayer(samples) {
  const seen = new Set();
  return samples.filter((sample) => {
    if (sample.who === undefined || sample.who === null || sample.who === '') return true;
    const key = `${sample.target}|${sample.who}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Build the entries for one bucket (e.g. Mythic+, or Heroic raid) of one spec.
 * targetOrder: target names in display order.
 * Returns [{ target, isAll, samples, builds: [{ code, count, share }] }]
 */
function entriesFor(samples, targetOrder, allLabel, { minSamples, keep }) {
  const entries = [];
  if (samples.length >= minSamples) {
    entries.push({ target: allLabel, isAll: true, samples: samples.length, builds: rank(samples, keep) });
  }
  for (const target of targetOrder) {
    const forTarget = samples.filter((s) => s.target === target);
    if (forTarget.length >= minSamples) {
      entries.push({ target, isAll: false, samples: forTarget.length, builds: rank(forTarget, keep) });
    }
  }
  return entries;
}

function groupBySpec(samples) {
  const bySpec = new Map();
  for (const sample of samples) {
    if (!bySpec.has(sample.specID)) bySpec.set(sample.specID, []);
    bySpec.get(sample.specID).push(sample);
  }
  return bySpec;
}

/**
 * @param {object} input
 * @param {Array} input.mythicSamples
 * @param {string[]} input.dungeonOrder
 * @param {Array} input.raidSamples
 * @param {string[]} input.bossOrder
 * @param {string[]} input.difficulties
 * @param {object} options  { minSamples, keep }
 */
export function aggregate(input, options) {
  const result = { mythic: {}, raid: {} };

  const mythic = onePerPlayer(input.mythicSamples || []);
  for (const [specID, samples] of groupBySpec(mythic)) {
    const entries = entriesFor(samples, input.dungeonOrder || [], 'All dungeons', options);
    if (entries.length > 0) result.mythic[specID] = entries;
  }

  for (const difficulty of input.difficulties || []) {
    const raidSamples = onePerPlayer((input.raidSamples || []).filter((s) => s.difficulty === difficulty));
    const bySpec = {};
    for (const [specID, samples] of groupBySpec(raidSamples)) {
      const entries = entriesFor(samples, input.bossOrder || [], 'All bosses', options);
      if (entries.length > 0) bySpec[specID] = entries;
    }
    if (Object.keys(bySpec).length > 0) result.raid[difficulty] = bySpec;
  }
  return result;
}
