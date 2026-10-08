# Changelog

## v0.20.0

### New: apply an imported code to your current loadout
- Blizzard's talent **Import** dialog (loadout dropdown → Import) has a new checkbox under it: "Apply to my current loadout instead". Ticked, the pasted code is applied onto the Blizzard loadout you have selected, the same way LoadoutPlanner applies your custom builds, instead of creating a new loadout.
- Unticked (the default), Blizzard's Import works exactly as before.
- If the code can't be used (wrong spec, outdated), the reason is shown under the checkbox and the dialog stays open. The option is disabled while the Starter Build is selected.

### New: save your current talents over a build
- Right-click a custom build → **Save current talents here** replaces its saved talents with what's on your talent screen now, including changes you haven't applied yet. It asks before overwriting.
- The build keeps its name, icon, group and tags.
- **Save current** now also picks up pending (not yet applied) talent changes.

### New: a prompt for each boss
- With boss tags, you're now prompted through the raid, not just when you enter. On reaching a new **map area**, you're offered the build for the next living boss there, and **after each kill**, the next one.
- The prompt lists that boss's build first, then at most two later bosses' builds, marked "Only if you're using a different kill order". If the next boss has no build tagged, there's no prompt.
- Re-entering an area whose boss is still alive offers its build again, every time (not twice within 10 seconds). No prompt if you already have that boss's build, never in combat, and not after a wipe.
- On by default; turn it off in the **...** menu ("Prompt for each boss"). `/lp why` shows your map area, the bosses there, and which boss is next.

### Prompt window
- The "Change talents for ...?" window now sizes itself to its contents: rows grow when their text wraps, and nothing is cut off with "..." or overlaps the Keep button. It's a little wider, with larger icons.

### Fixed
- Builds tagged to a specific dungeon (or raid) weren't offered when you entered it if your active Blizzard loadout was tagged **All dungeons** (or **All raids**). Your active loadout always matches your talents, because custom builds save into it, so the addon thought you were already set. Now, when a place has builds of its own, only those count as "already wearing it".

### Repository
- `.gitignore` now really ignores `luac.out` (the line was saved in the wrong text encoding), and keeps the old LEARNING.md / PUBLISHING.md guides out.
- New tests: the Import-dialog checkbox, "Save current talents here", the dungeon-prompt fix, and boss-by-boss prompts (a simulated raid night).

## v0.19.0

### New: your builds in the SimulationCraft export (Raidbots)
- When the SimulationCraft addon is installed, `/simc` now includes every custom build for your current spec as a `# Saved Loadout:` entry, next to your Blizzard loadouts. Raidbots then lists them as talent options, like Talent Loadout Ex did.
- Every build is included, even ones that share talents or a name with another loadout.
- The export's checksum is recalculated, so Raidbots accepts the edited profile. If the profile looks unfamiliar, it's left untouched.
- Can be turned off in the **...** menu: "Add my builds to the SimulationCraft export".
- New `/lp simc` command explains why your builds are or aren't in the export.

### Loadouts
- Clicking a Blizzard loadout row now switches loadouts exactly like Blizzard's own dropdown, and the talent window's dropdown updates to match.
- Applying a custom build still fills your currently selected Blizzard loadout, and the messages now name it (e.g. "Applying X to your Raid loadout").
- Fixed an error when clicking a Top builds row.

### Look and feel
- Icon rings: the build you're using has a gold ring, and every other build has a grey square ring, like an unlearned talent. Icon corners are masked so they no longer poke past the ring.
- The spec buttons (main window and talent tab) use the same rings: gold for your current spec, grey for the others.
- Build editor (Import / Edit) redesigned to match the main window. It has a solid background with your spec art, and Talents, Details and Choose an icon sections under gold-lined headers. The chosen icon is shown in a gold ring, and Save and Cancel sit on the bottom bar. The window no longer shows the talent tree through it.
- Icon picker: every icon has a ring (gold = chosen), section titles have header bands, and the section buttons fill the row and light up for the section you're scrolled to.
- Top builds redesigned the same way: a solid background with spec art, full-width difficulty tabs (the selected one stays lit instead of greying out), rows the same size as the main list, and the hint on the bottom bar. It can be dragged by its title bar.
- Main window: the list and its scroll bar now stop above the bottom-bar art. The Import / Save current / New group buttons fit inside the border, and their labels use Blizzard's small button font so each one fits its button.
- Fixed the **...** options button disappearing under the title bar.

### Zone-in prompts
- Dungeons: being in any dungeon is now enough to be offered its builds, whatever the difficulty. Builds tagged to the dungeon come first, then "All dungeons".
- You're only offered builds for the spec you're in. Offering builds tagged in your other specs is now an option, off by default: "Offer builds tagged in my other specs" in the **...** menu.
- The Encounter Journal's "Keystone Dungeons" page is no longer offered as a tag target (you can never be inside it, so its tags never triggered a prompt). Use "All dungeons" instead. Any existing Keystone Dungeons tags are moved to "All dungeons" automatically at login, so they now work in every dungeon.

### Encounter Journal
- Fixed raid boss icons sometimes missing.
- Journal pages that aren't real instances (world bosses, "Keystone Dungeons") are no longer listed as raids or dungeons.
- New `/lp journal` command lists this season's raids and dungeons as the game reports them.

### Top builds (work in progress)
> Top builds is still a work in progress. The data source and how builds are chosen may change in future versions, and the suggestions may not always match what top players are running right now.

- Built-in builds now come from the **top 10% of players** on parses.gg, falling back to all players where too few top players logged a fight. Rows say "top players" or "players" accordingly.
- The Archon button is replaced by a link button naming the source each build comes from. "Compare on Archon..." moved to the right-click menu.
- The source buttons only appear when more than one source has data.

### Publishing and repository
- The daily job now only commits new build data. Nothing is published to CurseForge unless a version tag is pushed (or the `AUTO_RELEASE` repository variable is turned on).
- Removed the LEARNING.md and PUBLISHING.md guides.
- New tests: SimulationCraft export, tags and zone-in prompts, the build editor opening, and top-10% labels.
