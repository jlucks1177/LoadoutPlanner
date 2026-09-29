# LoadoutPlannerSync

A small Node.js program that runs on your PC, asks the **official Raider.IO API** which talent builds the top players are using, and writes the answer as a tiny WoW addon, **LoadoutPlannerData**. In game, LoadoutPlanner's **Top builds** panel then shows, for your spec:

- **Mythic+:** the most-played build on each dungeon (and across all dungeons), from the season's top keys.
- **Raid:** the most-played build on each boss, on Mythic and Heroic, from the top guilds' kills.

Each row shows **how popular** that build is ("72% of 40 players"), and the right-click menu offers the **runner-up builds**.

Addons can't use the internet, so this is how the data gets into the game: the program writes a Lua file into your AddOns folder, and the game loads it on the next `/reload`.

---

> **Most players don't need this.** LoadoutPlanner ships with the builds built in, refreshed daily by a GitHub Action that runs this same program in **bundle mode** (see section 8). Run it yourself only if you want your own Raider.IO data, or your own settings.

## 1. What you need

- **Node.js 18 or newer.** Check with `node -v` in a terminal. If you don't have it, install the LTS version from nodejs.org. There are no other dependencies and nothing to `npm install`.
- **A Raider.IO API key** (optional, but recommended because keyed requests get higher limits):
  1. Log in at raider.io with your Battle.net account.
  2. Open your **account settings** and find the section for **API / applications**. Register an application (the name can be anything, like "LoadoutPlanner personal").
  3. Copy the key it gives you.
  4. **Read the API terms shown there.** This program only uses the official, documented `/api/v1` endpoints, for personal use, one request per second.

## 2. Set it up

1. Unzip **LoadoutPlannerSync** somewhere that is **not** inside your AddOns folder, for example `Documents\LoadoutPlannerSync`.
2. Copy `config.example.json` to `config.json` and edit it:

| Setting | What it does | Default |
|---|---|---|
| `apiKey` | Your Raider.IO key. Stays on your PC: it's never logged or written to the cache. | none |
| `addonsPath` | Your AddOns folder, e.g. `C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns` (double every backslash in JSON). Leave empty to write to `./output` instead. | `./output` |
| `region` | Leaderboard region: `world`, `us`, `eu`, `kr`, `tw`. | `world` |
| `mythicPlusPages` | Leaderboard pages per dungeon, about 20 runs each. More pages means more players and slower syncs. | 5 |
| `raidGuilds` | Top guilds per raid difficulty. | 20 |
| `raidDifficulties` | Any of `mythic`, `heroic`, `normal`. | mythic, heroic |
| `minSamples` | Don't publish a build seen on fewer players than this. | 3 |
| `buildsPerTarget` | The top build plus how many runners-up. | 3 |
| `requestDelayMs` | Pause between requests. Please don't go below 500. | 1000 |
| `cacheHours` | Re-running within this many hours reuses downloaded answers. | 6 |
| `expansionID` | Raider.IO's expansion number (11 = Midnight). | 11 |

The program refuses an `addonsPath` that doesn't end in `AddOns`, so a typo can't make it write somewhere unexpected. It only ever writes the `LoadoutPlannerData` folder.

## 3. Run it

In a terminal, in the LoadoutPlannerSync folder:

```
npm run sync
```

It prints each step: the season, the dungeons, and the raid and its guilds. A full sync is about 400 requests, roughly **7 minutes** at one per second. Then, in game, `/reload`, open your talents, click **Top builds**, and pick the **Raider.IO** source.

Options: `node src/sync.js --no-raid` (Mythic+ only, about a minute), `--no-mythic`, or `--config other.json`.

## 4. Run it daily (optional)

Builds shift through a season, so a daily sync keeps them fresh. The panel turns its "Synced ..." line orange when the data is 3 or more days old.

**Windows** (Task Scheduler, every day at 9:00). Adjust the path:

```
schtasks /Create /SC DAILY /ST 09:00 /TN "LoadoutPlannerSync" /TR "cmd /c cd /d %USERPROFILE%\Documents\LoadoutPlannerSync && node src\sync.js >> sync.log 2>&1"
```

**macOS / Linux** (cron, every day at 9:00): add this with `crontab -e`:

```
0 9 * * * cd ~/Documents/LoadoutPlannerSync && /usr/local/bin/node src/sync.js >> sync.log 2>&1
```

If WoW is running during a sync, just `/reload` afterwards to pick up the new data.

## 5. What the numbers mean

- **One vote per player per place.** A top player who ran Murder Row 30 times counts once, using their highest-ranked run.
- **Same talents = same build**, even if the players exported them on different patches (the program compares the talents themselves, not the raw strings).
- **"72% of 40 players"** means that of the 40 players of your spec found on that dungeon's top runs (or on that boss's top-guild kills), 72% used this exact build.
- **Raid data comes from each guild's first kill** of a boss (that's what the API reports). Early in a tier, Mythic has few bosses killed, so expect gaps, which show as "No logged build yet".
- **Loadouts that don't match the player's spec** (stale or broken data) are skipped. The counts are in `mythicStats` / `raidStats` in the generated `Data.lua`.

## 6. Troubleshooting

| Message | Fix |
|---|---|
| `401/403 - check your API key` | The key in `config.json` is wrong or was revoked. Create a new one on raider.io. |
| `Raider.IO said 429; waiting...` | You hit the rate limit. It waits and retries by itself. If it happens often, raise `requestDelayMs`. |
| `addonsPath should end in "AddOns"` | Point it at the `AddOns` folder itself, not `_retail_` or `Interface`. |
| `No Mythic+ season found` | A new expansion may need a new `expansionID`. |
| In game: "No Raider.IO data yet" | Check that `AddOns\LoadoutPlannerData\Data.lua` exists, that the addon is enabled in the AddOns list, then `/reload`. |
| Writing to `Program Files` fails | Run the terminal as your normal user. WoW's folder is normally writable. If not, set `addonsPath` to empty and copy the `output\LoadoutPlannerData` folder over manually. |

## 7. How it works (the code)

| File | Job |
|---|---|
| `src/sync.js` | The command: reads the config, runs each step, writes the addon, prints a summary. |
| `src/raiderio.js` | The API client: official endpoints only, one request at a time, retries 429/5xx using `Retry-After`, disk cache, and the key kept out of logs and cache file names. |
| `src/collect.js` | Finds the current season and raid, walks the Mythic+ leaderboards (each run already lists every player's loadout) and the top guilds' boss kills, and turns each player into a sample. |
| `src/talentString.js` | Reads talent strings without the game: 6 bits per character, least significant bit first, then the header (version, spec, tree hash). Used to check the spec and to group identical builds. |
| `src/aggregate.js` | One vote per player per place, grouped by talents, ranked. Adds the "All dungeons" / "All bosses" totals. |
| `src/writeAddon.js` | Writes `LoadoutPlannerData.toc` and `Data.lua` into a temporary folder, then swaps it in, so the game never sees a half-written file. |
| `test/` | `npm test`: 11 tests against a fake Raider.IO, including retries, caching, player de-duplication, patch grouping, and loading the output in Lua 5.1 (if installed). |

**Endpoints used** (all read-only): `/mythic-plus/static-data`, `/mythic-plus/runs`, `/raiding/static-data`, `/raiding/raid-rankings`, `/guilds/boss-kill`. Field names were confirmed against the MIT-licensed `tmaffia/raiderio` Go client and its recorded API responses.

Data © Raider.IO. This tool is not affiliated with Raider.IO.

## 8. Bundle mode (what the daily GitHub Action runs)

```
node src/sync.js --bundle <path to the LoadoutPlanner folder> --sources parses,raiderio
```

- Writes `Data/Builtin.lua` **inside** LoadoutPlanner, defining `LoadoutPlannerBuiltin = { parses = ..., raiderio = ... }`, each in the same shape as `LoadoutPlannerData`.
- `--sources` picks which sources to include. `parses` needs no key. `raiderio` uses `RAIDERIO_API_KEY` from the environment (a GitHub secret), or `apiKey` from `config.json`.
- **parses.gg**: `https://parses.gg/api/builds/export?tier=…&cohort=…`, two requests per difficulty for every spec: the **top 10%** of players (`cohort=top10`) and all players (`cohort=all`). Each dungeon and boss uses the top-10% build when at least 5 top players logged it, and all players otherwise; the entry records which (`cohort`). parses.gg states its data is free to reuse. Its responses include earlier seasons' content too, so builds are filtered to the current season's dungeons and bosses, by name, using Raider.IO's public static data.
- **Only rewrites the file when the builds changed.** A content hash in the file's header ignores timestamps, so the daily job only publishes a release when something really changed.
- **Refuses to write an empty bundle.** If a source returns nothing (site down, format changed), it exits with an error, so the job fails loudly and players keep the previous builds.
