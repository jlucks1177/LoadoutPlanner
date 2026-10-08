# LoadoutPlanner: notes for Claude

A World of Warcraft addon for **Midnight (12.1, `## Interface: 120100`)**. It docks a panel beside the talent window that manages talent loadouts. You can tag builds to raids, bosses, dungeons and difficulties, it prompts you to switch builds when you zone in, and it shows the most-played builds for your spec ("Top builds"). Published on GitHub (`jlucks1177/LoadoutPlanner`) and CurseForge (project 1713714).

## How the maintainer works: read this first

- The maintainer is learning addon development through this project. **Explain what you change and why**, in plain language. Don't just drop code.
- Explain changes in the conversation (what changed, why, what to check in game). The old LEARNING.md tutorial and PUBLISHING.md guide were removed in v0.19; don't recreate them unless asked.
- **README.md** is the player-facing reference. Keep it accurate when behavior changes (the file map in section 14 too).
- Claude may work on the repo through a link to the maintainer's PC (file access, no terminal), so the maintainer runs the git commands. The `AddOns\LoadoutPlanner` folder can be a junction to the repo.
- The maintainer tests in game on Windows and sends screenshots. You can't run WoW. Say what you verified with the tests, and what only an in-game check can confirm.

## Hard rules

1. **Archon.gg blocks automated access. Never scrape it or work around that.** The addon only builds a link and lets the player paste a talent string back in (Archon.lua).
2. **Raider.IO data is not redistributed.** The built-in Top builds come from **parses.gg** (its export says the data is free to reuse), using the top-10% cohort with a fallback to all players. Raider.IO is only a personal-sync source (LoadoutPlannerData); `INCLUDE_RAIDERIO` exists in the daily job but stays off. A switch to Raider.IO was tried in v0.19 and backed out; don't reintroduce it without asking.
3. **Only public, allowed sources.** parses.gg's export endpoint; Raider.IO's official `/api/v1` for personal syncs, throttled. Never scrape websites.
4. **Never put secrets in the repo.** API tokens live only in GitHub Secrets (`CF_API_KEY`, `WAGO_API_TOKEN`, `RAIDERIO_API_KEY`), or in `tools/sync/config.json`, which is gitignored.
5. **Taint:** never change talents or protected frames in combat (`InCombatLockdown()`). Use `HookScript` / `hooksecurefunc`, never replace Blizzard functions. Only `SetPoint`/`SetScale` on `PlayerSpellsFrame`, and restore it.
6. **Blizzard loadouts are the slots; custom builds fill the active one** (the maintainer's design). Clicking a Blizzard loadout row switches Blizzard's loadout like the dropdown. Applying a custom build commits it and saves it INTO the selected Blizzard loadout (`C_ClassTalents.SaveConfig`). Don't change this without asking the maintainer.
7. **Don't read other addons' private data.** The Raider.IO addon's talent builds are private to it (no public API). Only use data an addon deliberately exposes through a public global API.
8. **Fail soft.** Blizzard renames things between patches. Check that templates, atlases and APIs exist (see Style.lua's `SetAtlas` / `tryCreate`, and the `pcall` in `ns.On`). A missing asset should make the addon plainer, never broken. Mark guesses about the game API with `-- VERIFY:` comments.

## Code layout

Lua 5.1 (WoW's version). Each file starts with `local addonName, ns = ...`, and everything shared goes on `ns`. The only globals are the SavedVariables (`LoadoutPlannerBuilds`, `LoadoutPlannerDB`), `LoadoutPlannerBuiltin` (the data file), named frames, `SLASH_`/`SlashCmdList` and `StaticPopupDialogs`. The **TOC load order matters**: a file can only use what files above it defined.

| File | Job |
|---|---|
| `Data/Builtin.lua` | **Generated daily by CI. Never edit by hand.** parses.gg builds as `LoadoutPlannerBuiltin.parses`. |
| `Core.lua` | `ns` basics: `ns.Print`, event dispatcher `ns.On`/`ns.Off`, refresh signal `ns.Notify`/`ns.OnRefresh`, `/lp` routing via `ns.commands`. |
| `Style.lua` | Shared look: `ns.Style.CreatePanel` (DefaultPanelFlatTemplate), spec art, `MinimalScrollBar`, row highlight, icon rings, all with fallbacks. |
| `Loadouts.lua` | Blizzard loadouts (C_ClassTalents): read and switch. |
| `Data.lua` | SavedVariables and tags (instances, bosses, categories; per spec; per difficulty). |
| `Builds.lua` | Custom build library: groups, import codes. |
| `ImportTLE.lua` | Import from the Talent Loadout Ex addon. |
| `Import.lua` | Import code → talents: stage (click) / apply (double-click) into the selected loadout. |
| `ImportDialog.lua` | Checkbox strip under Blizzard's `ClassTalentLoadoutImportDialog`: ticked, our button covers Blizzard's Import button and applies the code via `ns.ApplyBuild` (no Blizzard function is replaced). Adds nothing if the dialog isn't shaped as expected. |
| `Journal.lua` | Encounter Journal: season raids, dungeons, bosses, icons, difficulty. |
| `Context.lua` | Where you are → which tagged builds apply. |
| `Prompt.lua` | The zone-in "Change talents for …?" prompt. |
| `BossPrompt.lua` | Boss-by-boss prompts: new map area (`C_Map.GetBestMapForUnit` + `C_EncounterJournal.GetEncountersOnMap`) and after each kill (`ENCOUNTER_END`), offering the next living boss's build, then later bosses'. Next boss untagged = no prompt. CheckContext calls `ns.TryBossPrompt` first and leaves boss tags out of the zone-in prompt while this is on. |
| `Diff.lua` | Hover comparison tooltip (talent map). |
| `Background.lua` | Talent-art transparency, slider widget. |
| `SpecBar.lua` | Spec switch buttons. |
| `IconPicker.lua`, `Editor.lua` | Build editor with embedded icon grid. |
| `Window.lua` | Main window and placement beside/inside the talent window. |
| `TagPanel.lua` | Tagging panel. |
| `Archon.lua` | Archon link + paste dialog. |
| `TopBuilds.lua` | Top builds panel: built-in parses.gg data (top 10% of players), or `LoadoutPlannerData` from a personal Raider.IO sync; per-row source link. |
| `UI.lua` | The loadout list inside the main window. |
| `Simc.lua` | Adds custom builds to the SimulationCraft addon's `/simc` export (`# Saved Loadout:` pairs) for Raidbots; recomputes SimC's Adler-32 checksum. Leaves the profile untouched if it doesn't end in `# Checksum:`. |

Other folders:
- `tools/sync/`: Node 18+ tool (no dependencies) that fetches builds and writes `Data/Builtin.lua` (`--bundle`) or a personal `LoadoutPlannerData` addon. Its own README.
- `tools/test/`: the addon's tests (below).
- `.github/workflows/`:
  - `ci.yml` runs the tests on every push.
  - `daily-builds.yml` refreshes the parses.gg data daily and commits it; it only releases if `AUTO_RELEASE` is on.
  - `release.yml` publishes when a `v*` tag is pushed.
- `.pkgmeta`: what the BigWigs packager leaves out of the player zip (tools, VERSION, this file).

## Testing

```
lua tools/test/run.lua          # from the repo root; any Lua 5.1+
cd tools/sync && npm test       # the sync tool
```

- `tools/test/wow.lua` is a fake WoW API. Frames answer any method call. Add stubs there when the addon starts using a new API.
- `test_load.lua` loads every TOC file in three modes: `modern`, `fallback` (no atlases), `missing` (templates gone).
- `test_topbuilds.lua` drives the Top builds panel with `fixtures/Builtin.lua` (fake parses.gg data).
- `test_bossprompt.lua` plays a fake four-boss raid over two map areas: zone-in, wipe, kills, an untagged boss, combat, already wearing, skipping ahead, at most two extras, re-offer on re-entry (10 s gap), option off.
- `test_importdialog.lua` checks the Import-dialog checkbox with a fake Blizzard dialog (off by default, applies via `ns.ApplyBuild`, stays open on errors, disabled on the Starter Build).
- `test_simc.lua` checks the SimulationCraft export (pairs added, every build listed even duplicates, checksum valid, other specs skipped, option off).
- `test_tags.lua` uses a fake Encounter Journal to check boss lists, left-out journal pages, the Keystone Dungeons migration, which builds the zone-in prompt offers, ring colours, and loadout/build separation.
- **Add a test for every bug fix** that fails without the fix. Check that it does fail, since a test that can't fail proves nothing.
- The tests prove the code loads and the logic is right. They can't show layout, art, or real API behavior. Say so, and ask the maintainer for a screenshot.

## GitHub settings (already set up)

| Name | Kind | Purpose |
|---|---|---|
| `CF_API_KEY` | secret | CurseForge upload token (project 1713714) |
| `CURSEFORGE_PROJECT_ID` | variable | `1713714` |
| `WAGO_API_TOKEN` / `WAGO_PROJECT_ID` | secret / variable | Wago uploads (optional, may be unset) |
| `RAIDERIO_API_KEY` / `INCLUDE_RAIDERIO` | secret / variable | Would add Raider.IO builds to the daily data. **Not set; leave off** (see rule 2). |
| `AUTO_RELEASE` | variable | `true` = the daily job also releases to GitHub/CurseForge when builds change. **Unset by default: nothing publishes without a version tag.** |

Actions need **Read and write** workflow permissions (Settings → Actions → General). Files under `.github/` can't be written through the link to the maintainer's PC; send them to be placed by hand.

## Releasing

The maintainer runs these from the repo root (PowerShell on Windows):

1. `git pull` first, always. The daily job commits new builds, so local copies fall behind.
2. Make the change, run the tests, and check it in game. The `AddOns\LoadoutPlanner` folder may be a junction to this folder, so `/reload` picks up edits.
3. Bump `VERSION` (patch for fixes, minor for features) and add a section for it at the top of `CHANGELOG.md` (the packager uses it as the CurseForge release notes; see `.pkgmeta`).
4. `git add -A`, `git commit -m "…"`, `git push`.
5. `git tag -a vX.Y.Z -m "vX.Y.Z"`, `git push origin vX.Y.Z`. The Release workflow tests, packages, and uploads to GitHub and CurseForge. **Only a tag publishes** (unless `AUTO_RELEASE` is turned on).

The daily job commits new builds to `main` (so `git pull` first). If `AUTO_RELEASE` is ever turned on, it packages whatever is on `main`, so then only push working code and use branches for unfinished work. Commit messages end with the co-author line your harness provides.
