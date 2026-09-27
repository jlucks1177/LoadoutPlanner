# LoadoutPlanner

A World of Warcraft addon (Retail, Midnight 12.1) for managing talent builds. It adds a panel to the talent window where you can keep an unlimited library of builds organized into groups, switch specs and builds with one click, compare any build against your current talents, browse the most-played builds for your spec per dungeon and raid boss (with Archon links), and tag builds to dungeons, raids, and bosses (optionally per difficulty) from anywhere, so the right one is offered when you zone in.

**Version:** 0.18.1 · **Author:** Joe · **Game version:** 12.1 (`## Interface: 120100`)

For a guided tour of the source code, written as a tutorial, see **LEARNING.md**. This README covers what the addon does and how it works.

---

## Contents

1. [Installation](#1-installation)
2. [Quick start](#2-quick-start)
3. [The LoadoutPlanner window](#3-the-loadoutplanner-window)
4. [The loadout list](#4-the-loadout-list)
5. [Custom builds](#5-custom-builds)
6. [Applying builds](#6-applying-builds)
7. [Comparing builds](#7-comparing-builds)
8. [Tags, difficulties, and zone-in prompts](#8-tags-difficulties-and-zone-in-prompts)
9. [Switching specs](#9-switching-specs)
10. [Background art transparency](#10-background-art-transparency)
11. [Importing from Talent Loadout Ex](#11-importing-from-talent-loadout-ex)
12. [Top builds and Archon](#12-top-builds-and-archon)
13. [Slash commands](#13-slash-commands)
14. [How it works](#14-how-it-works)
15. [Saved data](#15-saved-data)
16. [Limitations](#16-limitations)
17. [Troubleshooting](#17-troubleshooting)
18. [Credits](#18-credits)

---

## 1. Installation

**Easiest:** install **LoadoutPlanner** from the CurseForge app, Wago, or WowUp, and let it keep the addon updated. Each update carries fresh top builds (see [section 12](#12-top-builds-and-archon)).

**Manually:** download the latest zip from the GitHub Releases page, then:

1. Copy the `LoadoutPlanner` folder into `World of Warcraft/_retail_/Interface/AddOns/`. The folder name must match `LoadoutPlanner.toc`.
2. Restart the game or type `/reload`.
3. Optional, but recommended while testing: install **BugGrabber** and **BugSack** so any errors are captured.

If the addon shows as "out of date", confirm the game's interface number with `/dump select(4, GetBuildInfo())` and update the `## Interface:` line in `LoadoutPlanner.toc` to match.

**Conflicts:** other addons that add a loadout panel, spec buttons, or a background slider to the talent window (such as Talent Loadout Ex) will draw in the same places. Disable them, or use LoadoutPlanner's import to move your builds over first (see [section 11](#11-importing-from-talent-loadout-ex)).

---

## 2. Quick start

1. Open your talents (default key **N**). The LoadoutPlanner window appears beside the talent window.
2. Click **Save current** to save your current talents as a custom build. Give it a name and a group (for example "Raid"), pick an icon, and click **Save**.
3. Build a second set of talents and save that too.
4. **Click** a build to put its talents on the talent screen, then press Blizzard's **Apply Changes**, or just **double-click** the build to apply it straight away. Either way, it's saved into the Blizzard loadout you have selected. Hover over a build to see how it differs from your current talents.
5. Right-click a build → **Tag...** and click a difficulty next to any raid, boss, or dungeon. You don't need to be there. The build now shows that icon, and it's highlighted (and offered) when you're there on that difficulty.

---

## 3. The LoadoutPlanner window

The window opens and closes with the talent window. It's built from the same parts as Blizzard's talent window: the metal-bordered panel, your spec's talent painting (darkened) behind the list, the thin modern scroll bar, and the PvP talent list's gold hover glow and round icon rings.

### Placement

The window always tries to sit **beside** the talent window, on its right.

- **Making room:** if the talent window is too wide for both to fit on screen (common at larger UI scales, since the talent window is 1,618 units wide), LoadoutPlanner slides the talent window left and, if needed, shrinks it just enough to fit both. It's centered and kept at the same height on screen.
- **Inside fallback:** if fitting both would mean shrinking the talent window below 70%, the window is placed *inside* the talent window's right edge instead, clear of its title bar and bottom bar.
- **Tucking away:** the **X** doesn't close the window. It tucks it into a small **LP** tab on the talent window's right edge. Click the tab to bring it back. While tucked away, the talent window returns to Blizzard's normal size and position.
- It re-checks placement whenever the talent window opens or resizes (including Blizzard's own minimize button), when another Blizzard panel opens next to it, and when your UI scale or resolution changes.
- It never moves or resizes the talent window during combat. If a change is needed mid-fight, it waits until combat ends.

### Header

| Element | What it does |
|---|---|
| **Spec buttons** | One button per specialization. The active spec is bright; click another to switch ([section 9](#9-switching-specs)). |
| **Top builds** | Opens the Top builds panel for your spec: most-played builds per dungeon and boss, plus Archon links ([section 12](#12-top-builds-and-archon)). |
| **Import** | Opens the build editor with an empty import code field. |
| **Save current** | Opens the build editor with your current talents' import code filled in. |
| **New group** | Creates an empty group. |
| **"Here:" line** | Shows the dungeon or raid you're in, or "Not in a dungeon or raid". |
| **...** | Options menu (see below). |

### Options menu (**...**)

- **Move/shrink talent window to make room**: on by default. Turn it off to leave the talent window exactly as Blizzard places it. The window then goes inside when it doesn't fit beside.
- **Spec buttons on talent tab too**: off by default. Adds a second row of spec buttons to the talent tab's bottom bar.
- **Import from Talent Loadout Ex**: see [section 11](#11-importing-from-talent-loadout-ex).

### Footer

**Talent background art**: a slider that fades the talent window's background painting (see [section 10](#10-background-art-transparency)).

---

## 4. The loadout list

The list has two kinds of entries, shown in collapsible sections:

- **Blizzard loadouts:** the loadouts saved in Blizzard's own talent system for your current spec. These are subject to Blizzard's loadout limit.
- **Your groups:** your custom builds, organized into groups you name. These have no limit. Only builds for your **current spec** are listed, but every group is shown so you can organize before filling it. The number beside each group counts that spec's builds.

### Mouse actions

| Action | Result |
|---|---|
| **Left-click** a custom build | Puts its talents on the talent screen as pending changes (see [section 6](#6-applying-builds)). A single click waits 0.3 seconds to make sure it isn't the start of a double-click. |
| **Double-click** a custom build | Puts its talents on the talent screen **and applies them**. |
| **Left-click** a Blizzard loadout | Loads it, exactly like Blizzard's dropdown. |
| **Right-click** a row | Options menu for that entry (see below). |
| **Hover** a row | Shows the comparison tooltip ([section 7](#7-comparing-builds)). |
| **Left-click** a group header | Collapses or expands the group. |
| **Right-click** a group header | Rename, move up/down, add a build here, or delete the group. |

### What a row shows

- **Icon**, chosen in this order: the icon you picked for the build → the icon of the dungeon, raid, or boss it's tagged to → your spec's icon.
- **Name**, and underneath it the places it's tagged to, with the difficulty in brackets when a tag is difficulty-specific, for example "Nymrissa (M), Ara-Kara, City of Echoes (M+)". Untagged entries say "untagged".
- **Icon ring**: green normally, **gold** when that entry's talents are exactly your current talents (the same rule as the check mark).
- **Check mark** when that entry's talents are **exactly your current talents**. Every matching entry is checked, not just the one you clicked, so duplicates (for example the same build saved under two bosses) all show a check mark together. The comparison ignores free, automatically granted talents and updates live as you change talents.
- **Green strip** on the left edge when the entry is tagged to the dungeon or raid you're currently in, or to one of its bosses, **at your current difficulty** (or for any difficulty).

### Right-click menu

For **custom builds**: Edit, Copy import code, Move up/down, tag options, and Delete (asks for confirmation).

For **Blizzard loadouts**: Save as custom build (copies it into your library), and tag options.

Tag options (both kinds): **Tag...**, which opens the tag panel and works from anywhere (see [section 8](#8-tags-difficulties-and-zone-in-prompts)), plus **Remove tag ▸** for any existing tags.

---

## 5. Custom builds

Custom builds are import codes stored by LoadoutPlanner, each with a name, a group, and an icon. They're saved **account-wide, per class**, so every druid alt sees your druid builds.

### The build editor

Opened by **Import**, **Save current**, **Edit...**, **Add build here...**, or **Save as custom build...**.

- **Import code:** paste any talent import code (from Blizzard's export, Wowhead, Raidbots, Archon, and so on). It's checked as you type:
  - **"OK: *Spec* build"**: the code is valid for your class.
  - **"That doesn't look like a talent import code."**: it couldn't be read.
  - **"This code is from an older game version. Re-export it."**: Blizzard changed the code format since it was made.
  - **"This code is for a different class."**
- **Build name:** required.
- **Group:** type any name. A new name creates a new group, and the **v** button lists existing groups. Leave it empty to use "Ungrouped".
- **Selected icon** (top right): shows the build's icon. **Right-click** it to go back to the automatic spec icon.
- **Choose an icon:** the embedded icon picker (below).
- **Save** / **Cancel**. Escape closes the editor, and Tab moves between fields.

### The icon picker

Icons are listed with the most useful first:

1. **Current raid(s):** the raid's own icon (marked **R**), then a square icon for each boss, numbered in kill order.
2. **Dungeons:** this season's dungeons, labeled with short initials (such as **AKCE** for Ara-Kara, City of Echoes).
3. **Specializations:** your class's specs.
4. **Talents:** every talent in your class tree, alphabetically.
5. **All icons:** Blizzard's full icon list (the one the macro window uses).

**Jump buttons** above the grid scroll straight to each section. Scroll with the mouse wheel or the scroll bar. Hover an icon to see its name, and click it to select it (it's highlighted, and the preview updates).

**Search** matches boss, dungeon, spec, and talent names. Typing a **number** looks up that **spell ID or item ID**, for example `8921` for Moonfire. The "All icons" list can't be searched, because Blizzard's icon list has no names attached to its icons.

### Groups

- Create one with **New group**, or by typing a new name in the editor.
- Right-click a group header to **Rename**, **Move up/down**, **Add build here**, or **Delete** it. Deleting a group deletes its builds, after a confirmation.
- Group names can be anything: raid names, "M+", "Delves", "PvP", "Testing", and so on.
- Collapsed and expanded state is remembered.

---

## 6. Applying builds

**Blizzard loadouts** load exactly as if you picked them from Blizzard's dropdown.

**Custom builds** change the talents of **your currently selected Blizzard loadout**. No extra loadouts are ever created. It works in two steps, just like clicking talents yourself on the talent screen:

| You do | What happens |
|---|---|
| **Single-click** the build | Its talents appear on the talent screen as **pending changes**, highlighted and with **Apply Changes** lit, as if you'd clicked them yourself. Nothing is permanent yet. Review them, tweak them, or press Escape or Undo to discard them. |
| Press Blizzard's **Apply Changes** | The changes are applied ("Changing Talents" cast) and saved into your selected loadout. **This is the recommended way.** |
| **Double-click** the build | The changes are staged **and applied** in one go, into your selected loadout. |

**Why Apply Changes is recommended:** when addon code (rather than Blizzard's button) applies talents, WoW can flag the talent interface as "tainted", which in some cases breaks action-bar keybinds until you `/reload` (a known WoW issue, WoWUIBugs #447). Staging from the addon and applying with Blizzard's own button avoids that. Double-click is there for convenience. If you ever see blocked-action errors afterwards, switch to single-click + Apply Changes.

**Under the hood:**

1. **Nothing to do?** If your talents already match the build exactly, nothing is touched.
2. **Fast path:** only the talents that differ are changed. Talents the build doesn't want are refunded, working bottom-up so talents that depend on others go first, and missing ones are learned, working top-down so prerequisites come first. Every talent change makes Blizzard's talent window redraw, so changing 5 talents instead of re-learning 120 is the difference between instant and a visible freeze.
3. **Full path:** used if the build switches hero trees, or if the fast path doesn't end up exactly right. The tree is cleared (`C_Traits.ResetTree`) and everything is learned, in repeated passes until nothing more can be learned.
4. **Verify:** the result is compared with the build using its talent fingerprint (see [section 14](#14-how-it-works)). If it doesn't match (usually an outdated code), **everything is rolled back** to your committed talents, and chat says "*N* talents wouldn't learn".
5. **Apply** (double-click only): `C_Traits.CommitConfig` commits your talents ("Changing Talents" cast). Talent Loadout Ex uses the same call, because it doesn't run any of Blizzard's talent-window code and so avoids spreading taint. When the game confirms, the result is saved into your selected loadout with `C_ClassTalents.SaveConfig`.

A double-click does all of this **once**: the first click's staging is cancelled when the second click arrives.

**Tip:** if you want a build kept separately from your other loadouts, create a new loadout in Blizzard's dropdown first, select it, and then apply the build.

**Requirements:** out of combat, the build must be for your current spec (switch spec first), a regular loadout must be selected (Blizzard's Starter Build can't be edited), and the usual game rules apply. For example, talents can't be changed once a Mythic+ key has started. Any refusal from the game is shown in chat.

`/lp load <name>` and the zone-in prompt apply builds directly, like a double-click.

---

## 7. Comparing builds

Hovering any row opens a tooltip beside the list showing a **mini talent tree**: the class tree on the left, the hero tree in the middle, and the spec tree on the right. Each talent is a dot:

| Color | Meaning |
|---|---|
| Gold | In both your current talents and this build |
| Green | This build **adds** it |
| Red | This build **removes** it |
| Orange | In both, but a **different rank or choice** |
| Gray | In neither |

Lines connect talents as in the real tree, and are gold where the build takes both ends. Above the tree is a summary (**+added −removed ~changed**, or "Matches your current talents"). Below it, the changed talents are listed **by name**, along with a **Hero tree: A -> B** line if the hero tree differs.

For custom builds of another spec, the tooltip explains that the build is for another spec instead.

---

## 8. Tags, difficulties, and zone-in prompts

A **tag** links a loadout or build to a **dungeon or raid** (the whole instance) or to a **specific boss**, either for **any difficulty** or for **one difficulty**. Tags are per character and per spec. Difficulty tags are how you categorize builds by difficulty: for example, one build for Heroic and one for Mythic on the same boss, or a Mythic+ build for a dungeon.

### Tagging from anywhere: the tag panel

Right-click a row → **Tag...** opens the tag panel beside the LoadoutPlanner window. It lists this season's instances from the Encounter Journal, so you don't need to be anywhere in particular:

- **All instances:** an **All dungeons** row and an **All raids** row. These tags cover *every* dungeon or raid, so **All dungeons → M** means "offer this build whenever I enter any dungeon on Mythic".
- **Each raid:** a *Whole raid* row, then every boss, numbered in kill order.
- **Dungeons:** one row per dungeon.
- **Here:** if you're inside an older instance that isn't part of the current season, it's listed first.

Each row has a button per difficulty: **Any**, then **LFR / N / H / M** for raids or **N / H / M / M+** for dungeons.

| Button color | Meaning | Clicking it |
|---|---|---|
| **Green** | Tagged to *this* build | Removes the tag |
| **Gold** | Tagged to *another* build (hover to see which) | Moves the tag to this build |
| **Gray** | Not tagged | Tags this build |

**M+** on a dungeon means "offer this whenever I walk into this dungeon, on any difficulty, before a key starts". Each target and difficulty holds one entry. The panel closes with Escape or with the talent window. **Remove tag ▸** in the right-click menu is still there for quick removals. `/lp tag` and `/lp tagboss` ([section 13](#13-slash-commands)) tag the place you're in, for any difficulty.

### How difficulty is matched

When you're in an instance, a tag for your **exact difficulty** wins. Otherwise an **any difficulty** tag applies. So you can tag a raid "any difficulty" with your general build and add a "Mythic" tag for a specific boss or for the whole raid.

### Effects

- The row shows its tags under its title, with the difficulty in brackets, and the dungeon, raid, or boss icon (unless you picked your own).
- While you're in that instance **on a matching difficulty**, the row gets a **green strip**.
- **Zone-in prompt** (see below).

### The zone-in prompt

When you enter a dungeon or raid, or its difficulty changes while you're inside (for example when the raid leader switches to Mythic), LoadoutPlanner collects every build tagged for it and shows a small window: **"Change talents for *place (difficulty)*?"**, with a line saying **what you're on now** (your matching saved build, or your selected Blizzard loadout). Each tagged build is a row marked **Switch**: click it to apply that build, or hover to compare it with your talents. The bottom button, **Keep *current loadout***, dismisses the prompt and keeps your talents for the rest of the visit.

Builds are offered in this order, without duplicates:

1. The instance, tagged for **this exact difficulty**.
2. **In any dungeon, its Mythic+ tag**, whatever the difficulty (Normal, Heroic, or Mythic). A key can only be started from inside the dungeon, and talents lock once it starts, so walking in is the only moment a Mythic+ build can be offered.
3. The instance, tagged for **any difficulty**.
4. **All dungeons** / **All raids** tags, with the same rules: this difficulty, then (for dungeons) Mythic+, then any difficulty. A tag on the specific place always comes before these general ones.
5. Each **boss** of the instance (this difficulty first, then any difficulty), skipping bosses you've already killed on this difficulty.

**Tagged in another spec?** Tags belong to the spec you made them in. If the place has nothing tagged for your current spec but **another spec** does, you get a different prompt instead: **"*Place* is tagged for another spec"**, with a **Switch to *Spec*** button for each spec that has builds here (hover it to see which builds). Switching spec, whether from that button or any other way, re-runs the check, and the normal build prompt for the new spec follows.

**Finding tags reliably:** a tag matches the instance if it was made under the instance's ID as the game reports it, **or** under the Encounter Journal's ID for it (they can differ), **or** if its saved place name matches the instance's name.

The prompt **isn't shown** if you already have one of those builds' exact talents (chat tells you which one), if you're in combat (it asks once combat ends), or once a Mythic+ key is running. It asks once per instance and difficulty per visit. After a loading screen it waits for your talent data to load (checking every 2 seconds, up to 6 times) rather than guessing.

**Difficulties are recognized by what they are, not only by number.** Known difficulty numbers are used directly. Anything else is classified from the game's own description of it (`GetDifficultyInfo`: raid finder, heroic, mythic, or challenge mode), so renumbered or special versions of a difficulty still match your tags.

**If a prompt doesn't appear,** type `/lp why` inside the instance. It prints what LoadoutPlanner sees: the instance IDs it checks, the game's difficulty ID and how LoadoutPlanner classified it, every tag in your current spec with its place name, which other specs have builds tagged here, whether you're in combat or a key is running, whether it already asked, and each tagged build with whether it matches your talents. `/lp prompt` shows the prompt again, even if it already asked.

### Robustness

Tags to Blizzard loadouts survive renames and deleting/recreating the loadout (they re-link by ID, then by name). Tags to custom builds follow the build through renames and group moves. Tags made before difficulties existed count as "any difficulty". A tag whose target was deleted shows as missing in `/lp tags`.

---

## 9. Switching specs

The spec buttons in the window header (and optionally on the talent tab) switch specialization with one click. They're dimmed for inactive specs and bright for the current one, with a tooltip showing the spec name and role. The list, check marks, and comparisons update for the new spec automatically. Spec changes aren't possible in combat.

---

## 10. Background art transparency

The **Talent background art** slider (0-100%, in steps of 5; the mouse wheel works too) fades the talent window's background painting and its black backing, so you can see the game world behind the tree. The setting is saved per character and reapplied whenever the talent window opens or you change spec.

---

## 11. Importing from Talent Loadout Ex

LoadoutPlanner can copy all your groups and loadouts from the **Talent Loadout Ex** (TLE) addon:

1. **Enable** Talent Loadout Ex and `/reload`. WoW only loads an addon's saved data while that addon is enabled.
2. Click **...** → **Import from Talent Loadout Ex**, or type `/lp importtle`.
3. Check the chat summary, then disable TLE if you like. Everything now lives in LoadoutPlanner's own storage.

**What's imported:** every class's loadouts (so alts get theirs too), grouped as they were in TLE. Groups with the same name in different specs are merged into one group. Loadouts that weren't in any TLE group go to "Ungrouped". The icons you chose come along, including hero-talent emblems. TLE's default question-mark icon becomes LoadoutPlanner's automatic spec icon.

**What's skipped:** loadouts already in LoadoutPlanner with the same name and code (so importing twice is safe), TLE's pre-Dragonflight "legacy" entries, and anything whose spec can't be determined. PvP talent selections aren't imported, since LoadoutPlanner doesn't manage PvP talents.

---

## 12. Top builds and Archon

Click **Top builds** in the window header (or type `/lp top`) to open a panel beside the window, listing the best-known build for **your current spec** on each of this season's dungeons and raid bosses.

### Where the builds come from

**Nothing to set up:** LoadoutPlanner comes with the most-played builds **built in**. A daily job fetches them and publishes a new version of the addon whenever they change, so updating LoadoutPlanner through your addon manager keeps them fresh. The header shows when they were last updated, and turns orange after 3 days.

The panel has two sources, switched with the **Raider.IO** / **parses.gg** buttons at its top right (your choice is remembered). Each can come from the built-in data, or from something you install or run yourself; LoadoutPlanner uses whichever is newer:

**parses.gg** is built in. **Raider.IO** is built in once the maintainer has enabled it. Advanced users can also use:

**Raider.IO**: the **LoadoutPlannerData** addon, written by LoadoutPlanner's companion program **LoadoutPlannerSync** from the official Raider.IO API. It covers:

- **Mythic+:** the most-played build per dungeon (and across all dungeons) among the season's top keys.
- **Raid:** the most-played build per boss on Mythic and Heroic among the top guilds' kills.
- **Popularity:** each row says how many players it's based on and what share used that build ("72% of 40 players"), and the right-click menu has the **runner-up builds**.

To get it: install Node.js, put your Raider.IO API key and AddOns path in LoadoutPlannerSync's `config.json`, and run `npm run sync` (a full sync takes about 7 minutes). Then `/reload`. Its README has the full steps, including running it daily. The header line shows when you last synced and turns orange after 3 days.

**parses.gg**: besides the built-in copy, any addon providing the shared `PeaversTalentsData` interface. The built-in copy is used unless it's more than 3 days old and one of these is installed:

- **[ArchonTalentsData](https://github.com/EliteTC/ArchonTalentsData)**: updated daily with the most-played builds from **parses.gg** logs (real logged kills and keys), including LFR and Normal. It has its own updater script.
- **PeaversTalentsData**: the original addon with the same interface. Its old data source (wowcompare.io) has shut down, so ArchonTalentsData is the one to use. Don't install both, since they use the same global name.

You can install either source, or both. Without any, the panel still lists every dungeon and boss with its **Archon** button. It just has no "Top build" to click.

**Why not read the Raider.IO addon directly?** It does have a Talent Builds window, but its build data sits in the addon's private storage, which other addons can't see, and its public interface only covers player profiles. The official web API is the supported route, which is why LoadoutPlannerSync exists.

### Archon

**archon.gg can't be read by addons or tools.** Since August 27, 2026 it shows a "Human Verification" page to automated requests, and its operator has asked addon authors not to use its data. That's why the data addons switched to parses.gg, and why LoadoutPlanner never fetches from Archon.

What LoadoutPlanner does instead: every row has an **Archon** button that opens a small dialog with

1. the exact **archon.gg link** for your spec and that dungeon or boss (and difficulty), to copy with Ctrl+C and open in your browser, and
2. a **paste box**: copy the talent string from Archon's page and paste it in. The code is checked as you paste.

Then click **Save and tag** to save it to your library (group **Archon**, named like "Murder Row (Mythic+, Archon)") **and** tag it to that dungeon or boss at that difficulty, in one step, or **Save** to just save it. Mythic+ links use Archon's keystone-level-10, this-week view. Archon has no Raid Finder data, so LFR links go to Normal (the dialog says so).

### Using the panel

- **Tabs:** **M+ / LFR / Normal / Heroic / Mythic.** When you're in an instance, the panel opens on the matching tab.
- **Rows:** "All dungeons" or "All bosses" first, then each dungeon, or each boss in kill order. Each row shows the place's icon and a status: **Top build** (with "*N*% of *M* players" for Raider.IO data), **Matches your talents** (green) if your current talents are exactly that build, **No logged build yet** (common on Mythic early in a tier), and **saved as *name*** if that exact build is already in your library.
- **Mouse:** click to put the build on the talent screen, double-click to apply it (the same rules as your own builds, [section 6](#6-applying-builds)), and hover to compare it with your talents ([section 7](#7-comparing-builds)).
- **Right-click:**
  - **Save to library:** adds it to the group **Top builds: *difficulty***.
  - **Save and tag to *place* (*difficulty*):** saves it and tags it in one step, so the zone-in prompt will offer it. "All dungeons" and "All bosses" rows tag **All dungeons** / **All raids** at that difficulty.
  - **Copy talent string.**
  - **Other popular builds** (Raider.IO): the runners-up with their share, each of which you can put on the talent screen, apply, save, or save and tag.
  - **Get from Archon...:** the same dialog as the button.

Saving never duplicates: if your library already has a build with exactly that talent string, it's reused, and only the tag is added.

Top builds are matched to the Encounter Journal **by name**. If your game language differs from the data's English names, the builds still appear at the bottom of the list and work, but they can't be tagged from here.

---

## 13. Slash commands

`/lp` and `/loadoutplanner` are interchangeable.

| Command | Description |
|---|---|
| `/lp` | Open or tuck away the window (the talent window must be open). |
| `/lp help` | List the commands. |
| `/lp list` | List your Blizzard loadouts for this spec. |
| `/lp load <name>` | Load a Blizzard loadout or apply a custom build by name (case-insensitive). |
| `/lp tag <name>` | Tag a loadout or build to the current dungeon or raid (any difficulty). |
| `/lp untag` | Remove the current instance's tag. |
| `/lp bosses` | Number the bosses of the current instance. |
| `/lp tagboss <#> <name>` | Tag a loadout or build to boss number `#` (any difficulty). |
| `/lp boss <#>` | Load whatever is tagged to boss number `#` for your current difficulty. |
| `/lp why` | Explain what the zone-in prompt sees in the current instance (for troubleshooting). |
| `/lp prompt` | Show the zone-in prompt again for the current instance. |
| `/lp tags` | Show every tag for your current spec. |
| `/lp importtle` | Import from Talent Loadout Ex. |
| `/lp top` | Open Top builds for your current spec. |
| `/lp reset` | Reopen the window and restore default options. |

---

## 14. How it works

### Tests

`lua tools/test/run.lua` (from the repository root, any Lua 5.1 or newer) loads every file against a fake WoW API and checks the main windows and the Top builds panel. GitHub runs it on every push (`ci.yml`) and before every release, so a broken build never reaches players. See `tools/test/` and LEARNING.md Part 19.

### File map

Files load in this order (see `LoadoutPlanner.toc`), and each file only uses things defined above it at load time.

| File | Responsibility |
|---|---|
| `Style.lua` | The shared look: Blizzard's panel template, the talent window's spec art, the modern scroll bar, row highlights, icon rings and header styling. Each piece falls back to plain textures if a future patch renames it. |
| `Core.lua` | Shared namespace, chat printing, the event dispatcher (`ns.On` / `ns.Off`), the internal refresh signal (`ns.OnRefresh` / `ns.Notify`), and slash-command routing. |
| `Loadouts.lua` | Reading and loading Blizzard loadouts, combat queueing, and the **item** abstraction (`ns.LoadItem`, `ns.IsItemActive`, `ns.FindItemByName`). |
| `Data.lua` | Per-character saved data, tags (with optional difficulty), and tag references that repair themselves. |
| `Builds.lua` | Account-wide build library: groups, builds, ordering, IDs, and reading import code headers. |
| `ImportTLE.lua` | Converting Talent Loadout Ex's saved data. |
| `Import.lua` | Parsing import codes (via Blizzard's own parser), staging builds onto the talent screen, and applying them. |
| `Journal.lua` | Encounter Journal data (this season's raids, bosses, and dungeons, with the map and encounter IDs used by tags), square boss icons, difficulty names, and icon drawing. |
| `Context.lua` | Detecting the current instance, its bosses, and its difficulty, deciding which tagged builds to offer (`ns.GetCandidates`), when to prompt, `/lp why`, and tag commands. |
| `Prompt.lua` | The zone-in prompt window (build choices, or spec switching when the place is tagged in another spec). |
| `Diff.lua` | Build comparison (the tooltip), talent **fingerprints** (the check marks), and drawing the mini tree. |
| `Background.lua` | Background art transparency and a reusable percent slider. |
| `SpecBar.lua` | Reusable spec-button rows and spec switching. |
| `IconPicker.lua` | The embedded icon grid: data sources, search, and virtual scrolling. |
| `Editor.lua` | The build editor window. |
| `Window.lua` | The main window: frame, header, placement, making room, the collapse tab, and options. |
| `TagPanel.lua` | The tag panel: this season's raids, bosses, and dungeons, with a button per difficulty. |
| `Archon.lua` | archon.gg links for each spec, dungeon, and boss, and the link-and-paste dialog. |
| `Data/Builtin.lua` | The built-in builds (global `LoadoutPlannerBuiltin`), regenerated daily by the GitHub Action. |
| `TopBuilds.lua` | The Top builds panel: reads both sources (built in, your own LoadoutPlannerData sync, or a PeaversTalentsData data addon) into one shape, matches builds to this season's journal, save-and-tag, runner-up builds. |
| `UI.lua` | The list inside the window: rows, headers, right-click menus, and popups. |

### Items: one interface for two kinds of entries

Every row, tag, prompt, and comparison works with an **item**: a table with a `key`, a `name`, and either a `configID` (a Blizzard loadout) or a `build` (a custom build). Keys are the config ID for Blizzard loadouts and `"b:<build id>"` for builds. Only a few functions (`LoadItem`, `IsItemActive`, `ComputeDiff`, `GetFingerprint`) check which kind they have. Everything else just passes items around.

### Reading import codes

A talent import code is base64-encoded binary. Its header is 8 bits of format version, 16 bits of spec ID, and a 128-bit hash of the talent tree. After the header comes one small record per node in the tree.

- To **validate** a code as you type (`ns.ReadCodeHeader`), LoadoutPlanner reads only the header. That's enough to check the format version and which class and spec the code is for.
- To **apply or compare** a code (`ns.GetBuildEntries`), it calls Blizzard's own parser, `ClassTalentImportExportMixin`, which is the code behind Blizzard's Import button. The result is a list of `{ nodeID, ranksPurchased, ranksGranted, selectionEntryID }` entries. Codes made for an older version of the talent tree are refused, just as Blizzard's importer refuses them. Parsed results are cached per code and cleared when you change spec.

### Applying a build

Staging works on the *active config* (your current talents plus pending changes), and Blizzard's talent window picks up the changes through the same events it uses when you click talents yourself. The steps are in [section 6](#6-applying-builds). The fast path compares each node's purchased ranks and chosen option with the build, then calls `RefundAllRanks` / `RefundRank` for unwanted talents and `PurchaseRank` / `SetSelection` for missing ones. Nodes are ordered by their vertical position in the tree. Success is verified with fingerprints, and `C_Traits.RollbackConfig` undoes everything on failure.

**Click handling:** WoW's built-in double-click event only fires after the first click has already been handled, so a slow first click (staging) could stop the second click from counting as a double-click at all. LoadoutPlanner detects double-clicks itself instead. A single click starts a 0.3-second timer before staging, and a second click within that time cancels the timer and applies instead.

### Tags

Tags live in `LoadoutPlannerDB.specs[specID].categories` (keyed `"party"` or `"raid"`, the instance types `GetInstanceInfo()` reports), `.instances` (keyed by the instance's **map ID**, the same number `GetInstanceInfo()` reports inside it) and `.bosses` (keyed by the journal **encounter ID**). A tag for one difficulty uses the key `"<id>@<difficultyID>"`. A plain `<id>` means any difficulty, which is also how pre-0.10 tags keep working unchanged. Lookups try the exact difficulty first, then any difficulty. The menus get map IDs and encounter IDs from the Encounter Journal (the 11th value of `EJ_GetInstanceByIndex` is the map ID, as confirmed in Blizzard's own journal code), which is what makes tagging from anywhere possible.

### Comparing (the tooltip)

`Diff.lua` asks the same question of both your current talents and the target: "for this node, what rank, and which choice?" A **reader** answers it for each kind of target: a saved Blizzard loadout is asked directly through the game, and a custom build is looked up in its parsed entries. Each node is classified as same, added, removed, changed, or none. Choices are only compared on actual choice nodes, because other node types can report different entry IDs for the same talent.

To draw the mini tree, node positions from the game are scaled into a small map. The class and spec trees are split at the widest horizontal gap between nodes, and the hero tree goes between them. Lines are drawn first and dots on top, and dots are made round with a mask texture.

### Matching (the check marks)

Each build gets a **fingerprint**: a text summary of its *purchased* talents, like `82101:1:0,82102:2:0,82150:1:103452` (node, ranks, and the chosen option on choice nodes). Two builds with the same fingerprint have identical talents, so matching becomes a single string comparison.

- Free, automatically granted talents and the hidden hero-tree choice node are left out, because import codes and saved loadouts record them differently and would never match. The hero tree still counts through its purchased talents.
- Fingerprints are cached: custom builds until you change spec, and Blizzard loadouts and your current talents until your talents change.
- Talent changes arrive as bursts of events (applying a build fires one per talent), so the list refreshes **once**, 0.2 seconds after the burst, rather than hundreds of times.

### Placement and making room

- Whether the window fits beside the talent window is measured in real screen pixels, since each frame's position is in its own scale. Every position is multiplied by that frame's effective scale before comparing.
- To make room, the talent window's scale is set so the talent window, the gap, and our window together equal the screen width minus a small margin (never above Blizzard's own scale). The pair is then centered horizontally, and the talent window keeps its distance from the top of the screen.
- Blizzard's original scale and anchor are remembered, so the talent window can always be restored exactly. The anchor LoadoutPlanner sets is remembered too, so it can tell when Blizzard has re-positioned the window itself.
- Placement is re-run after Blizzard re-lays out its panels (via a hook on `UpdateUIPanelPositions`), when the talent window resizes, and when UI scale or resolution changes. A guard flag stops placement from triggering itself in a loop.

### Staying safe with Blizzard's UI ("taint")

WoW marks any value written by addon code as *tainted*. If protected Blizzard code later reads a tainted value in combat, actions get blocked. LoadoutPlanner follows these rules to avoid that:

- **It never calls Blizzard's window-management functions or changes their settings.** It only uses `SetScale`, `SetPoint`, `SetAlpha`, and `SetParent` on frames.
- **It adds to Blizzard's scripts instead of replacing them,** using `HookScript` and `hooksecurefunc`.
- **It never moves or resizes the talent window in combat.** That window contains protected spellbook buttons.
- **It calls Blizzard's import parser only for its read-only helper methods,** never methods that change the talent window's state.

### Icon sources

| Section | Where the icons come from |
|---|---|
| Raids and dungeons (icons and tag menus) | The Encounter Journal's last tier, which during a season is "Current Season": exactly this season's raids and Mythic+ dungeons. The journal's selected tier is restored afterwards. |
| Boss icons | Square artwork from raid achievements. Among achievements in "Dungeons & Raids" whose names contain the boss's name, the one with the fewest extra characters is chosen (usually "Mythic: *Boss*"). This works in any game language with no hard-coded list. If nothing matches, the journal's round portrait is used instead. |
| Talents | Every node in your class tree: entry → definition → spell icon. |
| All icons | `GetLooseMacroIcons` / `GetMacroIcons`. |

The grid is **virtualized**: only the 8 visible rows of 11 buttons exist, and scrolling changes what they display. Thousands of icons cost the same as a hundred.

### Refreshing the UI

Anything that changes data calls `ns.Notify()`, and every UI piece that registered with `ns.OnRefresh` redraws itself from scratch from current game and saved state. The UI never keeps its own copy of the data, so it can't drift out of sync. Hidden UI skips redrawing.

---

## 15. Saved data

| Variable | Scope | Contents |
|---|---|---|
| `LoadoutPlannerDB` | Per character | Tags per spec (places, bosses, and all-dungeon/all-raid categories, with optional difficulty), background art opacity, window options, and collapsed states. |
| `LoadoutPlannerBuilds` | Account-wide | Your build library, per class: ordered groups, each holding ordered builds (`id`, `name`, `code`, `icon`, `specID`). |

These live in `WTF/Account/<account>/SavedVariables/LoadoutPlanner.lua` and `WTF/Account/<account>/<realm>/<character>/SavedVariables/LoadoutPlanner.lua`. Back up the account-wide file to keep your build library safe.

---

## 16. Limitations

- **Builds are applied into your selected Blizzard loadout,** overwriting its talents. Create and select a separate loadout first if you want to keep the old one.
- **Applying from the addon (double-click) can occasionally taint the talent UI** (see [section 6](#6-applying-builds)). Single-click + Apply Changes avoids it.
- **PvP talents** aren't managed.
- **Outdated codes** can't be applied after a talent tree change, the same as in Blizzard's own importer. Re-export them from their source.
- **"All icons" can't be searched by name,** because the game provides no names for them.
- **Boss icons are matched heuristically.** A boss with an unusual name could get the wrong achievement's icon, or fall back to its portrait.
- **Prompts happen when you enter (or the difficulty changes), not per pull.** Midnight restricts live encounter information, so the prompt offers your boss builds when you arrive, skipping bosses you've already killed. Between bosses, pick the next one's build from the list (it has a green strip) or with `/lp boss <#>`.
- **Top builds need a data addon** (LoadoutPlannerData from LoadoutPlannerSync, or ArchonTalentsData), and are only as fresh as the last sync or update. Mythic raid data fills in as the tier progresses. Raider.IO raid data comes from each top guild's *first* kill of a boss.
- **Archon can't be read automatically** ([section 12](#12-top-builds-and-archon)). Archon builds come in by copy and paste, and the link slugs for unusual boss names are kept in `Archon.lua`, so they need updating each season.
- **The tag panel lists the current season's raids and dungeons** (from the Encounter Journal). Older instances can be tagged from inside them, under **Here:**.
- **Some parts couldn't be verified in game while writing** and are marked `VERIFY` in the code: `UIPanelScrollFrameTemplate`, the achievement category number (168), the macro icon functions, and the talent frame's internal names.

---

## 17. Troubleshooting

| Symptom | What to check |
|---|---|
| The window never appears | Hover the talent window with `/fstack` and check that its name is `PlayerSpellsFrame`. Try `/lp reset`. |
| The window overlaps the talent tree | It's in inside mode because the talent window would have to shrink below 70%. Lower your UI scale, or use the **LP** tab to tuck the window away while you edit talents. |
| Single-click shows the talents but **Apply Changes** stays grey | The talent window hasn't refreshed its buttons yet. Click any talent and click it back, or double-click the build instead. Please report it if it happens every time. |
| Clicking a build freezes the game briefly | Should be rare since 0.10, which only changes the talents that differ. A full rebuild still happens when switching hero trees. If it happens every time, please report it. |
| No prompt when entering a tagged instance | Type `/lp why` inside it, which explains exactly what it sees. Common causes: the tag is for another difficulty, you already have that build, you're in combat, or it already asked this visit (use `/lp prompt`). Tags made in another spec now produce a "tagged for another spec" prompt with a switch button. |
| A tag doesn't highlight in the instance | Check its difficulty (shown in brackets). A Mythic tag doesn't apply in Heroic. |
| "The Starter Build can't be changed" | Select or create a regular loadout in Blizzard's dropdown first. |
| Blocked-action errors after applying | A known WoW taint issue with addon-applied talents. `/reload`, and use single-click + Apply Changes from then on. |
| An old loadout named after one of your builds appeared | Versions before 0.9 applied builds through an extra "slot" loadout. It's now a normal loadout that you can keep or delete. |
| "*N* talents wouldn't learn" | The code no longer fits the current tree. Re-export it from its source. |
| "The game refused the change" | You're probably switching too fast. Wait a moment. Also check for combat or an active Mythic+ key. |
| Check marks look wrong | Hover the entry. If the tooltip says "Matches your current talents" but there's no check mark (or the reverse), please report the build's import code. |
| Boss icons show round portraits | No achievement matched that boss's name. Please report the boss. |
| Icon grid has no "All icons" section | The game's macro icon functions weren't available. Search and the named sections still work. |
| Top builds says "No Raider.IO data yet" | Run LoadoutPlannerSync (see its README), make sure **LoadoutPlannerData** is enabled in the AddOns list, then `/reload`. Or switch to the parses.gg source. |
| Top builds says "No parses.gg data installed" | Install **ArchonTalentsData** (and remove PeaversTalentsData if you have it), then `/reload`. |
| An Archon link shows a "not found" page | Archon may have changed a boss's URL name. Open your spec's page on Archon and pick the boss there. The name mapping lives in `SLUG_OVERRIDES` in `Archon.lua`. |
| TLE import finds nothing | Talent Loadout Ex must be **enabled** (then `/reload`) for its data to be readable. |
| Anything else | Check BugSack for the error text. |

---

## 18. Credits

- **Blizzard's UI source** (the `Gethe/wow-ui-source` mirror) was used to confirm the import format, the parser methods, how loadouts are staged and committed, and the talent window's layout and background textures.
- **Raider.IO addon issue #396** described the approach of rewriting one persistent loadout in place, rather than deleting and recreating loadouts, which wipes their action bars.
- **ArchonTalentsData** by EliteTC (MIT) is the recommended data addon, and its `tools/maps.mjs` provided the archon.gg URL scheme and spec slugs used in `Archon.lua`. Its readme documented why Archon can no longer be read automatically.
- **Raider.IO** provides the data behind LoadoutPlannerSync through its official API. The **tmaffia/raiderio** Go client (MIT) was used to confirm the endpoints and response fields.
- **parses.gg** provides the build data behind ArchonTalentsData, and states it is free to read and build against.
- **Talent Loadout Ex** by Morizo was read to learn its saved-data format for the importer, and inspired the list and icon-picker designs.
