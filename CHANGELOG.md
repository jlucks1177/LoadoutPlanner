# Changelog

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
- Main window: the list and its scroll bar now stop above the bottom-bar art, and the Import / Save current / New group buttons fit inside the border.
- Fixed the **...** options button disappearing under the title bar.

### Zone-in prompts
- Dungeons: being in any dungeon is now enough to be offered its builds, whatever the difficulty. Builds tagged to the dungeon come first, then "All dungeons".
- You're only offered builds for the spec you're in. Offering builds tagged in your other specs is now an option, off by default: "Offer builds tagged in my other specs" in the **...** menu.
- The Encounter Journal's "Keystone Dungeons" page is no longer offered as a tag target (you can never be inside it, so its tags never triggered a prompt). Use "All dungeons" instead. Any existing Keystone Dungeons tags are moved to "All dungeons" automatically at login, so they now work in every dungeon.

### Encounter Journal
- Fixed raid boss icons sometimes missing.
- Journal pages that aren't real instances (world bosses, "Keystone Dungeons") are no longer listed as raids or dungeons.
- New `/lp journal` command lists this season's raids and dungeons as the game reports them.

### Top builds
- Built-in builds now come from the **top 10% of players** on parses.gg, falling back to all players where too few top players logged a fight. Rows say "top players" or "players" accordingly.
- The Archon button is replaced by a link button naming the source each build comes from. "Compare on Archon..." moved to the right-click menu.
- The source buttons only appear when more than one source has data.

### Publishing and repository
- The daily job now only commits new build data. Nothing is published to CurseForge unless a version tag is pushed (or the `AUTO_RELEASE` repository variable is turned on).
- Removed the LEARNING.md and PUBLISHING.md guides.
- New tests: SimulationCraft export, tags and zone-in prompts, the build editor opening, and top-10% labels.
