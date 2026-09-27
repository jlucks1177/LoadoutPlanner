-- Loadouts.lua
-- Reading and switching talent loadouts (roadmap Phases 1 and 2).
--
-- Key idea: a spec has ONE "active config" (the talents you actually have)
-- and several SAVED loadouts, each with its own configID. Loading a saved
-- loadout copies its choices into the active config.

local addonName, ns = ...

-- Blizzard's special configID for the starter build.
local STARTER_BUILD_ID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID

function ns.GetSpecID()
    return PlayerUtil.GetCurrentSpecID()
end

-- Returns a list of { key = n, configID = n, name = "..." } for a spec.
-- `key` is what the rest of the addon uses to identify any loadable
-- "item": a configID for Blizzard loadouts, "b:<id>" for custom builds.
function ns.GetLoadouts(specID)
    specID = specID or ns.GetSpecID()
    local list = {}
    if not specID then
        return list
    end

    -- `or {}` guards against nil, which happens before the list is ready.
    for _, configID in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        local info = C_Traits.GetConfigInfo(configID)
        if info then
            table.insert(list, { key = configID, configID = configID, name = info.name })
        end
    end
    return list
end

-- The loadout shown as selected in Blizzard's dropdown.
function ns.GetSelectedConfigID(specID)
    return C_ClassTalents.GetLastSelectedSavedConfigID(specID or ns.GetSpecID())
end

function ns.IsStarterBuild(configID)
    return configID == STARTER_BUILD_ID
end

function ns.GetLoadoutByID(configID, specID)
    for _, loadout in ipairs(ns.GetLoadouts(specID)) do
        if loadout.configID == configID then
            return loadout
        end
    end
end

-- Case-insensitive name match, so "/lp load raid" finds "Raid".
function ns.FindLoadoutByName(name, specID)
    local target = name:lower()
    for _, loadout in ipairs(ns.GetLoadouts(specID)) do
        if loadout.name:lower() == target then
            return loadout
        end
    end
end

------------------------------------------------------------------------
-- Switching
------------------------------------------------------------------------
-- Talent changes are impossible in combat. Instead of failing, we remember
-- the request and retry when combat ends (PLAYER_REGEN_ENABLED).
local pendingLoad       -- loadout queued during combat
local inFlightLoad      -- loadout we asked the game to load, awaiting confirmation

-- Let other files (Import.lua) reuse the "Loaded X." confirmation message.
function ns.ExpectLoad(name)
    inFlightLoad = name
end

function ns.LoadLoadout(configID, name)
    if InCombatLockdown() then
        pendingLoad = { configID = configID, name = name }
        ns.Print(("In combat - will load |cffffd100%s|r when combat ends."):format(name))
        return
    end

    -- autoApply = true means "switch and commit", like picking from the dropdown.
    -- The call only STARTS the change (you'll see a "Changing Talents" cast).
    local result, changeError = C_ClassTalents.LoadConfig(configID, true)

    if result == Enum.LoadConfigResult.Error then
        -- Let the game explain why (e.g. a Mythic+ key is active).
        ns.Print(("Couldn't load %s: %s"):format(name, changeError or "unknown reason"))
        return
    end

    -- Keep Blizzard's loadout dropdown showing the right name.
    -- VERIFY: if BugSack ever reports ADDON_ACTION_BLOCKED for this call,
    -- remove this line; the switch itself will still work.
    C_ClassTalents.UpdateLastSelectedSavedConfigID(ns.GetSpecID(), configID)

    if result == Enum.LoadConfigResult.NoChangesNecessary then
        ns.Print(("|cffffd100%s|r is already active."):format(name))
        ns.Notify()
    else
        inFlightLoad = name
        ns.Print(("Loading |cffffd100%s|r..."):format(name))
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingLoad then
        local queued = pendingLoad
        pendingLoad = nil
        ns.LoadLoadout(queued.configID, queued.name)
    end
end)

-- The real confirmation that a switch finished.
ns.On("TRAIT_CONFIG_UPDATED", function()
    if inFlightLoad then
        ns.Print(("Loaded |cffffd100%s|r."):format(inFlightLoad))
        inFlightLoad = nil
    end
    ns.Notify()
end)

-- The loadout list isn't available at login until this fires, and it
-- fires again when loadouts are created, deleted, or renamed.
ns.On("TRAIT_CONFIG_LIST_UPDATED", ns.Notify)
ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        ns.Notify()
    end
end)

------------------------------------------------------------------------
-- "Items": one interface over Blizzard loadouts and custom builds
------------------------------------------------------------------------
-- Every list row, tag, and prompt works with an item that has `key` and
-- `name`, plus either `configID` (Blizzard loadout) or `build` (ours).
-- Callers never need to care which kind they're holding.
function ns.LoadItem(item)
    if item.build then
        ns.ApplyBuild(item.build)
    else
        ns.LoadLoadout(item.configID, item.name)
    end
end

-- "Active" means: this item's talents are exactly your current talents.
-- So every identical loadout or build gets a check mark, not just the one
-- you clicked. (Comparison lives in Diff.lua: ns.ItemMatchesCurrent.)
-- If talents can't be compared (e.g. an unreadable code), a Blizzard
-- loadout falls back to "is it the selected one?" and a build to "no".
function ns.IsItemActive(item)
    local matches = ns.ItemMatchesCurrent and ns.ItemMatchesCurrent(item)
    if matches ~= nil then
        return matches
    end
    return not item.build and item.configID == ns.GetSelectedConfigID()
end

-- Blizzard loadouts first, then custom builds for this spec.
function ns.FindItemByName(name)
    local loadout = ns.FindLoadoutByName(name)
    if loadout then
        return loadout
    end
    local target = name:lower()
    for _, build in ipairs(ns.GetBuildsForSpec()) do
        if build.name:lower() == target then
            return ns.ItemFromBuild(build)
        end
    end
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns.commands.list = function()
    local loadouts = ns.GetLoadouts()
    if #loadouts == 0 then -- # is Lua's length operator for lists
        ns.Print("No saved loadouts found for this spec (yet).")
        return
    end

    local selected = ns.GetSelectedConfigID()
    ns.Print("Loadouts for your current spec:")
    for _, loadout in ipairs(loadouts) do
        local marker = (loadout.configID == selected) and " |cff00ff00(selected)|r" or ""
        print("  " .. loadout.name .. marker)
    end
    if ns.IsStarterBuild(selected) then
        print("  |cff00ff00Starter build is selected.|r")
    end
end

ns.commands.load = function(name)
    if name == "" then
        ns.Print("Usage: /lp load <loadout name>")
        return
    end
    local item = ns.FindItemByName(name) -- Blizzard loadouts and custom builds
    if not item then
        ns.Print(("No loadout or build named '%s'. Try /lp list."):format(name))
        return
    end
    ns.LoadItem(item)
end
