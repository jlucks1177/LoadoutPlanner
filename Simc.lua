-- Simc.lua
-- Adds your custom builds to the SimulationCraft addon's export (/simc), so
-- Raidbots lists them next to your Blizzard loadouts, the way Talent
-- Loadout Ex and TalentLoadoutManager do.
--
-- How the export works: SimulationCraft builds one big text profile. Your
-- saved Blizzard loadouts appear in it as two comment lines each:
--     # Saved Loadout: Raid
--     # talents=CgEAAAAA...
-- Raidbots reads those pairs and offers them as talent options. The last
-- line is "# Checksum: <hex>", an Adler-32 of everything above it, which
-- Raidbots checks. So we add our own pairs and recompute the checksum.
--
-- SimulationCraft has no API for this. Like SimCOverride (public domain),
-- we wrap Simulationcraft:GetSimcProfile, which SimC calls for /simc, its
-- minimap button, and its "rebuild" toggles, and edit the text it returns.
-- Addons that post-hook PrintSimcProfile (TLE, TLM) still layer on top.
-- If anything looks unfamiliar (no checksum line), we leave the profile
-- untouched rather than risk a profile Raidbots rejects.

local addonName, ns = ...

------------------------------------------------------------------------
-- The checksum: SimulationCraft's own Adler-32, reproduced exactly
------------------------------------------------------------------------
-- (SimC core.lua, `adler32`: sums over the bytes, one modulo at the end.)
-- It runs over the profile with every "||" turned back into "|", because
-- the edit box shows a single pipe as two.
local function adler32(s)
    local prime = 65521
    local s1, s2 = 1, 0
    if #s > bit.lshift(1, 30) then return nil end
    for i = 1, #s do
        s1 = s1 + string.byte(s, i)
        s2 = s2 + s1
    end
    s1 = s1 % prime
    s2 = s2 % prime
    return bit.lshift(s2, 16) + s1
end
ns.SimcAdler32 = adler32 -- for the tests

-- Loadout names can contain "|" (colour codes, doubled pipes). A pipe in a
-- comment line breaks SimC's checksum convention, so strip them.
local function cleanName(name)
    local text = tostring(name or "?")
        :gsub("|c%x%x%x%x%x%x%x%x", "") -- colour start
        :gsub("|r", "")                 -- colour end
        :gsub("|T.-|t", "")             -- inline textures/icons
        :gsub("|A.-|a", "")             -- inline atlases
        :gsub("|+", "")                 -- any pipe left over
        :gsub("[\r\n]", " ")
    return (text:match("^%s*(.-)%s*$"))
end

------------------------------------------------------------------------
-- Editing the profile
------------------------------------------------------------------------
-- Returns the profile with our builds added (and a new checksum), or the
-- original profile unchanged if there's nothing to add or it doesn't look
-- the way we expect.
function ns.AddBuildsToSimcProfile(profile)
    if type(profile) ~= "string" then return profile end
    local body = profile:match("^(.-)# Checksum: %x+$")
    if not body then return profile end -- not a finished profile: leave it alone

    local specID = ns.GetSpecID and ns.GetSpecID()
    if not specID then return profile end

    -- Every build is listed, even when its talents match another loadout
    -- under a different name (you asked for each name to show on Raidbots).
    -- Only an exact repeat, same name AND same talents, is skipped, so a
    -- build that mirrors a Blizzard loadout of the same name isn't doubled.
    local present = {}
    for name, code in body:gmatch("# Saved Loadout: ([^\n]*)\n# talents=([%w+/=]+)") do
        present[name .. "\n" .. code] = true
    end

    local added = {}
    for _, build in ipairs(ns.GetBuildsForSpec(specID)) do
        local code = build.code
        local name = cleanName(build.name)
        local key = name .. "\n" .. tostring(code)
        if type(code) == "string" and code ~= "" and not present[key] then
            present[key] = true
            table.insert(added, "# Saved Loadout: " .. name)
            table.insert(added, "# talents=" .. code)
        end
    end
    if #added == 0 then return profile end

    -- Put them right after SimC's own talent lines (the active "talents="
    -- line and its "# Saved Loadout" pairs), so they read as one list.
    -- Offspec loadouts ("offspec_talents=") are a separate section; we go
    -- before it.
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    local insertAt
    for i, line in ipairs(lines) do
        if line:match("^talents=") or line:match("^# talents=") then
            insertAt = i
        elseif line:match("offspec_talents=") or line:match("^### Offspec") then
            break
        end
    end
    if not insertAt then return profile end -- no talent section found: don't guess
    for i = #added, 1, -1 do
        table.insert(lines, insertAt + 1, added[i])
    end
    -- The split above adds one empty element at the end (body ends in "\n").
    local newBody = table.concat(lines, "\n", 1, #lines - 1) .. "\n"

    local sum = adler32((newBody:gsub("||", "|")))
    if not sum then return profile end
    return newBody .. "# Checksum: " .. ("%x"):format(sum)
end

------------------------------------------------------------------------
-- Hooking SimulationCraft
------------------------------------------------------------------------
-- SimulationCraft keeps its addon object PRIVATE (its core.lua starts with
-- `local _, Simulationcraft = ...`), so there's no global to look at. It's
-- an Ace3 addon, though, and Ace3 hands out any addon's object by name.
-- (v0.19 first looked for a global, found nothing, and silently did nothing.)
local function simcAddon()
    local aceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local simc = aceAddon and aceAddon:GetAddon("Simulationcraft", true)
    if type(simc) == "table" then return simc end
    -- Fallback in case a future version makes it global.
    if type(_G.Simulationcraft) == "table" then return _G.Simulationcraft end
end

local function hookSimc()
    local simc = simcAddon()
    if type(simc) ~= "table" or type(simc.GetSimcProfile) ~= "function" or simc.loadoutPlannerHooked then
        return
    end
    simc.loadoutPlannerHooked = true
    local original = simc.GetSimcProfile
    simc.GetSimcProfile = function(self, ...)
        local profile, err = original(self, ...)
        if err or not (ns.db and ns.db.simcExport ~= false) then
            return profile, err
        end
        -- Never let our edit break /simc: on any error, SimC's own profile.
        local ok, edited = pcall(ns.AddBuildsToSimcProfile, profile)
        return ok and edited or profile, err
    end
end
ns.HookSimc = hookSimc -- for the tests

-- SimulationCraft may load before or after us (it's an OptionalDep).
EventUtil.ContinueOnAddOnLoaded("Simulationcraft", hookSimc)

------------------------------------------------------------------------
-- /lp simc: why aren't my builds in the export?
------------------------------------------------------------------------
ns.commands.simc = function()
    local simc = simcAddon()
    ns.Print("SimulationCraft export check:")
    print("  LoadoutPlanner version: " .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))
    print("  SimulationCraft addon loaded: " .. tostring(type(simc) == "table"))
    print("  Hooked into its export: " .. tostring(type(simc) == "table" and simc.loadoutPlannerHooked == true))
    print("  Option on (... menu): " .. tostring(not (ns.db and ns.db.simcExport == false)))
    local specID = ns.GetSpecID and ns.GetSpecID()
    local builds = specID and ns.GetBuildsForSpec(specID) or {}
    local _, specName = GetSpecializationInfoByID(specID or 0)
    print(("  Custom builds for your current spec (%s): %d"):format(tostring(specName), #builds))
    for i, build in ipairs(builds) do
        if i > 8 then print("    ...") break end
        print("    - " .. tostring(build.name))
    end
    if type(simc) == "table" and type(simc.GetSimcProfile) == "function" then
        local ok, profile = pcall(simc.GetSimcProfile, simc)
        if ok and type(profile) == "string" then
            local count = 0
            for _ in profile:gmatch("# Saved Loadout:") do count = count + 1 end
            print(("  /simc would contain %d '# Saved Loadout' entries in total (yours + Blizzard's)."):format(count))
        else
            print("  Couldn't build a test profile: " .. tostring(profile))
        end
    end
end
