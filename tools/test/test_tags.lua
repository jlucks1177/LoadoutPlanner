-- test_tags.lua
-- The Encounter Journal reading (boss lists, pages you can't enter) and
-- which tagged builds the zone-in prompt offers where you are.

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
wow.install({ modern = true })
print("Tags and zone-in prompt test")

------------------------------------------------------------------------
-- A fake Encounter Journal for "Current Season"
------------------------------------------------------------------------
-- Like the real one, it only lists a raid's bosses once that raid has
-- been SELECTED (the cause of the missing boss icons).
local JOURNAL = {
    raids = {
        { id = 1, name = "Midnight", showsDifficulty = false, mapID = 0, bosses = { "World Boss" } }, -- world bosses page
        { id = 2, name = "The Venomous Abyss", showsDifficulty = true, mapID = 3100,
            bosses = { "Nymrissa Wavecaller", "Sszorak" } },
    },
    dungeons = {
        { id = 11, name = "Murder Row", showsDifficulty = true, mapID = 2813, bosses = { "Boss A" } },
        -- The overview page, looking like a real dungeon (difficulty menu, a map,
        -- a boss) as it can in game: only its name gives it away.
        { id = 12, name = "Keystone Dungeons", showsDifficulty = true, mapID = 9999, bosses = { "Boss K" } },
    },
}
local selected
EJ_GetNumTiers = function() return 5 end
EJ_GetCurrentTier = function() return 3 end
EJ_SelectTier = function() end
EJ_GetTierInfo = function() return "Current Season" end
EJ_SelectInstance = function(id) selected = id end
EJ_GetInstanceByIndex = function(i, isRaid)
    local e = (isRaid and JOURNAL.raids or JOURNAL.dungeons)[i]
    if not e then return nil end
    return e.id, e.name, "", "", "button", "", "small", 0, "", e.showsDifficulty, e.mapID
end
local byID = {}
for _, list in pairs(JOURNAL) do for _, e in ipairs(list) do byID[e.id] = e end end
EJ_GetEncounterInfoByIndex = function(index, instanceID)
    if selected ~= instanceID then return nil end -- not selected: nothing
    local name = byID[instanceID].bosses[index]
    if name then return name, "", instanceID * 100 + index end
end
EJ_GetCreatureInfo = function() return nil, nil, nil, nil, 12345 end

------------------------------------------------------------------------
-- Load the addon
------------------------------------------------------------------------
local ns = {}
for _, file in ipairs(wow.tocFiles()) do wow.loadAddonFile(file, ns) end
local dispatcher
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then dispatcher = o break end
end
dispatcher.scripts.OnEvent(dispatcher, "ADDON_LOADED", "LoadoutPlanner")

-- Two custom builds for this spec (Balance, 102).
ns.SaveBuild({ name = "M+ build", code = "AAAA", specID = 102 }, "Dungeons")
ns.SaveBuild({ name = "Raid build", code = "BBBB", specID = 102 }, "Raids")
local mplus, raid = ns.GetGroups()[1].builds[1], ns.GetGroups()[2].builds[1]
local mplusItem, raidItem = ns.ItemFromBuild(mplus), ns.ItemFromBuild(raid)

-- A build that isn't in the library (a Top builds row) has no id.
local ok, item = pcall(ns.ItemFromBuild, { code = "CCCC", specID = 102, name = "Top" })
wow.check(ok and item.key == "t:CCCC", "a build without an id still becomes an item (Top builds rows)")

------------------------------------------------------------------------
-- 1. Reading the journal
------------------------------------------------------------------------
local season = ns.GetSeason(true)
wow.check(#season.raids == 1 and season.raids[1].name == "The Venomous Abyss",
    "the world bosses page isn't listed as a raid")
wow.check(#season.raids[1].bosses == 2, "raid bosses are listed (the raid is selected before reading them)")
wow.check(season.raids[1].bosses[1].icon ~= nil, "bosses get an icon")
wow.check(#season.dungeons == 1 and season.dungeons[1].name == "Murder Row",
    "the \"Keystone Dungeons\" page isn't listed as a dungeon")
wow.check(#season.skipped == 2, "both pages are reported as left out")

------------------------------------------------------------------------
-- 2. Old tags on "Keystone Dungeons" move to "All dungeons"
------------------------------------------------------------------------
local spec = ns.GetSpecData()
ns.GetSpecData = function() return spec end
spec.instances["9999@23"] = { buildID = mplus.id, name = mplus.name, label = "Keystone Dungeons", difficulty = 23 }
spec.instances["9999@8"] = { buildID = mplus.id, name = mplus.name, label = "Keystone Dungeons", difficulty = 8 }
ns.GetSeason(true)
wow.check(spec.instances["9999@23"] == nil and spec.instances["9999@8"] == nil,
    "tags on the Keystone Dungeons page are removed")
wow.check(spec.categories["party@23"] and spec.categories["party@8"]
    and spec.categories["party@8"].label == "All dungeons",
    "and become All dungeons tags with the same difficulties")

-- At login, before the journal is read: a tag LABELLED Keystone Dungeons
-- (under any ID) is moved on its name alone.
spec.categories["party@2"] = nil
spec.instances["4242@2"] = { buildID = mplus.id, name = mplus.name, label = "Keystone Dungeons", difficulty = 2 }
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then o.scripts.OnEvent(o, "PLAYER_LOGIN") break end
end
wow.check(spec.instances["4242@2"] == nil and spec.categories["party@2"] ~= nil,
    "at login, a Keystone Dungeons tag moves to All dungeons without reading the journal")

------------------------------------------------------------------------
-- 3. Which builds are offered where
------------------------------------------------------------------------
local function candidatesIn(name, instanceType, difficultyID, instanceID)
    GetInstanceInfo = function() return name, instanceType, difficultyID, "", 5, 0, false, instanceID end
    local names = {}
    for _, c in ipairs(ns.GetCandidates(ns.GetCurrentInstance(), false)) do
        names[c.item.name] = true
    end
    return names
end

-- Heroic Murder Row: the All dungeons tags are Mythic and Mythic+ only,
-- but being in any dungeon is enough now.
wow.check(candidatesIn("Murder Row", "party", 2, 2813)["M+ build"],
    "in a dungeon, a build tagged for another dungeon difficulty is offered")

-- Only a Heroic tag on this dungeon; you're in Mythic.
spec.categories = {}
spec.instances = { ["2813@2"] = { buildID = mplus.id, name = mplus.name, label = "Murder Row", difficulty = 2 } }
wow.check(candidatesIn("Murder Row", "party", 23, 2813)["M+ build"],
    "a dungeon's own tag works on any difficulty")

-- Raids stay strict: a Mythic raid tag isn't offered on Normal.
spec.instances = { ["3100@16"] = { buildID = raid.id, name = raid.name, label = "The Venomous Abyss", difficulty = 16 } }
wow.check(not candidatesIn("The Venomous Abyss", "raid", 14, 3100)["Raid build"],
    "a Mythic raid tag isn't offered on Normal")
wow.check(candidatesIn("The Venomous Abyss", "raid", 16, 3100)["Raid build"],
    "but is offered on Mythic")

------------------------------------------------------------------------
-- 4. Ring colours: gold = the build you're using, grey = the rest
------------------------------------------------------------------------
local ring = ns.Style.AddIconBorder(wow.newObj(), wow.newObj())
local atlas
ring.SetAtlas = function(_, a) atlas = a end
ns.Style.SetIconActive(ring, true)
wow.check(atlas == "talents-node-pvpflyout-yellow", "active build: gold ring")
ns.Style.SetIconActive(ring, false)
wow.check(atlas == "talents-node-square-gray", "other builds: grey square")

------------------------------------------------------------------------
-- 5. Blizzard loadouts are the slots; custom builds fill the active one
------------------------------------------------------------------------
-- Clicking the selected Blizzard loadout when your talents differ from
-- it: the game may answer "no changes necessary", so the addon puts that
-- loadout's talents back itself.
C_ClassTalents.LoadConfig = function() return Enum.LoadConfigResult.NoChangesNecessary end
C_ClassTalents.UpdateLastSelectedSavedConfigID = function() end
C_Traits.GenerateImportString = function(configID) return "LOADOUT" .. configID end
local realMatches, realApply = ns.ItemMatchesCurrent, ns.ApplyBuild
local applied
ns.ItemMatchesCurrent = function() return false end
ns.ApplyBuild = function(build) applied = build end
ns.LoadLoadout(11, "Raid")
wow.check(applied and applied.code == "LOADOUT11" and applied.name == "Raid",
    "clicking the selected Blizzard loadout restores its talents when they differ")
applied = nil
ns.ItemMatchesCurrent = function() return true end
ns.LoadLoadout(11, "Raid")
wow.check(applied == nil, "and does nothing when you already have them")
ns.ItemMatchesCurrent, ns.ApplyBuild = realMatches, realApply

-- With the talent window loaded, switching goes through Blizzard's own
-- loader (the same path as its dropdown), not the raw API.
local talents = PlayerSpellsFrame.TalentsFrame
local rawLoads, predicate = 0, nil
C_ClassTalents.LoadConfig = function() rawLoads = rawLoads + 1 return Enum.LoadConfigResult.LoadInProgress end
talents.configIDs, talents.variablesLoaded = { 11, 12 }, true
talents.LoadConfigByPredicate = function(_, fn) predicate = fn end
talents.IsCommitInProgress = function() return true end
ns.LoadLoadout(12, "M+")
wow.check(predicate and predicate(2, 12) and not predicate(1, 11) and rawLoads == 0,
    "clicking a Blizzard loadout uses Blizzard's dropdown loader for that loadout")
talents.configIDs, talents.variablesLoaded = nil, nil

-- Applying a custom build saves it INTO your active Blizzard loadout.
local importSource = assert(io.open("Import.lua")):read("*a")
wow.check(importSource:find("C_ClassTalents.SaveConfig", 1, true) ~= nil,
    "applying a build saves into the selected Blizzard loadout")

------------------------------------------------------------------------
-- 6. Prompts only use the spec you're in
------------------------------------------------------------------------
-- Your DPS spec (103) has a raid build tagged; you're in the raid as
-- another spec with nothing tagged: no prompt about the DPS spec's build.
ns.db.specs[103] = { instances = { ["3100"] = { buildID = raid.id, name = raid.name, label = "The Venomous Abyss" } },
    bosses = {}, categories = {} }
spec.instances, spec.categories, spec.bosses = {}, {}, {}
GetInstanceInfo = function() return "The Venomous Abyss", "raid", 15, "", 20, 0, false, 3100 end
local specPrompted, zonePrompted = false, false
ns.ShowSpecPrompt = function() specPrompted = true end
ns.ShowZonePrompt = function() zonePrompted = true end
ns.commands.prompt() -- run the zone-in check fresh
wow.check(not specPrompted and not zonePrompted, "no prompt for builds tagged in another spec (default)")
ns.db.promptOtherSpecs = true
ns.commands.prompt()
wow.check(specPrompted, "the other-spec offer still works when turned on in options")
ns.db.promptOtherSpecs = nil

------------------------------------------------------------------------
-- 6b. Wearing your GENERAL build doesn't hide a SPECIFIC one
------------------------------------------------------------------------
-- The bug: your active Blizzard loadout (M+) is tagged All dungeons, and
-- since custom builds save INTO it, it always matches your talents. The
-- "you already have a tagged build" check then fired in every dungeon,
-- and your Murder Row build was never offered in Murder Row.
ns.SaveBuild({ name = "Murder Row build", code = "MMMM", specID = 102 }, "Dungeons")
local murder
for _, b in ipairs(ns.FindGroup("Dungeons").builds) do if b.name == "Murder Row build" then murder = b end end
spec.instances = { ["2813"] = { buildID = murder.id, name = murder.name, label = "Murder Row" } }
spec.categories = { party = { buildID = mplus.id, name = mplus.name, label = "All dungeons" } }
spec.bosses = {}
GetInstanceInfo = function() return "Murder Row", "party", 23, "", 5, 0, false, 2813 end
local offered
ns.ShowZonePrompt = function(_, candidates) offered = candidates end
local wearing
ns.ItemMatchesCurrent = function(item) return item.build == wearing end

wearing, offered = mplus, nil
ns.commands.prompt()
wow.check(offered ~= nil and offered[1].item.build == murder,
    "wearing your All dungeons build, the dungeon's own build is still offered (first)")

wearing, offered = murder, nil
ns.commands.prompt()
wow.check(offered == nil, "wearing the dungeon's own build: no prompt")

-- Only a general tag here, and you're wearing it: nothing to offer.
spec.instances = {}
wearing, offered = mplus, nil
ns.commands.prompt()
wow.check(offered == nil, "only an All dungeons build tagged, and you're wearing it: no prompt")
ns.ItemMatchesCurrent = realMatches

------------------------------------------------------------------------
-- 7. Right-click a build: "Save current talents here"
------------------------------------------------------------------------
-- Codes whose header says which spec they're for (first letter F = Feral).
ExportUtil = { MakeImportDataStream = function(code) return {
    GetNumberOfBits = function() return 999 end,
    ExtractValue = function(_, bits)
        if bits == 8 then return 2 end
        return code:sub(1, 1) == "F" and 103 or 102
    end } end }
local onScreen = "NEWTALENTS"
PlayerSpellsFrame.TalentsFrame.shown = true
PlayerSpellsFrame.TalentsFrame.GetLoadoutExportString = function() return onScreen end
C_Traits.GenerateImportString = function() return "COMMITTEDONLY" end
wow.check(ns.CurrentTalentCode() == "NEWTALENTS",
    "\"current talents\" means what the talent screen shows, pending changes included")

-- The menu entry asks first, then overwrites.
local window = _G.LoadoutPlannerWindow
PlayerSpellsFrame.shown = true
window.shown = false
window:Show()
ns.Notify()
local row
for _, o in ipairs(wow.created) do
    if o.item and o.item.build == mplus and o.scripts and o.scripts.OnClick then row = o end
end
wow.check(row ~= nil, "the build has a row in the list")
row.scripts.OnClick(row, "RightButton")
local entry
for _, menuItem in ipairs(wow.lastMenu) do
    if type(menuItem) == "table" and menuItem.text == "Save current talents here" then entry = menuItem end
end
wow.check(entry ~= nil, "a custom build's right-click menu has \"Save current talents here\"")
wow.popups = {}
entry.fn()
local popup = wow.popups[1]
wow.check(popup and popup.which == "LOADOUTPLANNER_OVERWRITE_BUILD" and popup.data == mplus and mplus.code == "AAAA",
    "it asks before overwriting (nothing changes yet)")

local oldName, oldID = mplus.name, mplus.id
StaticPopupDialogs.LOADOUTPLANNER_OVERWRITE_BUILD.OnAccept({}, mplus)
wow.check(mplus.code == "NEWTALENTS", "confirming replaces the build's talents with your current ones")
wow.check(mplus.name == oldName and mplus.id == oldID, "its name and ID (so its tags) stay the same")

-- Talents for another spec are never saved over a build.
onScreen = "FERALTALENTS"
wow.check(ns.OverwriteBuildWithCurrent(mplus) == false and mplus.code == "NEWTALENTS",
    "talents from another spec aren't saved over a build")

-- Window closed: nothing can be pending, so the game's own export is used.
PlayerSpellsFrame.TalentsFrame.shown = false
wow.check(ns.CurrentTalentCode() == "COMMITTEDONLY", "with the talent window closed, your applied talents are used")

wow.finish()
