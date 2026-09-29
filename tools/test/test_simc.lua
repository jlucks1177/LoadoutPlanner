-- test_simc.lua
-- Custom builds added to the SimulationCraft export (/simc) for Raidbots.

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
wow.install({ modern = true })
print("SimulationCraft export test")

-- SimulationCraft's own checksum, written out independently here (from SimC
-- core.lua), so the test doesn't just trust the addon's copy.
local function simcChecksum(s)
    local s1, s2 = 1, 0
    for i = 1, #s do
        s1 = s1 + s:byte(i)
        s2 = s2 + s1
    end
    return bit.lshift(s2 % 65521, 16) + s1 % 65521
end
local function finish(body) return body .. "# Checksum: " .. ("%x"):format(simcChecksum((body:gsub("||", "|")))) end
local function checksumOK(profile)
    local body, hex = profile:match("^(.-)# Checksum: (%x+)$")
    return body ~= nil and ("%x"):format(simcChecksum((body:gsub("||", "|")))) == hex
end

-- A small profile shaped like SimC's (Balance Druid, two Blizzard loadouts).
local ACTIVE, RAID = "CYGAAAAAAActive", "CYGAAAAAAARaid"
local SIMC_BODY = table.concat({
    "# Player - Balance - 2026-09-29",
    "druid=\"Player\"",
    "spec=balance",
    "",
    "talents=" .. ACTIVE,
    "",
    "# Saved Loadout: Raid",
    "# talents=" .. RAID,
    "",
    "head=,id=1234",
    "",
}, "\n") .. "\n"

-- A fake SimulationCraft addon. Like the real one, it is NOT a global: only
-- Ace3's LibStub("AceAddon-3.0"):GetAddon("Simulationcraft") hands it out.
local calls = 0
local simcAddon = { GetSimcProfile = function() calls = calls + 1 return finish(SIMC_BODY) end }
local libs = { ["AceAddon-3.0"] = { GetAddon = function(_, name) return name == "Simulationcraft" and simcAddon or nil end } }
LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
Simulationcraft = nil

-- Load the addon.
local ns = {}
for _, file in ipairs(wow.tocFiles()) do wow.loadAddonFile(file, ns) end
local dispatcher
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then dispatcher = o break end
end
dispatcher.scripts.OnEvent(dispatcher, "ADDON_LOADED", "LoadoutPlanner")
ns.HookSimc() -- as if SimulationCraft had just loaded
wow.check(simcAddon.loadoutPlannerHooked == true, "finds SimulationCraft through Ace3 (it has no global) and hooks it")

-- Your library: two Balance builds (one identical to the Raid loadout), a
-- name with colour codes, and a Feral build.
ns.SaveBuild({ name = "Nymrissa", code = "CYGAAAAAANymrissa", specID = 102 }, "Raids")
ns.SaveBuild({ name = "Same as Raid", code = RAID, specID = 102 }, "Raids")
ns.SaveBuild({ name = "Raid", code = RAID, specID = 102 }, "Raids") -- exact repeat of the Blizzard one
ns.SaveBuild({ name = "|cffff0000Red|r M+", code = "CYGAAAAAAMplus", specID = 102 }, "Dungeons")
ns.SaveBuild({ name = "Feral thing", code = "CYGAAAAAAFeral", specID = 103 }, "Other")

wow.check(checksumOK(finish(SIMC_BODY)), "the test's own checksum matches its profile (sanity)")

local profile = simcAddon:GetSimcProfile()
wow.check(calls == 1, "SimC's own profile is still built (our hook wraps it)")
wow.check(profile:find("# Saved Loadout: Nymrissa\n# talents=CYGAAAAAANymrissa", 1, true) ~= nil,
    "custom builds are added as Saved Loadout pairs")
wow.check(profile:find("# Saved Loadout: Red M+\n", 1, true) ~= nil, "colour codes are stripped from names")
wow.check(profile:find("# Saved Loadout: Same as Raid\n# talents=" .. RAID, 1, true) ~= nil,
    "a build with the same talents but a different name is still listed")
local _, raidCount = profile:gsub("# Saved Loadout: Raid\n# talents=" .. RAID, "")
wow.check(raidCount == 2, "even an exact repeat (same name and talents) is listed")
wow.check(not profile:find("Feral", 1, true), "builds for other specs aren't added")
wow.check(checksumOK(profile), "the checksum is recomputed and valid")

-- Placed right after SimC's own loadout lines, before the gear.
local rawPos = profile:find("# talents=" .. RAID, 1, true)
local oursPos = profile:find("# Saved Loadout: Nymrissa", 1, true)
local gearPos = profile:find("head=", 1, true)
wow.check(rawPos and oursPos and gearPos and rawPos < oursPos and oursPos < gearPos,
    "our builds sit with SimC's loadouts, before the gear")

-- Turned off in the options menu: SimC's profile exactly as it was.
ns.db.simcExport = false
wow.check(simcAddon:GetSimcProfile() == finish(SIMC_BODY), "the option turns it off completely")
ns.db.simcExport = nil

-- Something unexpected (no checksum line): left untouched.
simcAddon.GetSimcProfile = nil
local odd = SIMC_BODY .. "no checksum here"
wow.check(ns.AddBuildsToSimcProfile(odd) == odd, "a profile without a checksum line is left untouched")

wow.finish()
