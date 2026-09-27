# LoadoutPlanner: How It's Built (and How You'd Build It Yourself)

This walks through the addon in the order you'd write it from scratch. For each file you get the thinking behind it, the decisions that shaped it, and a small exercise to prove you understand it. Read each file alongside its section here.

---

## 📌 1. Install and smoke test

1. Unzip so you have `World of Warcraft/_retail_/Interface/AddOns/LoadoutPlanner/` containing the `.toc` and five `.lua` files. The folder name **must** match the `.toc` file name.
2. In game, run `/dump select(4, GetBuildInfo())`. If the number isn't `120100`, change the `## Interface:` line in the `.toc`. (A mismatch just marks it "out of date". It still loads if you tick "Load out of date AddOns".)
3. Make sure BugGrabber + BugSack are installed, then `/reload`.

**Test checklist.** Bring back anything that fails, plus the BugSack text:

- [ ] `/lp help` prints the command list
- [ ] `/lp list` shows your loadouts, with the selected one marked
- [ ] `/lp load <name>` switches builds, and Blizzard's dropdown shows the new name
- [ ] `/lp load` during combat queues the change and applies it after combat
- [ ] In a dungeon: `/lp tag <name>`, leave, re-enter, and you get the prompt
- [ ] In a raid: `/lp bosses` lists bosses, `/lp tagboss 1 <name>` works
- [ ] Opening the talent window shows the panel docked to its right
- [ ] `/reload`, then `/lp tags` still shows everything

---

## 🔹 2. The big picture

```
Core.lua      plumbing: namespace, events, slash commands
Loadouts.lua  talk to the talent system: read + switch
Data.lua      remember things: SavedVariables + tags
Context.lua   know where you are: instance, bosses, prompt
UI.lua        show it all in a panel
```

Each file only uses things defined in files above it (the `.toc` load order). That's why `Core.lua` has no idea the UI exists, and why `ns.Notify()` exists: lower layers can say "something changed" without depending on higher ones. This is the same separation you'd do in Express between routes, services, and the DB layer.

### Lua for a JavaScript developer

| JavaScript | Lua |
|---|---|
| `let x = 1` | `local x = 1` (forget `local` and you've made a global) |
| `null` / `undefined` | `nil` |
| `arr[0]` | `arr[1]`, because lists start at 1 |
| `arr.length` | `#arr` |
| `for (const x of arr)` | `for i, x in ipairs(arr) do ... end` |
| `for (const k in obj)` | `for k, v in pairs(obj) do ... end` |
| `a !== b` | `a ~= b` |
| `!x`, `&&`, `\|\|` | `not x`, `and`, `or` |
| `` `Hi ${name}` `` | `"Hi " .. name` or `("Hi %s"):format(name)` |
| `x ?? y` | `x or y` (careful: treats `false` like `nil`) |
| `cond ? a : b` | `cond and a or b` (breaks if `a` is `false`/`nil`) |
| `try/catch` | `local ok, result = pcall(fn, args...)` |
| functions return one value | functions can return **several**: `local a, b = f()` |

Only `nil` and `false` are falsy in Lua. `0` and `""` are **truthy**, which is the opposite of JS for those two values.

---

## 🔹 3. Core.lua: the plumbing

**What you'd do first:** get *anything* running. A `.toc` plus a file that prints on load. Then add the three things every addon needs.

**The namespace (`local addonName, ns = ...`).** Every file gets the same private `ns` table. Think of it as your module system. You put functions on `ns` to share them between files instead of making globals that could clash with other addons.

**The event dispatcher.** The game is event-driven, and only frames can listen for events. The naive approach is one frame per file, each with its own `OnEvent`. That works, but it gets messy. `ns.On(event, fn)` lets any file subscribe to any event, like `emitter.on()` in Node. The `pcall` around `RegisterEvent` matters because registering a misspelled or removed event name throws an error.

**Slash commands.** WoW finds them through magic global names (`SLASH_LOADOUTPLANNER1`), which is the one place we *have* to create globals. The router splits the input with a Lua pattern and looks up `ns.commands[cmd]`, so other files add commands just by adding keys to that table. It's the same idea as an Express router.

> **Exercise:** add `/lp version` that prints the version from the `.toc`. (Hint: `C_AddOns.GetAddOnMetadata(addonName, "Version")`.)

---

## 🔹 4. Loadouts.lua: talking to the talent system

**The mental model to lock in:** each spec has one *active config* (your real talents) and several *saved loadouts* (each with a `configID`). Loading a loadout copies it into the active config. Almost every talent API bug comes from mixing those two up.

**Reading** is a straight chain: spec ID → list of config IDs → `C_Traits.GetConfigInfo` for each name. The `or {}` guards cover the moment at login before the list exists. `TRAIT_CONFIG_LIST_UPDATED` is the game's signal that it's ready.

**Switching** is where the interesting decisions are:

- **Combat queueing.** Rather than failing when you're in combat, we stash the request in `pendingLoad` and retry on `PLAYER_REGEN_ENABLED` (the "combat ended" event). This is a common WoW pattern because so much is locked during combat.
- **Asynchronous result.** `LoadConfig` only *starts* the switch, like calling `fetch()` without awaiting it. The real confirmation is `TRAIT_CONFIG_UPDATED`, which is why the "Loaded X" message lives in that event handler rather than after the call.
- **Letting the game explain failures.** We don't try to predict every rule (Mythic+ key active, rested state, etc.). We call `LoadConfig` and print its `changeError` string. That's less code, and it stays correct when Blizzard changes the rules.
- **Keeping Blizzard's dropdown honest.** `UpdateLastSelectedSavedConfigID` makes the talent window show the right loadout name. This is the line I'm least sure about, so it's marked VERIFY.

> **Exercise:** `/lp load` needs an exact name. Make it also accept a partial match when only one loadout matches (hint: `name:find(text, 1, true)` does a plain substring search).

---

## 🔹 5. Data.lua: remembering things

**SavedVariables** are simpler than they look. You name a global in the `.toc`, and the game saves that table to disk on logout/reload and restores it before your `ADDON_LOADED` fires. That timing is the trap: touch `LoadoutPlannerDB` earlier and it's `nil`. The `x = x or {}` lines fill in defaults for a first-time user without wiping an existing user's data.

**Why tags are per spec:** loadouts belong to a spec, so a Holy build tagged to a boss means nothing on Retribution. Putting `specs[specID]` at the top of the shape makes that impossible to get wrong.

**The key design decision is what a tag stores.** This came up in the roadmap, and here's what I chose:

- `configID`: exact and fast, but dies if you delete and recreate the loadout
- `name`: the fallback when the ID is gone
- `exportString`: stored but not used yet, kept for recovery and sharing later
- `label`: the boss or instance name at tagging time, so we can display tags without looking anything up

`ResolveRef` tries the ID, then the name, and **repairs the stored ref** when a fallback hits. If you renamed the loadout, it updates the name. If you recreated it, it updates the ID. The data heals itself as it's used.

**Keys are IDs, never names.** Instance and boss names are localized, so a German client sees different strings. The numeric IDs are the same everywhere.

> **Exercise:** add `/lp export` that prints the stored `exportString` for the current instance's tag, so you could paste it to a raider.

---

## 🔹 6. Context.lua: knowing where you are

**`GetInstanceInfo()`** returns about ten values. The `local name, instanceType, _, _, _, _, _, instanceID = ...` line is Lua's way of picking the ones you want. `_` is just a variable name people use for "ignore this". Instance type `"party"` means dungeon and `"raid"` means raid.

**Bosses come from the Encounter Journal**, which has its *own* instance IDs. So the chain is: current map → `EJ_GetInstanceForMap` → loop `EJ_GetEncounterInfoByIndex` until it returns `nil`. That `while true ... break` loop is idiomatic for APIs that don't tell you the count up front.

**Why bosses are manual, not automatic:** auto-detecting "you're about to pull boss X" means relying on encounter data, which is exactly the kind of thing Midnight restricted. A picker you control can't be broken by those restrictions.

**The prompt uses `StaticPopupDialogs`**, Blizzard's shared dialog system. You define the dialog once and show it with data. Two deliberate choices:

- **`promptedInstanceID`** stops re-prompting after you say No, and resets when you leave the instance.
- **`C_Timer.After(1, ...)`**: zoning fires several events in a burst, and some data lags behind them, so we wait a second before checking.

> **Exercise:** right now boss tags can only be set while you're inside the raid. How would you let players tag bosses from anywhere? (Hint: `EJ_GetInstanceByIndex` lists instances by tier.)

---

## 🔹 7. UI.lua: the panel (v0.1; see section 10 for the redesign)

**Frames and templates.** `CreateFrame("Frame", name, parent, "BasicFrameTemplateWithInset")` gives you a bordered window with a close button for free. Buttons use `UIPanelButtonTemplate`. Text is a *font string* created from a frame, and it's positioned with **anchors**: `SetPoint("TOPLEFT", otherThing, "BOTTOMLEFT", x, y)` means "put my top-left at their bottom-left, offset by x/y". Anchoring is WoW's layout system, so it's worth playing with until it clicks.

**Pooling rows.** You can't delete frames in WoW. Once created, they exist until reload. So rows are created only when needed and then reused, with extras hidden. Each button reads `row.entry` at click time, so the same button serves whichever boss the row currently shows.

**Refresh-from-scratch.** `RefreshUI` never keeps its own copy of the data. It re-reads everything from the game and the DB each time. It's the same idea as React re-rendering from state: less to keep in sync means fewer bugs. It skips work when the panel is hidden.

**Hooking Blizzard's window safely:**

- The talent UI is load-on-demand, so `EventUtil.ContinueOnAddOnLoaded` waits for it (or runs right away if it's already loaded).
- `HookScript` *adds* behavior after Blizzard's. Overwriting their scripts or functions causes **taint**, which is WoW's security system flagging Blizzard code that addon code has touched. Tainted code can break protected actions in weird, delayed ways.
- Anchoring *our* frame *to* theirs is safe. Moving or resizing *theirs* is not.
- Dragging the panel sets `attached = false`, so we stop overriding a position the player chose.

> **Exercise:** add a "Load" button for whatever loadout is tagged to the *next* unkilled boss. (Look into `GetInstanceLockTimeRemainingEncounter`, and 🔹verify it's still readable in Midnight.)

---

## 🔹 8. What I couldn't verify (you're my test environment)

These are marked `VERIFY` in the code:

- **`UpdateLastSelectedSavedConfigID`**: if BugSack shows `ADDON_ACTION_BLOCKED`, delete that line in `Loadouts.lua`.
- **`Blizzard_PlayerSpells` / `PlayerSpellsFrame`**: if the panel never docks, hover the talent window with `/fstack` and tell me what it says.
- **Interface number `120100`**: confirm with `/dump`.
- **Encounter Journal calls**: if `/lp bosses` says "No bosses found" inside a raid, run `/dump EJ_GetInstanceForMap(C_Map.GetBestMapForUnit("player"))` and send me the result.

---

## ✅ 9. Build-it-yourself challenges (in rising difficulty)

1. `/lp version` (Core)
2. Partial name matching for `/lp load` (Loadouts)
3. `/lp export` for sharing strings (Data)
4. A "Changing talents failed" message when the cast is interrupted (🔹research which event fires; the current code just never prints "Loaded")
5. Tag bosses from outside the raid (Context + UI)
6. **Recovery:** if a tagged loadout is missing, offer to recreate it from `exportString`. Read how Blizzard's import dialog does it in `wow-ui-source`. This is the hardest one, and it's where the Raider.IO issue from the roadmap becomes required reading.

---

# Part 2: v0.2 (the Talent Loadout Ex-style redesign)

## 📌 10. What changed and where

| Feature | File | New concepts |
|---|---|---|
| Full-height loadout list beside the talent window | `UI.lua` (rewritten) | scroll frames, two-point anchoring, context menus |
| Spec buttons on the Talents tab | `SpecBar.lua` (new) | parenting to Blizzard frames, API fallbacks, closures |
| Hover comparison mini-tree | `Diff.lua` (new) | the Traits data model, coordinate mapping, lines + masks |
| Plumbing | `Core.lua`, `Data.lua`, `Context.lua` | a subscriber list for refreshes, reverse lookups |

**Before testing:** if you keep Talent Loadout Ex enabled, the two panels will overlap, and the other addon's spec icons sit where ours go. Disable it while you try this.

**Test checklist (v0.2):**

- [ ] Opening talents shows the panel docked right, full height, listing your loadouts
- [ ] The active loadout has a check mark, and clicking another row loads it
- [ ] Right-click in a dungeon offers "Tag to <dungeon>", and in a raid also "Tag to boss >"
- [ ] Tagged rows show their tags as gray text and a boss portrait icon, and a green strip when you're in that instance
- [ ] Spec icons appear bottom-center-right of the Talents tab, only on that tab, and clicking one switches spec
- [ ] Hovering a row shows the mini-tree to the left, with sensible colors and a name list

---

## 🔹 11. Core.lua: from one refresh hook to many

v0.1 had `ns.RefreshUI` as a single hard-coded hook. Now two UI pieces care about changes, so `ns.OnRefresh(fn)` keeps a list of subscribers and `ns.Notify()` calls each one. It's the same pattern as `ns.On` for game events. When you notice you've written the same "call this if it exists" hook twice, that's the time to turn it into a list.

---

## 🔹 12. SpecBar.lua: switching specs on the talent page

**Parenting decides visibility.** The bar's parent is `PlayerSpellsFrame.TalentsFrame`, the Talents *tab*. In WoW, a hidden parent hides all its children. So the bar appears only on that tab without any show/hide code. Parenting and anchoring are separate: the parent controls visibility and layering, and the anchor controls position. Here we parent to the tab but anchor to the whole window's corner.

**Frame levels.** The talent tree is full of buttons. `SetFrameLevel(host:GetFrameLevel() + 200)` puts our bar above them so clicks land on our buttons.

**API fallbacks.** `local setSpec = SetSpecialization or specAPI.SetSpecialization` picks whichever function exists. Blizzard is migrating spec functions into `C_SpecializationInfo`, and this line keeps working through that move. `or` returns its first truthy operand, which makes it a handy "first one that exists" operator.

**Closures in loops.** Each button's `OnClick` calls `ns.SwitchSpec(index)`. That works because a numeric `for` loop gives each pass its *own* `index`. With a `while` loop and one shared counter, every button would switch to the last spec. This is the same trap as `var` vs `let` in a JS loop.

**Moving the bar:** change `BAR_OFFSET_X` / `BAR_OFFSET_Y` at the top of the file. I estimated them from your screenshot, so expect to adjust.

> **Exercise:** add a small role icon under each spec button. (Look up the `roleicon-tiny-tank` style atlases and `texture:SetAtlas`.)

---

## 🔹 13. UI.lua: a Talent Loadout Ex-style list

**Two-point anchoring = auto sizing.** When docked, the panel is anchored at *both* its top-left and bottom-left to the talent window's right edge. With both edges pinned, its height always matches, even if you resize or rescale the talent window. When floating, it's anchored at one point with a fixed height.

**Scroll frames.** A `ScrollFrame` is a viewport onto a taller *scroll child*. Rows go in `content`, whose height we set to `rows × ROW_HEIGHT`, and the template handles the scroll bar. This is like a fixed-height `div` with `overflow: auto`.

**Buttons as rows.** Each row is a `Button`, so it gets clicks, a highlight texture on hover, and `RegisterForClicks("LeftButtonUp", "RightButtonUp")` for right-click. The `OnClick` handler receives *which* mouse button was pressed.

**Context menus with MenuUtil.** You don't build menu frames yourself. You describe the menu in a function, and nested `:CreateButton()` calls on a button make submenus. This is declarative, a bit like JSX, and a big improvement over the old `UIDropDownMenu` API you'll see in older addon code.

**Boss portraits.** `EJ_GetCreatureInfo(1, encounterID)` returns the boss's portrait as its 5th value. We wrap it in `pcall` because a bad encounter ID shouldn't break the whole list.

**Reverse lookup.** Tags are stored "boss → loadout", but each row needs "loadout → bosses". `ns.GetTagsForLoadout` scans the tags and filters. With a few dozen tags that's instant, so there's no need for a second index that could drift out of sync with the first.

> **Exercise:** add a search box at the top that filters rows by name or tag. (Look at `SearchBoxTemplate` and its `OnTextChanged` script.)

---

## 🔹 14. Diff.lua: comparing builds

This is the most interesting file, and it's split into three parts on purpose.

### Part 1: the data (no UI at all)

The Traits system has layers, and it's worth learning them:

```
tree (your class)
 └─ nodes (each circle/square/octagon)      C_Traits.GetTreeNodes / GetNodeInfo
     └─ entries (1, or 2 for choice nodes)  C_Traits.GetEntryInfo
         └─ definition                      C_Traits.GetDefinitionInfo
             └─ spell (name, icon)          C_Spell.GetSpellName
```

`GetNodeInfo(configID, nodeID)` answers the question "in *this* config, what's the state of *this* node?" So the diff is: for every node, ask the active config and the loadout's config, then compare. `classify()` turns two (rank, choice) pairs into one of five statuses. It's a pure function you could unit test.

Hero talents add a wrinkle. Both hero trees exist in the data, and a node only counts if its sub-tree is active *in that config*. We draw only the loadout's hero tree, because both trees occupy the same screen area, and we mention a hero switch in text.

**Why split data from drawing?** So you can debug the diff with no UI at all. `ns` is private, so you can't reach it from `/run` by default. That's intentional, but while developing you can add `LoadoutPlannerDev = ns` to the bottom of Core.lua. Then `/dump #LoadoutPlannerDev.ComputeDiff(<configID>).added` shows how many talents a loadout adds. Remove the line before sharing the addon.

### Part 2: layout

Node positions come in game coordinates, on the order of thousands of units. `placeGroup` normalizes each group to 0..1 and scales it into a rectangle, which is the standard "map from one range to another" trick you'd use for a chart axis. To separate the class tree from the spec tree, we sort by x and split at the widest gap. That's a simple heuristic that avoids needing an API to tell us which tree a node belongs to.

### Part 3: drawing

- **Lines:** `map:CreateLine()` plus `SetStartPoint` / `SetEndPoint` draw a line between two points. Edges are drawn before dots so dots sit on top.
- **Circles:** there's no circle primitive, so each dot is a colored square clipped by a round **mask texture**. The same mask trick is how round portraits work across the UI.
- **Y flips:** our layout math has y growing downward, but WoW's UI y grows upward, which is why every offset is `-pos.y`.
- **Pools again:** dots and lines are created once and recycled on every hover.

> **Exercise:** make the dots bigger for capstone/octagon choice nodes. (Check `nodeInfo.type` against `Enum.TraitNodeType.Selection`.)

---

## 🔹 15. What I couldn't verify in v0.2

- **Diffing a saved loadout:** this assumes `C_Traits.GetNodeInfo(savedLoadoutID, nodeID)` returns that loadout's picks. **If every hover shows your whole build as red (removed)**, that assumption is wrong, and we'll switch to reading the loadout's export string instead. Tell me what you see.
- **Spec bar position:** these offsets are estimates from your screenshot.
- **`UIPanelScrollFrameTemplate`, `MenuUtil`, `PlayerSpellsFrame.TalentsFrame`:** all should exist in 12.x. Any errors naming them go straight to me with the BugSack text.

---

# Part 3: v0.3 (locked panel, art transparency, custom build library)

## 📌 16. What changed and where

| Feature | File | New concepts |
|---|---|---|
| Panel locked to the talent window | `UI.lua` | parenting instead of positioning |
| Background art transparency slider | `Background.lua` (new) | reading Blizzard's XML, building a widget from parts |
| Custom builds with groups | `Builds.lua` (new) | account-wide SavedVariables, ordered arrays |
| Applying import codes | `Import.lua` (new) | reusing Blizzard's parser, async creation, retry passes |
| Add/edit dialog, icon picker | `Editor.lua`, `IconPicker.lua` (new) | edit boxes, validation, paging |
| One "item" type for loadouts and builds | `Loadouts.lua`, `Data.lua`, `Diff.lua` | interfaces in a language without classes |

**Before testing:** disable any other addon that adds a transparency slider, spec buttons, or a loadout panel to the talent window, or you'll see two of each.

**Test checklist (v0.3):**

- [ ] The panel is glued to the talent window: it can't be dragged, and it moves, scales, and closes with the window
- [ ] The slider fades the talent background art, and the setting survives `/reload` and spec changes
- [ ] **Import:** paste a code. The status line says "OK: Balance build" (or explains what's wrong), and Save adds it under the group you typed
- [ ] **Save current:** opens the editor with your current talents' code already filled in
- [ ] Click the icon in the editor to open the picker. Paging and the mouse wheel work, and typing a spell name + Enter picks its icon
- [ ] Clicking a custom build applies it with ONE "Changing Talents" cast. The first time per spec, it creates a loadout slot named after the build
- [ ] Hovering a custom build shows the diff tree. Hovering an other-spec build explains that it's for another spec
- [ ] Right-clicking group headers gives rename/move/delete, and clicking a header collapses it
- [ ] Tagging a custom build to a boss works like tagging a Blizzard loadout

---

## 🔹 17. Locking the panel: parent, don't position

v0.2 kept the panel as a child of `UIParent` and used hooks to show it, hide it, and re-anchor it. v0.3 simply calls `panel:SetParent(PlayerSpellsFrame)`. A child frame inherits its parent's visibility, scale, and movement, so all that hook code disappeared. When you want something to "follow" another frame, reach for parenting first, and use anchoring for *where* inside or beside it.

---

## 🔹 18. Background.lua: reading Blizzard's source

To find the background art, I read `Blizzard_ClassTalentsFrame.xml` in `wow-ui-source`. The talents tab has `BlackBG` (a solid black layer) under `Background` (the spec painting), plus animated layers with `alpha="0"` that Blizzard fades in and out. We fade only the first two. Changing the alpha of an animated texture is pointless, because the animation overwrites it every frame.

That's a general skill worth practicing: when you want to change something Blizzard draws, find its XML, look up its `parentKey`, and reach it as `ParentFrame.ChildKey.TextureKey`.

**The slider** is built from a plain `Slider` frame plus decades-old textures, rather than a Blizzard slider template. Templates get renamed between expansions, while basic widgets and textures rarely change. `ns.CreatePercentSlider` is reusable. It takes a label and a callback and knows nothing about talents.

---

## 🔹 19. Builds.lua: your library

**Account-wide storage.** The TOC now has `## SavedVariables: LoadoutPlannerBuilds` next to the per-character line. Builds are keyed by class (`LoadoutPlannerBuilds.DRUID`), so every druid alt shares them, while tags and settings stay per character.

**Arrays for order.** Tags use ID-keyed tables because order doesn't matter there. Groups and builds are arrays (`{ group1, group2 }`) because *you* arrange them. Moving an item is a swap: `list[a], list[b] = list[b], list[a]`. Lua evaluates the whole right side before assigning, so no temp variable is needed.

**Reading a code without the talent window.** An import code is a base64-encoded bit stream. Blizzard documents its header: 8 bits of format version, then 16 bits of spec ID. `ns.ReadCodeHeader` reads just those two values to validate a code while you type it. It tells you whether the code is readable, whether it's from the current game version, and whether it's for your class.

---

## 🔹 20. Import.lua: turning codes into talents

**Reuse Blizzard's parser.** `ClassTalentImportExportMixin` is the code behind Blizzard's own Import button. Its `ReadLoadoutHeader`, `ReadLoadoutContent`, and `ConvertToImportLoadoutEntryInfo` methods only read the code and the tree, so we can call them directly. If Blizzard changes the format, we inherit the fix instead of maintaining our own decoder.

**The slot strategy.** Blizzard caps how many loadouts you can save, so we don't create one per build. Instead, one Blizzard loadout per spec acts as a slot, and applying a build rewrites it:

1. `C_ClassTalents.LoadConfig(slotID, false)`. With `autoApply = false`, the loadout is *staged*, not committed. I learned this from `LoadConfigInternal` in Blizzard's source, where `Ready` means "staged, waiting for commit". It's what makes this one cast instead of two.
2. `C_Traits.ResetTree` clears the staged tree.
3. Purchase every node from the build.
4. `C_ClassTalents.CommitConfig(slotID)` applies it and saves it into the slot.
5. The slot is renamed after the build, so Blizzard's dropdown shows the right name.

**The retry-passes algorithm.** Nodes have prerequisites (arrows, point gates, the hero-tree choice), and purchasing one before its prerequisites fails. Instead of sorting nodes by dependency, `purchaseAll` loops over everything that's left, buying what it can, and repeats until a full pass makes no progress. Anything still left over means the code doesn't fit the current tree. In that case we **roll back** (`C_Traits.RollbackConfig`) rather than committing half a build. This is a simple, robust pattern for any set of tasks with unknown dependencies.

**Async creation with a timeout.** Creating the slot (`RequestNewConfig`) is asynchronous: the game answers later with `TRAIT_CONFIG_CREATED`. We subscribe with `ns.On`, unsubscribe with the new `ns.Off` once it arrives, and set a 10-second `C_Timer.After` so a lost event can't leave us waiting forever. This is roughly what a JS Promise with `Promise.race` against a timeout does.

---

## 🔹 21. One "item" type, two data sources

Rows, tags, prompts, and the diff all used to assume a Blizzard loadout. Now an **item** is anything with a `key` and a `name`, plus either `configID` or `build`. `ns.LoadItem`, `ns.IsItemActive`, and `ns.ComputeDiff` check which kind they have in one place, so everything else just passes items around.

`Diff.lua` goes further with **readers**: small tables of functions (`read`, `heroActive`) that answer the same questions from different sources. A saved loadout asks the game, while a custom build looks things up in its parsed entries. The diff code only calls `reader.read(...)`. Lua has no classes or interfaces, so a table of functions *is* the interface. In JS terms this is duck typing, and it's the same idea as a Strategy pattern.

---

## 🔹 22. Editor.lua and IconPicker.lua

- **EditBoxes** (`InputBoxTemplate`) need `SetAutoFocus(false)`, or they grab the keyboard as soon as they appear and you can't move your character. Also, `SetMaxLetters(0)` means "no limit", which matters because import codes are long.
- **Validation as you type:** `OnTextChanged` calls `validate()`, the same idea as a controlled input in React.
- **Tab order** is manual: each box's `OnTabPressed` focuses the next one.
- **A multiple-returns gotcha** (see `ns.OpenEditor`): `x and f()` keeps only `f`'s *first* return value. `select(2, f())` skips ahead to the second one first.
- **Icon picker:** Blizzard's list has thousands of unnamed icons, so it pages (buttons + mouse wheel) instead of scrolling. It also offers a spell-name box, since `C_Spell.GetSpellTexture("Moonfire")` is the fastest way to find a specific icon.

---

## 🔹 23. What I couldn't verify in v0.3

- **Applying builds** is the riskiest part: `LoadConfig(..., false)`, `ResetTree`, and `CommitConfig` into the slot. If it fails, the chat message tells us which step. Send me that message plus BugSack.
- **The hero-tree choice** during apply: if builds apply everything *except* hero talents, tell me.
- **`GetMacroIcons` / `GetLooseMacroIcons`:** if the picker grid is empty, you'll get a chat message, and the spell box still works.
- **`PlayerSpellsFrame.Bg`:** if the slider fades the tree art but a dark layer remains, `/fstack` over that dark area will tell us its name.

---

## ✅ 24. New challenges

1. Show a small spec icon on builds in the list (useful if you later show all specs at once).
2. Drag-and-drop reordering instead of Move up/down. Research `RegisterForDrag` on rows and work out which row the cursor is over on drop.
3. "Export group": one long string holding every build in a group, so you can share a full raid tier with your raid team.
4. A search box that filters builds by name, group, or tag.

---

# Part 4: v0.4 (LoadoutPlanner's own window)

## 📌 25. What changed and why

At your UI scale, the talent window already fills nearly the whole screen, so a panel attached to its right edge had nowhere to go. Rebuilding Blizzard's talent tree ourselves would mean redrawing and re-implementing every talent interaction, and it would break every patch. So instead, LoadoutPlanner got **its own window that decides where to live**:

| File | Change |
|---|---|
| `Window.lua` (new) | The window frame, header, placement logic, collapse tab, options menu, slider |
| `UI.lua` | Now only the list inside the window (menus, rows, refresh) |
| `SpecBar.lua` | Spec buttons became a reusable row: one in the window header, and an optional one on the talent tab |

**Test checklist (v0.4):**

- [ ] Open talents: the window appears beside the talent window if it fits, otherwise inside its right edge. It never goes off-screen
- [ ] The X tucks it into a small "LP" tab on the talent window's edge, and clicking the tab brings it back
- [ ] "..." > **Free**: the window can be dragged anywhere, and it remembers the spot after `/reload`
- [ ] "..." > **Inside**: the window sits over the right side of the tree, above the bottom bar
- [ ] The spec buttons in the window header switch specs
- [ ] `/lp reset` returns everything to automatic

---

## 🔹 26. Window.lua: deciding where to go

**Measuring in real pixels.** `frame:GetRight()` returns a position in *that frame's own scale*. The talent window and `UIParent` can have different scales, so comparing their raw numbers is comparing inches to centimeters. `fitsBeside()` multiplies each side by its frame's `GetEffectiveScale()` to convert both to screen pixels first. You'll need this trick any time you compare positions between frames.

**When to re-check.** Whether it fits can change when the talent window opens, resizes (`OnSizeChanged`), or when your UI scale or resolution changes (`UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`). There's one more subtle case. Blizzard positions its windows *just after* showing them, so on `OnShow` we place the window immediately and again on the next frame with `C_Timer.After(0, ...)`. A zero-second timer means "after the current frame finishes", which is WoW's version of `setTimeout(fn, 0)`.

**One frame, several parents.** Docked modes parent the window to the talent window, so it inherits its movement, scale, and visibility. Free mode parents it to `UIParent`, so it can go anywhere. `SetParent` can be called any time, which makes switching modes cheap.

**Strata for "inside" mode.** To draw *over* the talent tree, the window needs a higher strata than the talent window. `strataAbove()` picks the next level up from whatever the talent window uses, instead of hard-coding one. Raising strata beats raising frame levels here, because strata is inherited by all the window's children, while frame levels can leave some children underneath.

**`SetClampedToScreen(true)`** makes WoW itself refuse to put the window off-screen, in every mode. It's the safety net behind the placement logic.

**Collapse instead of close.** The X doesn't really close the window. It sets `collapsed` and shows a tab. There's one function, `UpdateWindowVisibility`, that decides what's shown from two facts: is the talent window open, and is the window collapsed? Keeping visibility in a single function stops show and hide calls from fighting each other across files.

---

## 🔹 27. SpecBar.lua: one component, two places

`ns.CreateSpecButtons(parent, size, spacing)` returns a self-contained row. Every row it creates is added to `allRows`, so one `PLAYER_SPECIALIZATION_CHANGED` handler updates all of them. That's the same component idea as React: build it once and render it wherever you need it. The talent-tab copy is now off by default (toggle it in "..."), because other addons often put their own buttons in that spot.

> **Exercise:** add a "Compact" option that hides the tag subtitles and shrinks rows to 28px, so more loadouts fit when the window is inside the talent frame.

---

# Part 5: v0.5 (making room, and the phantom fifth spec)

## 📌 28. What changed

- **Making room.** When the window doesn't fit beside the talent window, the talent window now slides left, and if needed shrinks slightly, so both fit on screen together. On a 1,618-unit-wide talent window plus our 260-unit window, that's about 93% scale on your setup. Auto mode only falls back to "inside" if it would have to shrink below 70%. You can turn this off under "..." > *Move/shrink talent window to make room*. Tucking the window away gives the talent window its normal size back.
- **Fifth spec button fixed.**

**Test checklist (v0.5):**

- [ ] Opening talents: the talent window and LoadoutPlanner sit side by side, both fully on screen
- [ ] Tuck the window away (X): the talent window snaps back to Blizzard's normal size and position
- [ ] Open the character window (C) while talents are open: everything re-arranges without overlapping
- [ ] Blizzard's own minimize button on the talent window still works, and placement adjusts
- [ ] Druid shows exactly four spec buttons, both in the header and on the talent tab if enabled

---

## 🔹 29. The bug: a hidden fifth spec

The old loop asked for specs 1 through 5 and stopped at the first *empty* one. Every class also has a hidden "starter" spec used before level 10, and `GetSpecializationInfo(5)` happily returns it for druids. So the loop never hit an empty slot, and we drew a button for a spec you can't pick.

**The lesson:** "loop until nil" only works when the data really ends with nil. When the game has a function that tells you the count (`GetNumSpecializations()`), ask for it instead of guessing. It's the same reason you'd use `array.length` instead of looping until `undefined`.

---

## 🔹 30. Moving someone else's window safely

This is the most delicate thing the addon does, because the talent window belongs to Blizzard. The rules:

1. **Change the frame, never Blizzard's bookkeeping.** Blizzard's own code shows that it positions this window through its panel manager (`SetUIPanelAttribute(self, "centerXOffset", ...)`). Calling that from addon code would **taint** the panel manager. Taint is WoW's security marker: any table value written by addon code is flagged, and when protected code later reads a flagged value in combat, actions get blocked. So we only use `SetScale` and `SetPoint` on the frame itself. Those change the widget, not Blizzard's Lua tables.
2. **Hook, don't call.** To react when Blizzard re-arranges panels, we use `hooksecurefunc("UpdateUIPanelPositions", ...)`. Blizzard's function runs untouched and securely, and then ours runs afterwards. Calling Blizzard's function ourselves would run it in *our* tainted context instead.
3. **Never in combat.** The talent window contains protected spellbook buttons, so moving it in combat is blocked. `restoreNatural` checks `InCombatLockdown()` and remembers to try again on `PLAYER_REGEN_ENABLED`.
4. **Always be able to undo.** We remember Blizzard's own anchor (`naturalPoint`) and scale (`baseScale`). We also remember the anchor *we* set (`ourPoint`), so we can tell whether Blizzard has re-positioned the window since, in which case that becomes the new natural anchor.

**The coordinate math** (`applyRoom`) uses one rule twice: *a child's offset × its scale = distance in the parent's units.* We measure the distance from the top of the screen in `UIParent` units, change the scale, then divide by the new scale to get the `SetPoint` offset in the frame's own units. This keeps the window at the same height on screen after shrinking.

---

## 🔹 31. Guarding against infinite loops

`PlaceWindow` changes the talent window's scale and anchor, and that could fire the very hooks (`OnSizeChanged`, panel re-layout) that call `PlaceWindow` again. A `placing` flag makes nested calls return immediately. The real work runs inside `pcall`, so the flag is reset even if something errors. The error is then passed to `geterrorhandler()`, so BugSack still shows it. This "guard flag + pcall + re-raise" pattern works for any function that can trigger itself.

> **Exercise:** add a "Talent window scale" slider under the art slider, so players can pick their own shrink level instead of the automatic fit. (Hint: store it in `ns.db`, and use it in `fitScale()` as an upper limit.)

---

# Part 6: v0.6 (one build window, a smarter icon picker)

## 📌 32. What changed

- **Window position options removed.** Placement is always automatic: beside the talent window, making room when needed, and inside only as a last resort. The "..." menu keeps just the two toggles. (Sections 25-26 still describe the old modes. The placement math and the ideas there still apply.)
- **The build editor is one window** in the style of your screenshot: import code at the top, then name and group, a *Selected icon* preview, and the icon grid embedded below. You can right-click the preview to go back to the automatic spec icon.
- **The icon grid shows the useful icons first:** current raid bosses (numbered in kill order), this season's dungeons (labeled with initials, like "AKCE" for Ara-Kara, City of Echoes), your specs, and every talent in your tree. All icons come last. Jump buttons scroll straight to each section.
- **Search now works.** It matches boss, dungeon, spec, and talent names, and a number looks up a spell ID or item ID.

**Test checklist (v0.6):**

- [ ] Import opens one window with the icon grid inside it
- [ ] The grid starts with the current raid's bosses, then dungeons, specs, and talents, followed by "All icons"
- [ ] Hovering an icon shows its name, and clicking it updates the preview with a highlight
- [ ] Searching a boss name, a dungeon name, or "moonfire" filters the grid, and "8921" finds Moonfire by ID
- [ ] Scrolling through "All icons" is smooth (mouse wheel and scroll bar)
- [ ] The "..." menu no longer has position options

---

## 🔹 33. Why the old search didn't work, and what "search" can mean

Blizzard's icon list is just file IDs, with no names attached, so there was never anything to search. The old box only worked for spell *names*, and only for spells in your spellbook, because that's all `C_Spell.GetSpellTexture("name")` can see.

So the new search works over **icons that do have names**: bosses and dungeons (from the Encounter Journal), specs, and your talents (from the talent tree, via entry → definition → spell, the same chain `Diff.lua` uses). A number is treated as an ID, since spell and item IDs work for any spell or item, known or not. The lesson: before building a search, check what your data can actually be searched *by*.

---

## 🔹 34. The Encounter Journal as a data source

`readSeason()` reads the journal's **last tier**. During a season, Blizzard makes that tier "Current Season", containing exactly this season's raids and Mythic+ dungeons. So when the season changes, the picker updates with no code changes. The chain is tier → instances (`EJ_GetInstanceByIndex`, once for raids and once for dungeons) → encounters → the boss's portrait (`EJ_GetCreatureInfo`).

**Borrowed state:** `EJ_SelectTier` changes *the* selected tier, which the real Encounter Journal window uses too. So we remember the previous tier and restore it afterwards, even if something errors in between (the `pcall`). Whenever you have to change shared state temporarily, save it, change it, and put it back.

---

## 🔹 35. A virtualized grid

"All icons" has thousands of entries. Creating a button for each would mean thousands of permanent frames, since frames can't be deleted. Instead, the picker creates **only the rows you can see** (8 rows × 11 buttons) and reuses them:

- The data is a flat list of *rows*. Each row is a section header, a set of up to 11 icons, or, for "All icons", just a start index (`allStart`), so we don't build thousands of little tables either.
- A vertical `Slider` acts as the scroll bar. Its value is the index of the first visible row, and the mouse wheel moves it.
- `Render()` fills the 8 visible row frames from `rows[offset + 1 ... offset + 8]`.

This is the same technique as React's virtualized lists (react-window). It matters any time a list is longer than the screen, and it's also how Blizzard's newer `ScrollBox` works internally.

**Two small details worth noticing:**

- `SetValue(0)` doesn't fire `OnValueChanged` if the slider is already at 0, so `reload()` sets the offset and redraws itself instead of relying on the event.
- `SearchBoxTemplate` already has its own `OnTextChanged` (for the clear button and hint text). `HookScript` adds ours without replacing Blizzard's.

**Testing outside the game:** for this version I ran `IconPicker.lua` in plain Lua with fake versions of the WoW functions (a *mock*), to catch logic errors before you have to `/reload`. That's how the "The Dawnbreaker" → "D" label got caught and fixed to "DAW". Mocking the API is a very effective habit for addon code.

> **Exercise:** add a "Recently used" section at the top of the grid, showing the last 11 icons you picked. (Hint: save them in `LoadoutPlannerBuilds`, and add them in `buildRows` before the raid sections.)

---

# Part 7: v0.7 (square boss icons, importing from Talent Loadout Ex)

## 📌 36. What changed

- **Raid sections in the icon picker** now start with the raid's own icon (labeled "R"), followed by a **square icon for each boss** instead of the Encounter Journal's round portraits.
- **Rows in the list** show the icon of the dungeon, raid, or boss they're tagged to (unless you picked an icon yourself), instead of a boss portrait. Tags remember their icon from the moment you create them.
- **Import from Talent Loadout Ex:** "..." > *Import from Talent Loadout Ex*, or `/lp importtle`. It copies every class's loadouts and groups, and running it twice doesn't create duplicates.

**Test checklist (v0.7):**

- [ ] With Talent Loadout Ex **enabled**, run the import. Your groups and loadouts appear, including on alts of other classes
- [ ] Icons you chose in TLE carry over, including hero-talent emblems
- [ ] Running the import again reports "already existed"
- [ ] Afterwards you can disable TLE, and everything stays
- [ ] The icon picker's raid section shows square boss icons, and the raid's own icon first
- [ ] Tag something to a boss: its row shows that boss's icon

---

## 🔹 37. Reading another addon's data

**Find the format in the source.** I downloaded Talent Loadout Ex and read its `.toc` (`## SavedVariables: TalentLoadoutEx`) and `modules/data.lua`. The layout is `TalentLoadoutEx[CLASS][specIndex]`, a list in which **an entry without `text` is a group header** and the loadouts below it belong to that group. That "flat list with header rows" design is common in WoW addons, because it's easy to reorder by drag and drop. We convert it into our nested `groups → builds` shape, which is easier to work with.

**Other addons' SavedVariables only exist while they're enabled.** The game loads an addon's saved file only if the addon itself loads. That's why the importer asks you to enable TLE first, and why we *copy* the data instead of reading TLE's table every time.

**Trust the data itself over metadata.** Each loadout's spec is read from its import code's header (`ns.ParseCodeSpec`) and checked against the class. TLE's spec index is only a fallback, because the code is what will actually be applied.

**Idempotent imports.** Running the importer twice gives the same result as running it once, since loadouts with the same name and code are skipped. Anything a user might click twice should work this way.

**Defensive reading.** TLE's own code notes that its lists can contain gaps, so we loop with `pairs` over specs, skip anything that isn't a table, and skip `isLegacy` entries (a pre-Dragonflight format that can't be applied).

**Testing with fake data.** Before shipping, I ran `ImportTLE.lua` in plain Lua against a hand-made `TalentLoadoutEx` table covering every case: loose loadouts, groups, a group name reused across specs, a code with stray whitespace, an unreadable code, a legacy entry, and a second run. Writing that fake table is also the fastest way to *understand* a data format.

---

## 🔹 38. Finding square boss icons without hard-coding

TLE keeps a hand-typed list of icon file numbers for every boss, and it has to be updated each season. We find them instead, because each raid boss has a "Mythic: *Boss*" achievement with square boss artwork:

1. Read every achievement in the "Dungeons & Raids" category and its subcategories, **once**, and cache the name and icon of each.
2. For a boss, take the achievements whose name contains the boss's name, and pick the one with the **fewest extra characters**. "Mythic: Plexus Sentinel" beats "Glory of the Manaforge Raider".
3. If nothing matches, fall back to the journal portrait.

This works in any game language, because it doesn't look for the word "Mythic", and it keeps working in future seasons with no code changes. The trade-off is that it's a *heuristic*: an odd boss name could occasionally pick the wrong achievement. That's why the fallback exists, and why the cache also remembers "found nothing" (`false`), so we don't search again each time.

---

## 🔹 39. Atlases vs. textures

Some icons (TLE's hero-talent emblems, for example) aren't image files but **atlas names**: named rectangles on a larger sprite sheet, like CSS sprites. They need `texture:SetAtlas(name)` instead of `SetTexture`. `ns.SetIcon` checks with `C_Texture.GetAtlasInfo` and uses the right one. There's one trap: `SetAtlas` changes the texture coordinates and `SetTexture` doesn't reset them, so `SetIcon` always sets the coordinates explicitly. Otherwise a row that once showed an atlas would crop the next icon strangely.

---

## 🔹 40. A bug found while reading: ID collisions

Build IDs were "current time + a random number from 0 to 9999". Importing 100 builds in the same second gives a **~40% chance** that two get the same ID. This is the birthday problem: collisions show up much sooner than intuition suggests. IDs now include a counter as well (`time-counter-random`), which can't collide within a session.

> **Exercise:** add the reverse direction. "Export group" should produce text in TLE's own export format (see `GetSpecDataText` in TLE's `data.lua`), so friends who use TLE can import your builds.

---

# Part 8: v0.8 (check marks for identical builds, and a README)

## 📌 41. What changed

- **Check marks now mean "these are exactly my current talents".** Every matching entry is checked, whether it's a Blizzard loadout or a custom build, and whichever one you clicked. They update live as you change talents.
- **README.md** is the full user and technical reference. LEARNING.md stays as the tutorial.

**Test checklist (v0.8):**

- [ ] Save the same talents as two builds (say, under two bosses), then apply one: both get check marks
- [ ] Change one talent in Blizzard's UI: the check marks disappear, and changing it back brings them back
- [ ] Applying a build doesn't stutter (the list redraws once, not per talent)
- [ ] A Blizzard loadout with the same talents as a custom build is checked too

---

## 🔹 42. Fingerprints: comparing by content, not identity

The old check mark asked *"is this the one that was loaded?"*, which is a question about **identity**. You wanted *"does this have the same talents?"*, which is a question about **content**. For content equality, the classic technique is to turn each thing into a **canonical string** and compare strings:

- Walk the tree's nodes **in a fixed order** (`GetTreeNodes` returns them sorted by ID), and write `node:ranks:choice` for each purchased talent.
- Same talents always produce the same string, so equality is one `==`.
- The fingerprints can be cached, and each cache is cleared when its data can change.

**Deciding what goes into the fingerprint is the real design work.** The first idea was to include every rank. But import codes store free talents as *granted*, while saved loadouts report them as *current rank*. The hero-tree choice node is also recorded differently by each. With those included, identical builds would never match. So the fingerprint includes only what the player actually chooses: purchased ranks, plus the option picked on choice nodes. I checked these cases outside the game with a fake talent tree containing a granted node, a choice node, and two hero trees. That's exactly the kind of edge case to test before you have to debug it in game.

---

## 🔹 43. Debouncing bursts of events

Applying a build fires `TRAIT_NODE_CHANGED` once for **every talent**, often more than a hundred times in a single frame. Redrawing the list (with fingerprints) for each one would freeze the game. `talentsChanged()` clears the caches immediately, which is cheap, but schedules **one** redraw 0.2 seconds later, and ignores further requests while one is pending. This is called **debouncing**, the same idea as debouncing a search box in JavaScript. Any time an event can fire in bursts, debounce the expensive reaction.

> **Exercise:** show a small number next to groups whose builds match your current talents, like "Raid (5) ✓1". (Hint: the loop in `refresh()` already calls `ns.IsItemActive` for each visible build.)

---

# Part 9: v0.9 (stage with a click, apply with a double-click)

## 📌 44. What changed

Custom builds no longer go through a separate "slot" loadout. They change **your currently selected Blizzard loadout**:

- **Single-click** a build: its talents appear on the talent screen as *pending* changes, with Apply Changes lit.
- **Double-click**: the same, then applied and saved into your selected loadout.
- Blizzard loadouts still load with a single click.

Sections 20 and 30 describe the old slot approach. The retry-passes and rollback ideas are unchanged, but the slot is gone. Any loadout the old version created is now just a normal loadout.

**Test checklist (v0.9):**

- [ ] Single-click a build: the talent screen shows the changes as pending, and Apply Changes is lit
- [ ] Press Apply Changes: one cast, and your selected loadout now holds the build
- [ ] Single-click, then press Escape or Undo: the talents return to how they were
- [ ] Double-click a build: it applies straight away, with one cast
- [ ] With Blizzard's Starter Build selected: a clear message, and nothing changes
- [ ] After applying, action-bar keybinds still work. If you see blocked-action errors after double-clicking, note it

---

## 🔹 45. Staged vs. committed: using Blizzard's own model

Blizzard's talent system already has two layers:

- **Committed** talents are what your character actually has.
- **Staged** changes are what you've clicked but not applied yet. They live in the *active config* and are reported by `C_Traits.ConfigHasStagedChanges`.

When you click a talent node, Blizzard's own button calls `C_Traits.PurchaseRank` on the active config, which *stages* it. Apply Changes then calls `C_ClassTalents.CommitConfig(selectedLoadoutID)`. I confirmed that last detail in Blizzard's source (`CommitConfigInternal`). Our single-click does exactly what your own clicks would do, and our double-click does exactly what the Apply button does. Working *with* the platform's model, instead of around it, is why this version is shorter than the slot version. It also removed the asynchronous loadout creation, the timeout, and the renaming.

---

## 🔹 46. Why "click Blizzard's button" is the safe path: taint, again

Talent Loadout Ex's author found that applying talents from addon code can taint the talent interface, and the taint then spreads to the action bars, where keybinds fail with "blocked action" errors (WoWUIBugs #447). The root cause is subtle, and the recommended workaround is for the *addon* to stage and the *player* to press Apply Changes.

Why does that help? Taint follows **who is running the code**. When our code calls `CommitConfig`, everything that runs as a result starts in our (addon) context. When you click Blizzard's button, the same call starts in Blizzard's own secure context. Same function, different caller, different result. That's why double-click is offered as a convenience with a caveat, and single-click + Apply Changes is the recommendation.

---

## 🔹 47. Single vs. double clicks in WoW

A WoW `Button` fires `OnClick` for the first click of a double-click and `OnDoubleClick` for the second. The second click does *not* fire `OnClick`. So:

- `OnClick` → stage (the first click of any double-click stages too).
- `OnDoubleClick` → stage again, then commit. The second stage is almost free, since the talents are already in place.

There's no "wait to see if a second click comes" delay, so single clicks feel instant. That's usually the better design: make the double-click action a *continuation* of the single-click action, rather than something different that forces the single click to wait.

> **Exercise:** add an option under "..." for "Double-click applies" (on/off), for players who only ever want to use Apply Changes.

---

# Part 10: v0.10 (fixing the freeze, and difficulty tags from anywhere)

## 📌 48. What changed

- **Double-click works, and there's no freeze.** Only the talents that differ are changed, a double-click does the work once, and applying uses the same call as Talent Loadout Ex.
- **Tags can have a difficulty** (Raid Finder / Normal / Heroic / Mythic for raids; Normal / Heroic / Mythic / Mythic+ for dungeons), or "any difficulty".
- **Tag from anywhere:** right-click → **Tag ▸** lists this season's raids (whole raid plus each boss) and dungeons, each with difficulties.
- Zone-in prompts, green strips, and `/lp boss` respect your current difficulty.
- New file: `Journal.lua` (the Encounter Journal code, moved out of `IconPicker.lua` because tagging needs it too).

**Test checklist (v0.10):**

- [ ] Double-click a build: it applies (one cast), with no freeze
- [ ] Single-click a build close to your current talents: it's instant, and the talent screen shows only the few changed talents as pending
- [ ] A build with a different hero tree still works (a brief rebuild is expected)
- [ ] Out in the world, right-click → Tag → a raid → a boss → Mythic. The subtitle shows "(M)"
- [ ] Tag a dungeon "Mythic+", then enter it at the matching difficulty: you get the prompt, which names the difficulty
- [ ] A Mythic-only tag doesn't highlight or prompt on Heroic, and an "any difficulty" tag does
- [ ] Your older tags still work (they count as "any difficulty")

---

## 🔹 49. Debugging a freeze: find what's multiplied

The freeze had three causes, and each one multiplied the others:

1. **Every talent change makes Blizzard's talent window redraw.** Our old staging cleared the whole tree and re-learned everything, well over 100 changes, even when the new build differed by 3 talents.
2. **A double-click did it twice.** WoW fires `OnClick` for the first click, so the full rebuild ran, then `OnDoubleClick` ran it again.
3. **The freeze broke the double-click.** While the first rebuild froze the game, the second click waited in a queue. By the time it was handled, it no longer counted as a double-click, so it became a second single click: stage again, but never apply. That's exactly what you saw.

The fixes target each factor:

- **Do less:** `stageDifferences` changes only what differs, like a *diff and patch* instead of a full rewrite (the same idea as React's virtual DOM). In the simulated tree, a 3-talent difference now costs 5 changes instead of rebuilding everything, and an already-matching build costs zero.
- **Do it once:** a single click waits 0.3 seconds before staging, and a second click cancels that and applies instead. This time, delaying the single click is the right trade-off (unlike section 47's advice), because the single-click action is expensive and the double-click action includes it.
- **Keep a safe fallback:** when the fast path can't be used (switching hero trees) or doesn't end up exactly right, fall back to the full rebuild. Then verify the result with the fingerprints from Part 8. The fast path only has to be *usually* right, because the verification catches the rest.

---

## 🔹 50. Learning from a working implementation

Talent Loadout Ex's double-click works in practice, so I read its `import.lua` before rewriting ours. Three ideas came from it:

- **Refund and buy only the differences**, one node at a time.
- **Process nodes in tree order.** We sort by each node's vertical position: top-down for learning (prerequisites first) and bottom-up for refunding (dependents first).
- **Commit with `C_Traits.CommitConfig(activeConfigID)`.** Its author found that this avoids the taint that calling the talent window's own Lua causes. We then save into your selected loadout with `C_ClassTalents.SaveConfig` once the game confirms the commit (`TRAIT_CONFIG_UPDATED`).

Reading a mature project's source for a problem it has already solved is often faster than trial and error. You still need to understand *why* each piece exists, which is what the comments explain.

---

## 🔹 51. Designing the difficulty feature to be backward compatible

Tags used to be stored as `instances[mapID] = ref`. Difficulty tags reuse the same tables with a **composite key**, `"mapID@difficultyID"`, while a plain `mapID` means "any difficulty". So:

- **Old tags need no migration.** They're already plain IDs, and they now mean exactly what they always meant: any difficulty.
- **Lookup is two table reads:** the exact key first, then the plain key (`ns.GetTag`).
- **Removing a tag** only needs its storage key, which `GetTagsForItem` returns.

Whenever you extend saved data, look for a design where old data is already valid in the new format. It saves writing, and debugging, a migration.

**Why tagging from anywhere works:** tags need the same IDs the game reports when you're inside, and the Encounter Journal's 11th value for each instance is that map ID. I confirmed this in Blizzard's own journal code, which reads it into a variable called `mapID`. Boss tags already used journal encounter IDs, so the journal can list every boss of the season, with its ID, from anywhere.

> **Exercise:** add a **difficulty filter** to the window header (All / LFR / N / H / M / M+) that dims builds not tagged for that difficulty. (Hint: `GetTagsForItem` now returns each tag's `difficulty`.)

---

# Part 11: v0.11 (prompts that actually fire, and a tag panel)

## 📌 52. What changed

- **Zone-in prompt fixed and upgraded.** It's now our own window listing *every* build tagged for where you are (instance for this difficulty, Mythic+ when you walk into a Mythic dungeon, any-difficulty tags, and unkilled bosses). Click one to apply it, or hover to compare.
- **Tag panel** instead of nested menus: one scrollable list with a row of difficulty buttons (green / gold / gray) on every raid, boss, and dungeon.
- **`/lp why`** explains what the prompt logic sees, and **`/lp prompt`** re-shows the prompt.
- New files: `Prompt.lua` and `TagPanel.lua`.

**Test checklist (v0.11):**

- [ ] Walk into a Mythic dungeon (no key yet) in your raid build: the prompt offers both your Mythic and your M+ builds
- [ ] Click one: it applies, and the prompt closes
- [ ] Walk in already wearing one of those builds: no prompt
- [ ] Right-click → Tag... opens the panel beside the window, with no overlapping menus
- [ ] The difficulty buttons show green for this build and gold for another, the gold tooltip names the other build, and clicking toggles or replaces the tag
- [ ] If a prompt ever doesn't appear, `/lp why` inside the instance explains why

---

## 🔹 53. The bug: when "unknown" looks like "equal"

The prompt checked "do you already have this build?" one second after the loading screen. At that moment the talent data sometimes isn't loaded yet, so **both** fingerprints came out as empty strings, and `"" == ""` is true. The addon concluded you were already in the right build, stayed silent, and recorded "already handled here", so it never asked again during that visit.

This is a classic trap. An **empty or default value used to mean "not known yet"** will compare equal to other unknown values. The fixes:

- **Represent "unknown" explicitly.** An empty fingerprint now returns `nil` ("can't tell yet"), which never counts as a match and is never cached. The *cache* part matters just as much: a cached wrong answer would have kept the bug alive until you changed spec.
- **Wait and retry instead of guessing.** When any comparison says "can't tell yet", `CheckContext` tries again 2 seconds later, up to 6 times.
- **Only record "handled" after a real decision**, meaning a prompt was shown, you already have a tagged build, or nothing is tagged. Never while data is missing.

---

## 🔹 54. Knowing the game's rules: Mythic vs. Mythic+

Your M+ tag couldn't have prompted even without that bug. When you walk into a dungeon to run a key, the difficulty is **Mythic** (ID 23). It only becomes **Mythic Keystone** (ID 8) once the key starts, and then talents are locked. So a rule of "prompt when the difficulty matches the tag" can never fire for M+. The candidate list now includes the M+ tag whenever you're in a Mythic dungeon, and stops prompting once `C_ChallengeMode.IsChallengeModeActive()` is true.

When a feature "never happens", check whether the moment it's waiting for can actually occur.

---

## 🔹 55. Make the code explain itself: `/lp why`

When something *doesn't* happen, there's no error to read, and you're left guessing. `/lp why` prints each input to the decision (instance ID, difficulty ID, combat, keystone, "already asked") and each candidate's comparison result. It reuses the same `ns.GetCandidates` function the prompt uses, so it can't disagree with what the prompt actually does. Diagnostic commands like this are worth adding to any feature whose failure mode is silence.

I also tested the new logic outside the game by simulating your exact case: raid build, Mythic Ara-Kara, a Mythic tag and an M+ tag, and talent data missing for the first two checks.

---

## 🔹 56. When a UI pattern fights you, change the pattern

Four levels of nested menus (Tag ▸ Raid ▸ Boss ▸ Difficulty) opened from a window at the screen's right edge. Each submenu had to flip left, back over its parent, which is where the overlapping came from. Tweaking the menu wouldn't fix that geometry, so tagging moved to a **panel**:

- **Everything is visible at once:** every target and every difficulty, with the current state shown by **color**, instead of hidden three clicks deep.
- **One click per change:** click a difficulty button to toggle it.
- **Conflicts are visible:** a gold button tells you another build already owns that spot, and the tooltip names it.

The panel shares everything else with the rest of the addon (`ns.SetTag`, `ns.ClearTag`, `ns.GetSeason`, `ns.OnRefresh`), so it's mostly layout code. That's the payoff of keeping data logic separate from UI since Part 1.

> **Exercise:** add a "Show only tagged" checkbox to the tag panel that hides rows with no tags at all, to review your setup at a glance.

---

# Part 12: v0.12 (Mythic+ tags on every dungeon difficulty, and a sturdier prompt)

## 📌 57. What changed

- **A dungeon's M+ tag is now offered whenever you walk in, on Normal, Heroic, or Mythic.** A key can only be started from inside, and talents lock once it starts, so entering is the one moment to offer it.
- **Difficulties are classified by what they are.** If the game reports a difficulty number we don't know, `ns.NormalizeDifficulty` asks `GetDifficultyInfo` whether it's raid finder, heroic, mythic, or challenge mode.
- **The prompt can't be stopped by unrelated problems:** a UI refresh error, a journal read error, or an odd timer argument.
- If you already have a tagged build when you walk in, chat says so, so a missing prompt is never a mystery.

**Test checklist (v0.12):**

- [ ] Tag a dungeon **M+** only, then walk in on Normal, Heroic, or Mythic: you're offered the M+ build
- [ ] With both a Mythic and an M+ tag, walk in on Mythic: both are offered, Mythic first
- [ ] Walk in already wearing the M+ build: no prompt, and a chat line saying you already have it
- [ ] If there's still no prompt, run `/lp why` and check the "game difficulty ID → treated as" line

---

## 🔹 58. Designing around the player's real moment

Tags were designed as "match this difficulty". That's the right model for raids, where you choose a difficulty and then play it. For keys, the difficulty you *play* (Mythic Keystone) is never the difficulty you're in when talents *can* change. So the M+ tag is really a different kind of rule: "offer this whenever I enter the dungeon". It's the same data, but the matching rule depends on what the player is actually doing. When a feature keeps "not working", step back and ask whether the model matches how the activity really happens.

---

## 🔹 59. Defense in depth for a feature that fails silently

A prompt that doesn't appear gives you no error to read. So every step that could quietly stop it now fails *loudly or not at all*:

| Risk | Defense |
|---|---|
| A difficulty number we don't know | Classify it through `GetDifficultyInfo` instead of failing to match |
| An error in *any* UI refresh stops `ns.Notify()`, and with it the zone-in check | `ns.Notify` runs each refresher in `pcall` and reports errors through `geterrorhandler` |
| Reading the boss list errors | `pcall`, and still offer the instance's own builds |
| A timer or event passes an unexpected argument | `CheckContext` only accepts a real number for `attempt`, and timers call it through a small wrapper function |
| "Already have it" looks like "nothing happened" | A chat line says which build you already have |

The `Notify` fix affects the whole addon: one buggy UI piece can no longer take down unrelated features that just wanted to announce a change. Isolating failures like this is the same idea as React's error boundaries.

**Tested outside the game** against the real `Core.lua`, `Journal.lua`, and `Context.lua`: every dungeon difficulty, an unfamiliar difficulty number, a running key, a deliberately broken UI refresh, a timer that passes a table, and the full zone-in event path (no repeat within a visit, and a fresh prompt after leaving and returning).

> **Exercise:** add a "Remind me" option to the prompt that re-shows it 30 seconds later instead of dismissing it.

---

# Part 13: v0.13 (tagged in another spec? say so, and offer to switch)

## 📌 60. What changed

- **Spec-mismatch prompt:** if the place you enter has nothing tagged for your current spec but another spec has builds here, a window says "*Place* is tagged for another spec" with a **Switch to *Spec*** button per spec. After switching, the normal build prompt follows.
- **Tags are found by any of the instance's IDs, or by name.** That's the game's ID, the Encounter Journal's ID (these can differ), or the place name saved on the tag.
- **`/lp why`** lists the IDs it checks, your spec's tags *with place names*, and other specs' matches.

**Test checklist (v0.13):**

- [ ] Enter a place tagged only in another spec: the "tagged for another spec" window appears
- [ ] Click Switch to *Spec*: the spec changes, and the build prompt for that spec follows
- [ ] Hover a switch button: its tooltip lists the builds tagged there
- [ ] `/lp why` in Murder Row now shows place names next to each tag

---

## 🔹 61. Reading your own diagnostic output

Your `/lp why` output answered the question on its own. It reported that you were in instance **2813**, and that the tags in your spec were on **3004, 3029, and 2987**. The prompt code was working, but the tags you expected just weren't there *for this spec*. That's exactly why diagnostic commands print raw values: they change a vague "it doesn't work" into a precise "these two numbers don't match".

The output also showed a weakness in the diagnostic itself: bare ID numbers are hard for a person to recognize. So `/lp why` now prints each tag's **place name**, and says outright when another spec has builds tagged here. A diagnostic is also a user interface, and it's worth polishing like one.

---

## 🔹 62. Matching one thing that has several IDs

An instance can be known by more than one number. `GetInstanceInfo()` reports one, and the Encounter Journal (where tags from the tag panel come from) reports its own. They usually agree, but that's not guaranteed. Rather than betting on one, `GetCurrentInstance` now collects a **set** of IDs (`instance.ids`), and `instanceTagsIn` accepts a tag if its ID is in that set, **or** if its saved name matches the instance's name.

Two details are worth noticing:

- **Parsing the storage keys:** tag keys are either `2813` or `"2813@23"`. One Lua pattern, `^(%d+)@?(%d*)$`, splits both forms into ID and difficulty (`@?` means "an optional @").
- **Several matching rules, most specific first:** exact ID, then journal ID, then name. The name check is a safety net, not the primary rule.

---

## 🔹 63. Tags per spec: the rule, and making it visible

Tags live *per spec* on purpose. A Balance build is useless to a Feral druid. But a rule the player can't see feels like a bug. The fix wasn't to change the rule, but to **surface it at the moment it matters**: when you enter a place whose builds belong to another spec, the prompt explains the situation and offers the fix (switching spec) in one click. `ns.GetCandidates` now takes an optional spec table, so the same matching logic serves both your current spec and the check of your other specs. For other specs it only reads the saved tag, because Blizzard loadouts can only be looked up for the spec you're in.

Switching spec from the prompt uses the same `ns.SwitchSpec` as the header buttons, and `PLAYER_SPECIALIZATION_CHANGED` clears the "already asked" memory and re-runs the check after a moment, so the build prompt follows automatically.

> **Exercise:** show a small spec icon next to tags in the list rows' subtitles when a build is tagged in more than one spec.

---

# Part 14: v0.14 ("All dungeons" and "All raids" tags)

## 📌 64. What changed

The tag panel starts with an **All instances** section: **All dungeons** and **All raids**, each with the usual difficulty buttons. **All dungeons → M** offers that build whenever you enter *any* dungeon on Mythic. **All dungeons → M+** offers it whenever you enter any dungeon before a key starts. A tag on a specific place always outranks these general ones.

**Test checklist (v0.14):**

- [ ] Tag a build **All dungeons → M**, then enter a dungeon on Mythic: it's offered
- [ ] Enter a dungeon on Heroic: it isn't offered
- [ ] Give one dungeon its own Mythic tag: in that dungeon, its build is listed first and the general one second
- [ ] The row's subtitle shows "All dungeons (M)"

---

## 🔹 65. Adding a new kind of tag without breaking old data

Tags already had two kinds, `instances` and `bosses`. This adds a third, `categories`, keyed by the same strings the game uses for instance types (`"party"`, `"raid"`). That makes matching a lookup on `GetInstanceInfo()`'s own answer, with no translation table. Old saved data has no `categories` table, so `ns.GetSpecData` creates it on first use (`spec.categories = spec.categories or {}`). It's the same "old data is already valid" approach as difficulty keys in Part 10. Everything else (tag keys with `@difficulty`, labels, the tag panel's buttons, removal, the prompt) worked unchanged, because it was written against "a kind of tag" rather than against instances and bosses specifically.

> **Exercise:** add **Current season dungeons** as a category, which matches only dungeons listed in `ns.GetSeason().dungeons` (compare map IDs), so old dungeons in Timewalking don't trigger your Mythic+ build.

---

# Part 15: v0.15 (Top builds, and Archon by hand)

## 📌 66. What changed

- **Top builds panel** (header button, or `/lp top`): the most-played build for your spec on each of this season's dungeons and raid bosses, with tabs per difficulty. Click to stage, double-click to apply, hover to compare, and right-click to **save and tag** in one step.
- **Archon button on every row:** the exact archon.gg link for your spec and that place, plus a paste box that saves and tags whatever you copy from Archon.
- New files: `TopBuilds.lua` and `Archon.lua`. The single/double-click logic moved into a shared helper, `ns.HandleBuildClick` in `Import.lua`, so both lists behave identically.
- The TOC gained `## OptionalDeps: ArchonTalentsData, PeaversTalentsData`, so a data addon loads before us when it's installed.

**Test checklist (v0.15):**

- [ ] Without a data addon: Top builds lists every dungeon and boss with an Archon button, and says how to get build data
- [ ] Install **ArchonTalentsData** and `/reload`: rows show "Top build", with a source line and update date
- [ ] Hover a row: the comparison tooltip appears. Click, then double-click: stage, then apply
- [ ] Right-click → Save and tag: the build appears under "Top builds: Mythic+" (or the difficulty), and the tag panel shows it green
- [ ] Archon button: the link copies with Ctrl+C and **opens the right page in your browser**, and pasting a string then Save and tag works
- [ ] Walk into a place you tagged this way: the zone-in prompt offers it

---

## 🔹 67. Checking whether a feature is *allowed* before building it

The first question for "pull builds from Archon" wasn't *how*, but *whether*. Research turned up three facts, each from a primary source:

1. **Addons can't reach the internet**, so any outside data must be shipped as another addon's Lua tables.
2. **The data addons have already dropped Archon.** ArchonTalentsData's readme explains that on 2026-08-27 archon.gg started answering automated requests with a "Human Verification" page, and that its operator had asked an addon author to stop using their data. My own test request got a `403`.
3. **parses.gg explicitly allows reuse** ("free for anyone to read, download whole, or build against").

A verification wall is a deliberate access control, and getting around it would be both against the site's wishes and fragile. So the design splits into what's allowed:

- **Automated data:** parses.gg, through a data addon that's allowed to ship it.
- **Archon:** a human visits the page, and the addon makes that fast. It supplies the exact link and turns one paste into a saved, tagged build.

That's a pattern worth remembering: when you can't automate a step, **automate everything around it** and leave only the part that must be human.

---

## 🔹 68. Integrating with another addon through a shared interface

TalentLoadoutsEx reads build data from a global named `PeaversTalentsData`. ArchonTalentsData deliberately registers under that *same* name so existing consumers keep working. The global name is the **contract**, not the brand. LoadoutPlanner uses the same contract:

- **Feature detection, not addon names:** `dataAPI()` checks that `_G.PeaversTalentsData.API.GetBuilds` is a function. Any addon that provides it works, with no list of approved addons.
- **Distrust the data:** every build must be in a known category, and its talent string must *look* like a code (base64 characters, long enough). An older data addon shipped `"No data on wowcompare.io - Coming soon!"` as a talent string. The check drops that instead of trying to import it.
- **`pcall` around the call:** another addon's bug shouldn't break our panel.
- **`OptionalDeps`:** tells the game to load the data addon first *if it's installed*, without requiring it.

---

## 🔹 69. Joining two datasets by name

The data addon labels builds by English name ("Nek'zali the Soulcoiler"). Our tags need journal IDs. There's no shared ID, so `buildRows` joins the two on a **normalized name**: lowercase, with everything that isn't a letter or digit removed, so punctuation and spacing differences don't matter.

The join is built as a *left join* from the journal's side. Every dungeon and boss this season gets a row, with or without a build, so the Archon button is always there. Then any data builds that didn't match (for example on a non-English client) are appended at the end: still usable, just not taggable. Nothing is silently dropped.

**Testing against the real thing:** for this version I loaded ArchonTalentsData's *actual* data files and API into plain Lua next to our real files, and checked every tab. All 8 dungeons and 9 bosses matched. On Mythic, only the bosses with logged kills had builds, which is correct this early in a tier. The Archon links came out identical to the URLs ArchonTalentsData's own scraper used to build.

> **Exercise:** in the zone-in prompt, when a place has *no* tags at all, offer its Top build as a suggestion ("Most-played here: ..."). (Hint: `ns.GetTopBuilds(specID)` plus the same name matching as `buildRows`.)

---

# Part 16: v0.16 (your own data pipeline: Raider.IO → Node.js → the game)

## 📌 70. What changed

- **New companion project: LoadoutPlannerSync** (Node.js, no dependencies). It reads the official Raider.IO API and writes a data addon, **LoadoutPlannerData**.
- **Top builds** has a **source toggle** (Raider.IO / parses.gg). Raider.IO rows show popularity ("72% of 40 players") and **runner-up builds**.
- `TopBuilds.lua` now reads both sources into one shape, so the rest of the panel didn't change.

**Test checklist (v0.16):**

- [ ] Run `npm test` in LoadoutPlannerSync: 11 passing tests
- [ ] Set up `config.json` with your key and AddOns path, then `npm run sync`. It finishes with "Builds for N specs written to ...AddOns\LoadoutPlannerData"
- [ ] `/reload`, then Top builds → **Raider.IO**: rows show "*N*% of *M* players", and the header says "Synced today"
- [ ] Right-click a row → Other popular builds → #2 → Put on talent screen
- [ ] Switch to **parses.gg** and back: your choice is remembered after `/reload`

---

## 🔹 71. The architecture: why two programs

```
 Raider.IO API ──HTTPS──▶ LoadoutPlannerSync (Node, on your PC)
                                  │ writes Lua
                                  ▼
                 AddOns/LoadoutPlannerData/Data.lua
                                  │ loaded by the game on /reload
                                  ▼
                 LoadoutPlanner (reads the global LoadoutPlannerData)
```

WoW addons run in a sandbox with **no network access**. That's deliberate on Blizzard's part. So anything from the internet has to be fetched *outside* the game and handed over as files. The file format is the contract between the two programs: a Lua table with a documented shape (see the top of `TopBuilds.lua`). Either side can change freely as long as that shape holds. That's the same idea as a REST API contract between a frontend and a backend.

Writing the data as a **separate addon** rather than into LoadoutPlanner's folder means the sync program can replace its whole folder safely, and LoadoutPlanner's own files are never touched.

---

## 🔹 72. Finding the real API shape before writing code

Raider.IO's docs page renders with JavaScript, so it came back empty. Instead of guessing field names, I read an open-source Go client's **recorded API responses** (its test fixtures). They showed two things that shaped the whole design:

- Mythic+ **leaderboard** responses already include each roster member's `loadout`. So one request covers ~20 runs for *every* spec, with no per-player lookups needed.
- `/guilds/boss-kill` rosters include `talentLoadout.loadoutText` for each raider.

Reading real responses also caught a trap: in one fixture a Death Knight's `loadout` was actually a *Mage's* string. Real data can be wrong, so the program checks the spec encoded in each string against the player's spec, and skips mismatches.

---

## 🔹 73. Reading talent strings in JavaScript

`talentString.js` reimplements the game's decoder. I confirmed the details in Blizzard's own `ExportUtil.lua`:

- Each base64 character holds **6 bits**, read **least significant bit first**. Values are assembled **little-endian**: the first bit read is worth 1, the next 2, then 4...
- The header is 8 bits of version, 16 of spec ID, and 128 of tree hash.

Why decode at all? **Grouping.** Two players with identical talents can have different strings if they exported on different patches, because the tree hash differs. The program groups by the talent bits *after* the header, and shows each group's most common exact string. Without that, one popular build could be split into several smaller ones and lose its top spot.

The test helper `makeCode` is the exact **inverse** (an encoder). Writing the inverse is a great way to test a decoder: build a string with known contents, decode it, and compare.

---

## 🔹 74. Counting fairly

"Most-played" sounds simple, but the naive count is biased. Top players appear in *many* top runs, so counting appearances would let a handful of people decide the answer. `aggregate.js` gives **one vote per player per dungeon or boss** (their highest-ranked run, which comes first in the leaderboard). It publishes a build only if at least `minSamples` players are behind it, and always shows the sample size, so "100% of 2 players" never masquerades as a strong signal.

---

## 🔹 75. Being a good API citizen

`raiderio.js` enforces the manners in code rather than relying on you remembering them:

| Practice | How |
|---|---|
| Official endpoints only | Only `/api/v1/...`. An access key is rejected by the site's unofficial endpoints anyway. |
| Slow and steady | `throttle()` spaces requests `requestDelayMs` apart (default 1 s), one at a time. |
| Back off when asked | On 429 or 5xx, wait, using the server's `Retry-After` if it sends one, otherwise exponential backoff (5 s, 10 s, 20 s...). |
| Don't re-download | A disk cache keyed by the URL *without* the key, with a freshness window (`cacheHours`). |
| Keep secrets secret | The key is appended only at request time, so it never appears in logs, errors, or cache file names. `config.json` is in `.gitignore`. |
| Fail softly | A 404 for one guild's kill returns `null` and the run continues. A 401 stops with a message pointing at the API key. |

**Atomic writes:** `writeAddon.js` writes into a temporary folder, then renames it into place, so the game can never load a half-written file, even if you `/reload` mid-sync. It's the same technique databases use.

---

## 🔹 76. Testing without the network

The real API wasn't reachable from where I built this, and tests that hit a live API are slow and flaky anyway. So:

- **Dependency injection:** `RaiderIO` takes an optional `fetch`, and `run()` takes `fetchImpl` and `now`. Tests pass a fake `fetch` that answers from a routing function, and a fixed date so "the current season" is predictable.
- **Unit tests** (`node --test`, built into Node) cover retries, caching, spec mismatches, one-vote-per-player, grouping across patches, and minimum samples.
- **An end-to-end run:** a tiny local HTTP server that imitates Raider.IO, with the *real* CLI pointed at it through `baseURL`. That exercised real `fetch`, config loading, the AddOns path check, and file writing, and the generated `Data.lua` was then loaded by the *real* LoadoutPlanner code in the Lua test harness.

> **Exercise:** add a `--spec 102` option that only writes one spec's data, to make syncs smaller. (Hint: filter in `aggregate()`, and note that the leaderboard requests don't get cheaper, since each one returns every spec.)

> **Exercise:** the Raider.IO leaderboard can be filtered by region. Add a `regions` array to the config and merge the samples, so you can compare "world" with "us" only.

---

# Part 17: v0.17 (builds for everyone, with no setup)

## 📌 77. What changed

- **Builds are built into the addon** (`Data/Builtin.lua`). Players install LoadoutPlanner and Top builds just works.
- **A GitHub Action refreshes them daily** and publishes a new release to GitHub, CurseForge and Wago, but only when the builds changed.
- The project is now a **repository**: the addon at the top level, the sync tool in `tools/sync`, the workflows in `.github/workflows`, and packaging rules in `.pkgmeta`. See **PUBLISHING.md** for the setup steps.

---

## 🔹 78. The shape of a release pipeline

```
 every morning (cron)                      you push a tag (v0.18.0)
        │                                            │
        ▼                                            ▼
 Daily builds workflow                        Release workflow
   test the sync tool                             │
   fetch builds → Data/Builtin.lua                │
   check it loads (luac5.1)                       │
   changed? ── no ──▶ stop                        │
        │ yes                                     │
   commit + annotated tag v0.17.0.YYYYMMDD        │
        ▼                                         ▼
          BigWigs packager: zip (per .pkgmeta), fill in @project-version@,
          write a changelog, upload to GitHub Releases / CurseForge / Wago
```

A few decisions worth understanding:

- **Why the daily job packages the release itself:** tags pushed by a workflow's own `GITHUB_TOKEN` deliberately **don't trigger other workflows** (GitHub does this to prevent infinite loops). So the daily job can't rely on `release.yml` reacting to its tag, and runs the packager as its own last step.
- **Change detection with a content hash:** the data file contains a timestamp, so it's "different" every day. The sync writes a hash of *just the builds* into the file's header and leaves the file alone when the hash matches, so `git diff --quiet` tells the workflow whether there's anything to publish. No pointless daily releases.
- **Fail loudly, keep the last good data:** if parses.gg is down, the sync exits with an error instead of writing an empty file. The job goes red (and GitHub emails you), and players keep yesterday's builds. A silent success that ships nothing would be much worse.
- **Tests run before every publish:** the workflow runs `npm test` and `luac5.1 -p` on the generated file first. A broken change to the sync tool can't reach players.
- **Secrets vs. variables:** tokens (`CF_API_KEY`, `WAGO_API_TOKEN`, `RAIDERIO_API_KEY`) are *secrets*: hidden, and masked in logs. Project IDs and switches (`CURSEFORGE_PROJECT_ID`, `INCLUDE_RAIDERIO`) are *variables*: visible settings. Configuring through the repository instead of editing files means a fork, or a future you, can change them without touching code.
- **`@project-version@`:** the TOC's Version line is a placeholder that the packager replaces with the tag, so the version number lives in exactly one place: the git tag.

## 🔹 79. Rehearsing CI locally

A workflow you can only test by pushing is slow to debug. Before handing this over I:

1. **Linted** both workflows with `actionlint`, which catches YAML, expression, and shell mistakes.
2. **Rehearsed the shell steps** against a local bare git repository standing in for GitHub: new builds (commit + tag), identical builds (no release), and a second change the same day (a time suffix on the tag).
3. **Ran the real packager** (`release.sh -d`, which skips uploads) on the tagged commit. That confirmed the zip leaves out `tools/`, `LEARNING.md`, `PUBLISHING.md` and `VERSION`, and that the TOC version was filled in.
4. **Ran the sync with no network**, which confirmed it refuses to write an empty bundle.

The only parts left untested are the ones that need your accounts: the actual uploads.

> **Exercise:** add a third workflow, `ci.yml`, that runs `npm test` and `luac5.1 -p` on every file whenever you push to `main`, so mistakes show up before you tag a release.

---

# Part 18: v0.18 (looking like part of the game)

## 📌 80. What changed

Every window now uses the talent window's own parts instead of the generic dark tooltip-style box:

| Before | Now | Where Blizzard uses it |
|---|---|---|
| Dark dialog background + thin border | `DefaultPanelFlatTemplate` (metal border, title bar) | Most modern Blizzard panels |
| Plain dark background | Your spec's talent painting, darkened | The talent window's tree |
| Classic scroll bar with arrows | `MinimalScrollBar` | The loadout and PvP talent lists |
| Blue quest-log hover | `talents-pvpflyout-rowhighlight` | Hovering a PvP talent |
| Square icon | `talents-node-pvpflyout-green` / `-yellow` ring | PvP talent icons |
| +/- buttons on groups | `friendslist-categorybutton-arrow-right` / `-down` | Friends list categories |
| Checkbox tick | `common-icon-checkmark` | Talent loadout dropdown |

All of it lives in one new file, **Style.lua**, loaded right after Core.lua so every window can use it.

---

## 🔹 81. Templates and atlases

Two ways to reuse Blizzard's art:

- A **template** is a ready-made frame defined in Blizzard's XML. `CreateFrame("Frame", name, parent, "DefaultPanelFlatTemplate")` gives you the border, background and a title string (`frame.TitleContainer.TitleText`) in one line. Templates can come with **child keys** like that, which is how you find their parts.
- An **atlas** is a named region of a big texture sheet. `texture:SetAtlas("talents-node-pvpflyout-green")` picks one picture out of the sheet by name, with no file paths or coordinates.

How I found the names: Blizzard's UI source is public (the `wow-ui-source` mirror on GitHub). I read the talent window's XML to see which templates and atlases **it** uses, then checked every name against `AtlasInfo.lua`, the list of every atlas in the game. Several names I expected (like `Options_ListExpand_Down`) turned out not to exist, which is exactly why checking matters.

---

## 🔹 82. Failing soft

Blizzard renames art between patches. If `SetAtlas` gets a name that doesn't exist, the texture just shows nothing, and a missing template makes `CreateFrame` throw an error. So every helper in Style.lua checks first and has a fallback:

```lua
function Style.SetAtlas(texture, atlas, fallback)
    if atlasExists(atlas) then   -- C_Texture.GetAtlasInfo(atlas) ~= nil
        texture:SetAtlas(atlas)
        return true
    end
    if fallback then fallback(texture) end
    return false
end
```

and templates are tried with `pcall(CreateFrame, ...)`, falling back to the old look. Worst case after a patch: the addon looks plainer. It never stops working.

I tested three ways: with everything present, with the modern pieces missing (fallback scroll bars and borders), and with no atlases at all.

---

## 🔹 83. Borrowing the spec painting

The talent window shows a 1612×774 painting for your spec. We read which one with `PlayerSpellsFrame.TalentsFrame.Background:GetAtlas()`, so it's always the right spec, including new ones, with no table of names to maintain.

Our window is tall and narrow, so stretching the whole painting would squash it. Instead we look up the atlas's position on its sheet (`C_Texture.GetAtlasInfo`) and show only a **slice** of the same shape as our window, from the middle:

```lua
local fraction = math.min(1, (w / h) / (info.width / info.height))
local span = (right - left) * fraction          -- how much of the width to show
local start = left + ((right - left) - span) / 2  -- centred
texture:SetTexture(info.file)
texture:SetTexCoord(start, start + span, top, bottom)
```

`SetTexCoord` picks a rectangle of a texture using 0-to-1 coordinates. We use the sheet's file directly, because texture coordinates on top of an atlas are unreliable. A dark gradient on top keeps the text readable.

> **Exercise:** add a slider to the options menu that controls how dark the painting is (the `SetVertexColor` values in `Style.AddSpecArt`).

---

# Part 19: v0.18.1 (tests that live in the repo)

## 📌 84. What changed

- **Top builds opens on a source that has data.** If your saved choice was Raider.IO (which isn't included yet), the panel used to open on an empty page. Now it falls back to parses.gg, and remembers your choice for when Raider.IO arrives. Clicking Raider.IO yourself still shows why it's empty.
- **The tests moved into the repo** (`tools/test/`) and **GitHub runs them**: on every push (`ci.yml`, a new "Checks" workflow), and before every release. A failing test stops the release before anything is uploaded.
- **CLAUDE.md**: notes that Claude Code reads automatically when you work on the repo in VS Code: the project's rules, layout, tests and release steps.

---

## 🔹 85. Testing an addon without the game

WoW addons normally only run inside WoW. But a Lua file is just Lua: what it needs from the game is a set of **globals** (`CreateFrame`, `C_Traits`, `UIParent`...). Provide fake versions of those, and the real addon files load and run in plain Lua. That's `tools/test/wow.lua`.

The main trick keeps the fake small. Every fake frame answers **any** capitalized method call, and does nothing:

```lua
setmetatable(o, { __index = function(_, k)
    if not k:match("^%u") then return nil end   -- fields stay nil
    return function(self, ...) ... end           -- SetPoint, SetAtlas, ...: accepted
end })
```

`__index` is the function Lua calls when a key is missing from a table, so `frame:SetPoint(...)` finds a do-nothing function without us listing all 200 frame methods. Only the few that must *behave* (Show/Hide firing OnShow, SetText remembering its text, SetScript storing handlers) have real code.

What these tests can and can't tell you:

| Catches | Can't catch |
|---|---|
| Typos and syntax errors | Anything visual: layout, overlap, art |
| A file using something defined later in the TOC | Real API behavior (the fakes return what we tell them) |
| Logic errors (wrong source chosen, missing rows) | Taint, combat restrictions |
| Crashes when Blizzard art or templates are missing | |

So tests and in-game checks complement each other. Tests catch mistakes in seconds, every time. The game catches what only the game can show.

---

## 🔹 86. A test must be able to fail

My first version of the new Top builds test **passed even with the bug put back in**. It checked that the header mentioned "parses.gg", but the Raider.IO message says "…Or use parses.gg." too. The test could never fail.

The habit that caught it: after writing a test for a fix, **undo the fix and run the test again**. If it still passes, it isn't testing anything. The fixed test now looks for "Most-played builds from parses.gg", which only the real header contains.

---

## 🔹 87. Continuous integration (CI)

`ci.yml` is the exercise from section 79, done:

```yaml
on:
  push:
    branches: ['**']
    paths-ignore: ['Data/Builtin.lua']   # the daily job tests its own commits
```

Every push runs the addon tests and the sync tool's tests on a fresh Linux machine. The result shows as a ✓ or ✗ next to the commit on GitHub. `release.yml` runs the same tests **before** the packager, so a red test means no release. That's the safety net that lets you ship quickly.

> **Exercise:** add a test to `test_load.lua` that runs `/lp toggle` twice and checks the window is shown again afterwards. Then break `ns.SetWindowCollapsed` on purpose and make sure your test fails.

