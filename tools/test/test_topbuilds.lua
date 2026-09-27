-- test_topbuilds.lua
-- The Top builds panel with only the built-in data (what players get from
-- CurseForge), using a small fake bundle in fixtures/Builtin.lua.
-- Also checks that the REAL Data/Builtin.lua has the expected shape.

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
wow.install({ modern = true })
print("Top builds test")

-- 1. The real data file (changes daily, so only its shape is checked).
local chunk = assert(loadfile("Data/Builtin.lua"))
chunk()
local real = LoadoutPlannerBuiltin
wow.check(type(real) == "table", "Data/Builtin.lua defines LoadoutPlannerBuiltin")
if real and real.parses then
    wow.check(type(real.parses.mythic) == "table" and type(real.parses.raid) == "table",
        "real parses.gg data has mythic and raid sections")
else
    print("  note Data/Builtin.lua is the empty placeholder (fine before the daily job has run)")
end

-- 2. The panel, with the fixture instead.
LoadoutPlannerBuiltin = nil
assert(loadfile("tools/test/fixtures/Builtin.lua"))()

local ns = { commands = {} }
wow.loadAddonFile("Core.lua", ns)
wow.loadAddonFile("Style.lua", ns)
ns.db = { specs = {} }
-- Minimal stand-ins for the parts of the addon this panel leans on.
function ns.GetSpecID() return 102 end
function ns.GetSpecData()
    ns.db.specs[102] = ns.db.specs[102] or { instances = {}, bosses = {}, categories = {} }
    return ns.db.specs[102]
end
function ns.TagKey(id, d) if d then return id .. "@" .. d end return id end
function ns.ItemFromBuild(b) return { key = "b:" .. b.id, name = b.name, build = b } end
function ns.SetTag() end
LoadoutPlannerBuilds = { DRUID = { groups = {} } }
ns.buildDB = LoadoutPlannerBuilds.DRUID
ExportUtil = { MakeImportDataStream = function() return {
    GetNumberOfBits = function() return 999 end,
    ExtractValue = function(_, bits) if bits == 8 then return 2 end return 102 end } end }
wow.loadAddonFile("Builds.lua", ns)
wow.loadAddonFile("Journal.lua", ns)
-- The season as the game's Encounter Journal would report it (matches the fixture).
function ns.GetSeason()
    local bosses = {}
    for i, name in ipairs({ "Nymrissa Wavecaller", "Nek'zali the Soulcoiler", "Entombed Sentinels" }) do
        bosses[i] = { name = name, encounterID = 3000 + i }
    end
    local dungeons = {}
    for i, name in ipairs({ "Kings' Rest", "Temple of Sethraliss", "Ruby Life Pools", "The Blinding Vale",
            "Voidscar Arena", "Den of Nalorakk", "Murder Row", "Altar of Fangs" }) do
        dungeons[i] = { name = name, mapID = 2000 + i, icon = i }
    end
    return { dungeons = dungeons, raids = { { name = "The Venomous Abyss", mapID = 3100, icon = 9, bosses = bosses } } }
end
function ns.GetCurrentInstance() return nil end
function ns.ItemMatchesCurrent() return false end
function ns.HideDiff() end
function ns.ShowDiff() end

local function openFresh()
    wow.loadAddonFile("Archon.lua", ns)
    wow.loadAddonFile("TopBuilds.lua", ns)
    ns.OpenTopBuilds()
    return _G.LoadoutPlannerTopBuilds
end

local panel = openFresh()
local line = wow.plain(panel.source.text)
wow.check(line:find("Most-played builds from parses.gg", 1, true) and line:find("Built in", 1, true), "defaults to the built-in parses.gg builds")
wow.check(panel.rows and #panel.rows > 0 and panel.rows[1].build ~= nil, "M+ tab lists builds")
wow.check(panel.rows[1].share and panel.rows[1].samples, "rows show popularity (share of samples)")

wow.click("Heroic")
wow.check(panel.rows[2] and panel.rows[2].label == "Nymrissa Wavecaller" and panel.rows[2].build ~= nil,
    "Heroic tab lists raid bosses with builds")

wow.click("Raider.IO")
wow.check(wow.plain(panel.source.text):find("No Raider.IO data yet", 1, true),
    "clicking Raider.IO explains it isn't included")

-- A new session where the saved choice is Raider.IO, which has no data:
-- the panel should open on parses.gg, and keep the saved choice.
ns.db.topSource = "raiderio"
panel:Hide()
panel = openFresh()
-- (Match the parses.gg header itself: the Raider.IO message also mentions parses.gg.)
wow.check(wow.plain(panel.source.text):find("Most-played builds from parses.gg", 1, true),
    "a saved source with no data falls back to one with data")
wow.check(ns.db.topSource == "raiderio", "the saved choice isn't overwritten")

wow.finish()
