// raiderio.js
// A small, polite client for the official Raider.IO API (https://raider.io/api).
//
// Politeness rules this client enforces:
//   * only the official /api/v1 endpoints (the access key is only valid there)
//   * one request at a time, with a pause between them (config.requestDelayMs)
//   * on 429 "too many requests" or a 5xx error: wait and retry, honoring
//     the server's Retry-After header when it sends one
//   * responses are cached on disk, so re-running within `cacheHours`
//     doesn't hit the API again
//   * a User-Agent that says who we are

import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import path from 'node:path';

const USER_AGENT = 'LoadoutPlannerSync/1.0 (personal WoW addon data; +https://raider.io/api)';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class RaiderIO {
  /**
   * @param {object} options
   * @param {string} [options.apiKey]        Raider.IO application key (optional, raises limits)
   * @param {string} [options.baseURL]       defaults to https://raider.io/api/v1
   * @param {number} [options.requestDelayMs] pause between requests
   * @param {string} [options.cacheDir]      where responses are cached (null = no cache)
   * @param {number} [options.cacheHours]    how long a cached response stays fresh
   * @param {number} [options.maxRetries]
   * @param {(msg: string) => void} [options.log]
   * @param {typeof fetch} [options.fetch]   injectable for tests
   */
  constructor(options = {}) {
    this.apiKey = options.apiKey || '';
    this.baseURL = (options.baseURL || 'https://raider.io/api/v1').replace(/\/$/, '');
    this.requestDelayMs = options.requestDelayMs ?? 1000;
    this.cacheDir = options.cacheDir ?? null;
    this.cacheHours = options.cacheHours ?? 6;
    this.maxRetries = options.maxRetries ?? 4;
    this.log = options.log || (() => {});
    this.fetch = options.fetch || globalThis.fetch;
    this.lastRequestAt = 0;
    this.stats = { requests: 0, cached: 0, retries: 0 };
  }

  /** Build the URL. The key is added separately so it never lands in logs or cache names. */
  url(endpoint, params) {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(params || {})) {
      if (value !== undefined && value !== null && value !== '') query.set(key, String(value));
    }
    return `${this.baseURL}${endpoint}?${query.toString()}`;
  }

  cachePath(url) {
    const name = createHash('sha1').update(url).digest('hex');
    return path.join(this.cacheDir, `${name}.json`);
  }

  async readCache(url) {
    if (!this.cacheDir) return null;
    try {
      const file = this.cachePath(url);
      const info = await stat(file);
      const ageHours = (Date.now() - info.mtimeMs) / 3_600_000;
      if (ageHours > this.cacheHours) return null;
      return JSON.parse(await readFile(file, 'utf8'));
    } catch {
      return null; // missing or unreadable: just fetch
    }
  }

  async writeCache(url, data) {
    if (!this.cacheDir) return;
    await mkdir(this.cacheDir, { recursive: true });
    await writeFile(this.cachePath(url), JSON.stringify(data));
  }

  /** Wait so requests are at least requestDelayMs apart. */
  async throttle() {
    const wait = this.lastRequestAt + this.requestDelayMs - Date.now();
    if (wait > 0) await sleep(wait);
    this.lastRequestAt = Date.now();
  }

  /**
   * GET an endpoint and return parsed JSON.
   * Returns null for a 400/404 (e.g. a guild with no recorded kill of
   * that boss), so one missing item doesn't stop the whole run.
   */
  async get(endpoint, params) {
    const url = this.url(endpoint, params);
    const cached = await this.readCache(url);
    if (cached) {
      this.stats.cached++;
      return cached;
    }

    const requestURL = this.apiKey ? `${url}&access_key=${encodeURIComponent(this.apiKey)}` : url;
    for (let attempt = 0; ; attempt++) {
      await this.throttle();
      this.stats.requests++;
      let response;
      try {
        response = await this.fetch(requestURL, {
          headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
        });
      } catch (error) {
        if (attempt >= this.maxRetries) throw new Error(`${endpoint}: network error (${error.message})`);
        this.stats.retries++;
        await sleep(2000 * 2 ** attempt);
        continue;
      }

      if (response.ok) {
        const data = await response.json();
        await this.writeCache(url, data);
        return data;
      }
      if (response.status === 400 || response.status === 404) {
        this.log(`  (skipped ${endpoint}: ${response.status})`);
        return null;
      }
      if ((response.status === 429 || response.status >= 500) && attempt < this.maxRetries) {
        this.stats.retries++;
        const retryAfter = Number(response.headers.get('retry-after'));
        const waitMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 5000 * 2 ** attempt;
        this.log(`  Raider.IO said ${response.status}; waiting ${Math.round(waitMs / 1000)}s before retrying...`);
        await sleep(waitMs);
        continue;
      }
      if (response.status === 401 || response.status === 403) {
        throw new Error(this.apiKey
          ? `${endpoint}: ${response.status} - check your API key (config.json or the RAIDERIO_API_KEY secret)`
          : `${endpoint}: ${response.status} - Raider.IO refused the request (no API key set)`);
      }
      throw new Error(`${endpoint}: HTTP ${response.status}`);
    }
  }

  // ---- The endpoints we use (all official, all read-only) ------------------

  mythicPlusStaticData(expansionID) {
    return this.get('/mythic-plus/static-data', { expansion_id: expansionID });
  }

  /** One page of the Mythic+ leaderboard. Each run includes its roster's talent loadouts. */
  mythicPlusRuns({ season, region, dungeon, page }) {
    return this.get('/mythic-plus/runs', { season, region, dungeon, affixes: 'all', page });
  }

  raidStaticData(expansionID) {
    return this.get('/raiding/static-data', { expansion_id: expansionID });
  }

  raidRankings({ raid, difficulty, region, limit }) {
    return this.get('/raiding/raid-rankings', { raid, difficulty, region, limit });
  }

  /** A guild's first kill of a boss, with each raider's talent loadout. */
  guildBossKill({ raid, difficulty, region, realm, guild, boss }) {
    return this.get('/guilds/boss-kill', { raid, difficulty, region, realm, guild, boss });
  }
}
