# LoadoutPlanner: notes for Claude

A World of Warcraft addon for **Midnight (12.1, `## Interface: 120100`)**. It docks a panel beside the talent window that manages talent loadouts. You can tag builds to raids, bosses, dungeons and difficulties, it prompts you to switch builds when you zone in, and it shows the most-played builds for your spec ("Top builds"). The author is Joe, published on GitHub (`jlucks1177/LoadoutPlanner`) and CurseForge (project 1713714).

## How Joe works: read this first

- Joe is a bootcamp grad (Fullstack Academy, 2026) learning addon development through this project. **Explain what you change and why**, in plain language. Don't just drop code.
- Every version gets a chapter in **LEARNING.md** (a tutorial: numbered sections, 📌 for "what changed", 🔹 for concepts, short code excerpts, an exercise at the end). The latest is Part 18, sections 80–83. Add a Part for each new version.
- **README.md** is the player-facing reference. Keep it accurate when behavior changes (the file map in section 14 too).
- Joe tests in game on Windows and sends screenshots. You can't run WoW. Say what you verified with the tests, and what only an in-game check can confirm.

## Hard rules

1. **Archon.gg blocks automated access. Never scrape it or work around that.** The addon only builds a link and lets the player paste a talent string back in (Archon.lua).
2. **Raider.IO data is only redistributed with their permission.** The code exists, but it's off until the repo variable `INCLUDE_RAIDERIO=true` (see PUBLISHING.md Part E). Only use official `/api/v1` endpoints, throttled.
3. **parses.gg** (`https://parses.gg/api/builds/export`) says its data is free to reuse. It's the built-in source.
4. **Never put secrets in the repo.** API tokens live only in GitHub Secrets (`CF_API_KEY`, `WAGO_API_TOKEN`, `RAIDERIO_API_KEY`), or in `tools/sync/config.json`, which is gitignored.
5. **Taint:** never change talents or protected frames in combat (`InCombatLockdown()`). Use `HookScript` / `hooksecurefunc`, never replace Blizzard functions. Only `SetPoint`/`SetScale` on `PlayerSpellsFrame`, and restore it.
6. **Fail soft.** Blizzard renames things between patches. Check that templates, atlases and APIs exist (see Style.lua's `SetAtlas` / `tryCreate`, and the `pcall` in `ns.On`). A missing asset should make the addon plainer, never broken. Mark guesses about the game API with `-- VERIFY:` comments.

## Code layout

Lua 5.1 (WoW's version). Each file starts with `local addonName, ns = ...`, and everything shared goes on `ns`. The only globals are the SavedVariables (`LoadoutPlannerBuilds`, `LoadoutPlannerDB`), `LoadoutPlannerBuiltin` (the data file), named frames, `SLASH_`/`SlashCmdList` and `StaticPopupDialogs`. The **TOC load order matters**: a file can only use what files above it defined.

| File | Job |
|---|---|
| `Data/Builtin.lua` | **Generated daily by CI. Never edit by hand.** parses.gg builds as `LoadoutPlannerBuiltin`. |
| `Core.lua` | `ns` basics: `ns.Print`, event dispatcher `ns.On`/`ns.Off`, refresh signal `ns.Notify`/`ns.OnRefresh`, `/lp` routing via `ns.commands`. |
| `Style.lua` | Shared look: `ns.Style.CreatePanel` (DefaultPanelFlatTemplate), spec art, `MinimalScrollBar`, row highlight, icon rings, all with fallbacks. |
| `Loadouts.lua` | Blizzard loadouts (C_ClassTalents): read and switch. |
| `Data.lua` | SavedVariables and tags (instances, bosses, categories; per spec; per difficulty). |
| `Builds.lua` | Custom build library: groups, import codes. |
| `ImportTLE.lua` | Import from the Talent Loadout Ex addon. |
| `Import.lua` | Import code → talents: stage (click) / apply (double-click) into the selected loadout. |
| `Journal.lua` | Encounter Journal: season raids, dungeons, bosses, icons, difficulty. |
| `Context.lua` | Where you are → which tagged builds apply. |
| `Prompt.lua` | The zone-in "Change talents for …?" prompt. |
| `Diff.lua` | Hover comparison tooltip (talent map). |
| `Background.lua` | Talent-art transparency, slider widget. |
| `SpecBar.lua` | Spec switch buttons. |
| `IconPicker.lua`, `Editor.lua` | Build editor with embedded icon grid. |
| `Window.lua` | Main window and placement beside/inside the talent window. |
| `TagPanel.lua` | Tagging panel. |
| `Archon.lua` | Archon link + paste dialog. |
| `TopBuilds.lua` | Top builds panel: sources (built-in parses.gg, `ArchonTalentsData`/`PeaversTalentsData` API, `LoadoutPlannerData` from the sync tool). |
| `UI.lua` | The loadout list inside the main window. |

Other folders:
- `tools/sync/`: Node 18+ tool (no dependencies) that fetches builds and writes `Data/Builtin.lua` (`--bundle`) or a personal `LoadoutPlannerData` addon. Its own README.
- `tools/test/`: the addon's tests (below).
- `.github/workflows/`:
  - `ci.yml` runs the tests on every push.
  - `daily-builds.yml` refreshes the data daily and releases if it changed.
  - `release.yml` publishes when a `v*` tag is pushed.
- `.pkgmeta`: what the BigWigs packager leaves out of the player zip (tools, docs, VERSION, this file).

## Testing

```
lua tools/test/run.lua          # from the repo root; any Lua 5.1+
cd tools/sync && npm test       # the sync tool
```

- `tools/test/wow.lua` is a fake WoW API. Frames answer any method call. Add stubs there when the addon starts using a new API.
- `test_load.lua` loads every TOC file in three modes: `modern`, `fallback` (no atlases), `missing` (templates gone).
- `test_topbuilds.lua` drives the Top builds panel with `fixtures/Builtin.lua` (fake data).
- **Add a test for every bug fix** that fails without the fix. Check that it does fail, since a test that can't fail proves nothing.
- The tests prove the code loads and the logic is right. They can't show layout, art, or real API behavior. Say so, and ask Joe for a screenshot.

## Releasing

Joe runs these from the repo root (PowerShell on Windows):

1. `git pull` first, always. The daily job commits new builds, so local copies fall behind.
2. Make the change, run the tests, and have Joe check it in game. His `AddOns\LoadoutPlanner` may be a junction to this folder, so `/reload` picks up edits.
3. Bump `VERSION` (patch for fixes, minor for features).
4. `git add -A`, `git commit -m "…"`, `git push`.
5. `git tag -a vX.Y.Z -m "vX.Y.Z"`, `git push origin vX.Y.Z`. The Release workflow tests, packages, and uploads to GitHub and CurseForge.

Careful: **the daily job packages whatever is on `main`**. Only push working code to `main`, and use a branch for anything unfinished. Commit messages end with the co-author line your harness provides.
