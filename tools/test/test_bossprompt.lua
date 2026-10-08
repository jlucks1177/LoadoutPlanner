-- test_bossprompt.lua
-- Boss-by-boss prompts: a prompt on reaching a new map area, and after
-- each kill, offering the next living boss's build (then the later
-- bosses' builds, in case you skip). No tag on the next boss: no prompt.

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
wow.install({ modern = true })
print("Boss prompt test")

-- A raid with five bosses over two map areas:
--   area 50: Alpha (1), Bravo (2)      area 51: Charlie (3), Delta (4), Echo (5)
-- Journal boss IDs 301-305; the game's encounter IDs (ENCOUNTER_END) 1301-1305.
local BOSSES = { "Alpha", "Bravo", "Charlie", "Delta", "Echo" }
local PINS = { [50] = { 301, 302 }, [51] = { 303, 304, 305 } }
local mapID = 50
C_Map = { GetBestMapForUnit = function() return mapID end }
EJ_GetInstanceForMap = function() return 7 end
EJ_GetInstanceInfo = function() return "Test Raid" end
EJ_GetEncounterInfoByIndex = function(i) if BOSSES[i] then return BOSSES[i], "", 300 + i end end
EJ_GetEncounterInfo = function(id) return BOSSES[id - 300], "", id, 0, "", 7, id + 1000, 3100 end
C_EncounterJournal = { GetEncountersOnMap = function(m)
    local out = {}
    for _, id in ipairs(PINS[m] or {}) do table.insert(out, { encounterID = id, mapX = 0.5, mapY = 0.5 }) end
    return out
end }
GetInstanceInfo = function() return "Test Raid", "raid", 15, "", 20, 0, false, 3100 end -- Heroic
local inCombat = false
InCombatLockdown = function() return inCombat end
C_Timer.After = function(_, fn) fn() end -- run timers immediately
clock = 1000
GetTime = function() return clock end

local ns = {}
for _, file in ipairs(wow.tocFiles()) do wow.loadAddonFile(file, ns) end
local dispatcher
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then dispatcher = o break end
end
local function fire(event, ...) dispatcher.scripts.OnEvent(dispatcher, event, ...) end
fire("ADDON_LOADED", "LoadoutPlanner")

-- Builds for Alpha, Bravo, Delta and Echo (Heroic). Charlie has none.
local builds = {}
for _, name in ipairs({ "Alpha", "Bravo", "Delta", "Echo" }) do
    ns.SaveBuild({ name = name .. " build", code = name:upper(), specID = 102 }, "Raid")
end
for _, b in ipairs(ns.FindGroup("Raid").builds) do builds[b.name] = b end
local spec = ns.GetSpecData()
spec.bosses[ns.TagKey(301, 15)] = { buildID = builds["Alpha build"].id, name = "Alpha build" }
spec.bosses[ns.TagKey(302, 15)] = { buildID = builds["Bravo build"].id, name = "Bravo build" }
spec.bosses[ns.TagKey(304, 15)] = { buildID = builds["Delta build"].id, name = "Delta build" }
spec.bosses[ns.TagKey(305, 15)] = { buildID = builds["Echo build"].id, name = "Echo build" }

local wearing
ns.ItemMatchesCurrent = function(item) return item.build ~= nil and item.build == wearing end
local shown
ns.ShowZonePrompt = function(_, list, title) shown = { list = list, title = title } end
local function names()
    local out = {}
    for _, c in ipairs(shown and shown.list or {}) do table.insert(out, c.item.name) end
    return table.concat(out, ", ")
end
local function kill(index, success)
    shown = nil
    fire("ENCOUNTER_END", 1300 + index, BOSSES[index], 15, 20, success or 1)
end

-- 1. Zone in (area 50): the first boss's build, then the later ones.
ns.commands.prompt()
wow.check(shown and shown.title == "Change talents for Alpha?", "zoning in: offered the first boss here (Alpha)")
wow.check(names() == "Alpha build, Bravo build, Delta build",
    "its build comes first, then at most two later bosses' builds in kill order")
wow.check(shown.list[1].note == "Next boss: Alpha"
    and wow.plain(shown.list[2].note):find("different kill order", 1, true) ~= nil
    and wow.plain(shown.list[3].note):find("(boss 4)", 1, true) ~= nil,
    "the extra bosses are marked as being for a different kill order")

-- 2. Wipe on Alpha: nothing.
kill(1, 0)
wow.check(shown == nil, "a wipe doesn't prompt")

-- 3. Kill Alpha: Bravo is next in this area.
kill(1)
wow.check(shown and shown.title == "Change talents for Bravo?" and names() == "Bravo build, Delta build, Echo build",
    "after a kill: the next boss in this area (Bravo)")

-- 4. Kill Bravo: the next boss (Charlie) has no build, so no prompt.
kill(2)
wow.check(shown == nil, "next boss untagged: no prompt")

-- 5. Walk into area 51: Charlie's next there, still untagged, so nothing.
shown, mapID = nil, 51
fire("ZONE_CHANGED_INDOORS")
wow.check(shown == nil, "new area whose next boss is untagged: no prompt")

-- 6. Kill Charlie in combat-heavy fashion: the prompt waits for combat to end.
inCombat = true
kill(3)
wow.check(shown == nil, "no prompt while in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
wow.check(shown and shown.title == "Change talents for Delta?", "...then Delta's build, once combat ends")

-- 7. Already wearing the next boss's build: no prompt.
ns.ResetBossPrompts()
wearing = builds["Delta build"]
kill(1); kill(2)       -- (Bravo's prompt; Charlie untagged)
kill(3)                -- Delta is next, and you're wearing its build
wow.check(shown == nil, "already wearing the next boss's build: no prompt")
wearing = nil

-- 8. Skipping ahead: fresh visit, area 51 first (nothing dead). Charlie
-- (untagged) is next there, so no prompt. Clear area 51 (Delta, Echo,
-- Charlie): nothing left here, so the next living boss in kill order
-- (Alpha) is offered, with Bravo after it.
ns.ResetBossPrompts()
mapID = 51
ns.commands.prompt()
wow.check(shown == nil or shown.title ~= "Change talents for Charlie?", "untagged boss here at zone-in: no boss prompt")
kill(4)
kill(5)
kill(3)
wow.check(shown and shown.title == "Change talents for Alpha?" and names() == "Alpha build, Bravo build",
    "area cleared out of order: the next living boss in kill order, then the rest")

-- 9. Re-entering an area re-offers its living boss, every time; just not
-- twice within 10 seconds (walking along an area's edge flips the map).
shown = nil
mapID = 50; fire("ZONE_CHANGED_INDOORS")
wow.check(shown == nil, "flipping straight back into the area: not offered again within 10 seconds")
clock = clock + 60
mapID = 51; fire("ZONE_CHANGED_INDOORS") -- (area 51 is cleared, so this offers Alpha too)
clock = clock + 60
shown = nil
mapID = 50; fire("ZONE_CHANGED_INDOORS")
wow.check(shown and shown.title == "Change talents for Alpha?", "re-entering an area later: its living boss is offered again")

-- 10. Turned off in the ... menu: nothing.
ns.ResetBossPrompts()
ns.db.bossPrompts = false
shown = nil
kill(1)
wow.check(shown == nil, "the option turns boss prompts off")

wow.finish()
