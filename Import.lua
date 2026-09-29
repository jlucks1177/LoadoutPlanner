-- Import.lua
-- Turning an import code into actual talents.
--
-- Two jobs:
--   1. PARSE a code into a list of "learn this node at this rank" entries.
--      We reuse Blizzard's own parser (ClassTalentImportExportMixin) so we
--      automatically follow any format change Blizzard makes.
--   2. APPLY those entries to YOUR CURRENT talents, in two steps that
--      mirror Blizzard's own talent screen:
--        STAGE  (single click) - the talents change on the talent screen,
--                                pending, with "Apply Changes" lit, exactly
--                                as if you had clicked them yourself.
--        COMMIT (double click) - stage, then apply ("Changing Talents"
--                                cast). The result saves into whichever
--                                Blizzard loadout you have selected: a
--                                custom build is applied ONTO your active
--                                Blizzard loadout (by design: Blizzard
--                                loadouts are the slots, builds fill them).
--      Staging then clicking Blizzard's own Apply Changes button is the
--      safest path: committing from addon code can taint the talent UI and
--      break action-bar keybinds (WoWUIBugs #447).

local addonName, ns = ...

------------------------------------------------------------------------
-- Part 1: parsing
------------------------------------------------------------------------
-- Blizzard's parser lives in the load-on-demand talent UI addon.
local function blizzardImporter()
    if not ClassTalentImportExportMixin then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    end
    return ClassTalentImportExportMixin
end

-- Parsing touches every node in the tree, so cache the results.
-- Cleared on spec change because entries are tied to the current tree.
local parsed = {}

function ns.ForgetParsedBuild(code)
    parsed[code] = nil
end

ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        parsed = {}
    end
end)

local function parse(code)
    local IE = blizzardImporter()
    if not IE then
        return nil, "Blizzard's talent import code isn't available."
    end

    local stream = ExportUtil.MakeImportDataStream(code)
    -- These are Blizzard's own methods; they only read the stream and the
    -- tree, so calling them from our code is safe.
    local valid, version, specID, treeHash = IE:ReadLoadoutHeader(stream)
    if not valid then
        return nil, "Invalid import code."
    end
    if version ~= C_Traits.GetLoadoutSerializationVersion() then
        return nil, "This code is from an older game version. Re-export it."
    end
    if specID ~= ns.GetSpecID() then
        local _, specName = GetSpecializationInfoByID(specID)
        return nil, ("This build is for %s. Switch spec first."):format(specName or "another spec")
    end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not IE:IsHashEmpty(treeHash) and not IE:HashEquals(treeHash, C_Traits.GetTreeHash(treeID)) then
        return nil, "The talent tree changed since this code was made. Re-export it."
    end

    local content = IE:ReadLoadoutContent(stream, treeID)
    local entries = IE:ConvertToImportLoadoutEntryInfo(C_ClassTalents.GetActiveConfigID(), treeID, content)
    return entries
end

-- Returns a list of { nodeID, ranksPurchased, ranksGranted, selectionEntryID }
-- or nil, errorMessage.
function ns.GetBuildEntries(code)
    if parsed[code] then
        return parsed[code]
    end
    local ok, entries, err = pcall(parse, code)
    if not ok then
        return nil, "Couldn't read this code (" .. tostring(entries) .. ")."
    end
    if entries then
        parsed[code] = entries
    end
    return entries, err
end

------------------------------------------------------------------------
-- Part 2: applying
------------------------------------------------------------------------
-- Node types where you pick ONE option (choice nodes and the hero-tree
-- choice). Built defensively: using a nil as a table key is an error, so
-- skip any enum value that doesn't exist in this game version.
local SELECTION_TYPES = {}
for _, name in ipairs({ "Selection", "SubTreeSelection" }) do
    local value = Enum.TraitNodeType[name]
    if value then
        SELECTION_TYPES[value] = true
    end
end
local HERO_CHOICE = Enum.TraitNodeType.SubTreeSelection

-- What the build wants, per node: { ranks = purchased ranks, entryID = choice }.
-- (Tiered nodes appear as several entries; their ranks add up.)
local function wantedByNode(entries)
    local wanted = {}
    for _, entry in ipairs(entries) do
        if (entry.ranksPurchased or 0) > 0 then
            local need = wanted[entry.nodeID] or { ranks = 0 }
            need.ranks = need.ranks + entry.ranksPurchased
            need.entryID = entry.selectionEntryID
            wanted[entry.nodeID] = need
        end
    end
    return wanted
end

-- Tree nodes sorted top to bottom (by their Y position on the tree).
-- Learning top-down means prerequisites usually come first; refunding
-- bottom-up means talents that depend on others go first.
local function nodesTopDown(configID, treeID)
    local list = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.ID ~= 0 then
            table.insert(list, info)
        end
    end
    table.sort(list, function(a, b) return (a.posY or 0) < (b.posY or 0) end)
    return list
end

local function isSatisfied(info, need)
    if SELECTION_TYPES[info.type] then
        return (info.ranksPurchased or 0) > 0 and info.activeEntry
            and info.activeEntry.entryID == need.entryID
    end
    return (info.ranksPurchased or 0) >= need.ranks
end

-- Learn everything the build wants that isn't there yet. Talents have
-- prerequisites (arrows, point gates, the hero-tree choice), so repeat
-- passes until one makes no progress. Returns how many nodes failed.
local function purchaseAll(configID, treeID, wanted)
    local pending = {}
    for _, info in ipairs(nodesTopDown(configID, treeID)) do
        local need = wanted[info.ID]
        if need and not isSatisfied(info, need) then
            table.insert(pending, { nodeID = info.ID, need = need, isSelection = SELECTION_TYPES[info.type] })
        end
    end

    local progress = true
    while progress and #pending > 0 do
        progress = false
        for i = #pending, 1, -1 do -- backwards, so removing is safe
            local task = pending[i]
            local done = false
            if task.isSelection then
                done = C_Traits.SetSelection(configID, task.nodeID, task.need.entryID)
            else
                local info = C_Traits.GetNodeInfo(configID, task.nodeID)
                local have = info and info.ranksPurchased or 0
                while have < task.need.ranks and C_Traits.PurchaseRank(configID, task.nodeID) do
                    have = have + 1
                    progress = true
                end
                done = have >= task.need.ranks
            end
            if done then
                table.remove(pending, i)
                progress = true
            end
        end
    end
    return #pending
end

-- Refund one node completely.
local function refund(configID, info)
    C_Traits.RefundAllRanks(configID, info.ID)
    for _ = 1, (info.maxRanks or 1) do -- belt and braces, as TLE does
        if not C_Traits.RefundRank(configID, info.ID) then break end
    end
end

-- FAST PATH: change only what differs. Every single talent change makes
-- Blizzard's talent window redraw, so touching 5 nodes instead of 120 is
-- the difference between instant and a visible freeze.
-- Returns false if the hero tree changes (handled by the full path).
local function stageDifferences(configID, treeID, wanted)
    local nodes = nodesTopDown(configID, treeID)

    for _, info in ipairs(nodes) do
        if info.type == HERO_CHOICE then
            local need = wanted[info.ID]
            local current = info.activeEntry and info.activeEntry.entryID
            if need and current and need.entryID ~= current then
                return false -- switching hero trees: use the full path
            end
        end
    end

    -- Refund bottom-up anything the build doesn't want (or wants differently).
    for i = #nodes, 1, -1 do
        local info = nodes[i]
        local purchased = info.ranksPurchased or 0
        if purchased > 0 and info.type ~= HERO_CHOICE then
            local need = wanted[info.ID]
            local wrong = not need
                or (SELECTION_TYPES[info.type] and not isSatisfied(info, need))
                or (not SELECTION_TYPES[info.type] and purchased ~= need.ranks)
            if wrong then
                refund(configID, info)
            end
        end
    end

    purchaseAll(configID, treeID, wanted)
    return true
end

-- SLOW PATH: clear the tree and learn everything.
local function stageFromScratch(configID, treeID, wanted)
    C_Traits.ResetTree(configID, treeID)
    return purchaseAll(configID, treeID, wanted)
end

-- Why can't we change talents right now? Returns a message, or nil if we can.
local function blockedReason(build)
    if InCombatLockdown() then
        return "Can't change talents in combat."
    end
    if build.specID ~= ns.GetSpecID() then
        return "That build is for another spec. Switch spec first."
    end
    local selected = ns.GetSelectedConfigID()
    if selected and ns.IsStarterBuild(selected) then
        -- The starter build is Blizzard's; its talents can't be edited.
        return "The Starter Build can't be changed. Select or create a loadout in the talent window first."
    end
end

-- Does the talent screen now show exactly this build? Always re-checks
-- (forgetting cached fingerprints), since we just changed things ourselves.
local function showsBuild(build)
    ns.ForgetTalentPrints()
    return ns.ItemMatchesCurrent(ns.ItemFromBuild(build)) == true
end

-- Put the build's talents on the talent screen as pending changes.
-- Returns the active config ID on success, or nil after printing why not.
local function stage(build)
    local reason = blockedReason(build)
    if reason then
        ns.Print(reason)
        return nil
    end
    local entries, err = ns.GetBuildEntries(build.code)
    if not entries then
        ns.Print(err)
        return nil
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if showsBuild(build) then
        return configID -- already there: change nothing at all
    end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(build.specID)
    local wanted = wantedByNode(entries)

    -- Try the fast path; if it can't be used or doesn't end up exactly
    -- right, fall back to rebuilding from scratch.
    if not (stageDifferences(configID, treeID, wanted) and showsBuild(build)) then
        local failed = stageFromScratch(configID, treeID, wanted)
        if failed > 0 or not showsBuild(build) then
            C_Traits.RollbackConfig(configID) -- back to your committed talents
            ns.Print(("Couldn't load %s: %d talents wouldn't learn. The code may be outdated.")
                :format(build.name, math.max(failed, 1)))
            return nil
        end
    end
    return configID
end

-- Single click: stage only.
function ns.StageBuild(build)
    local configID = stage(build)
    if not configID then return end
    if C_Traits.ConfigHasStagedChanges(configID) then
        local selected = ns.GetSelectedConfigID()
        local info = selected and not ns.IsStarterBuild(selected) and C_Traits.GetConfigInfo(selected)
        ns.Print(("|cffffd100%s|r is on the talent screen. Click |cffffffffApply Changes|r "
            .. "(or double-click the build) to apply it%s."):format(build.name,
            info and (" to your |cffffffff" .. info.name .. "|r loadout") or ""))
    else
        ns.Print(("|cffffd100%s|r already matches your talents."):format(build.name))
    end
    ns.Notify()
end

-- After an addon commit, save the result into the selected loadout once
-- the game confirms the commit finished.
local saveInto

ns.On("TRAIT_CONFIG_UPDATED", function()
    if saveInto then
        local configID = saveInto
        saveInto = nil
        if C_Traits.GetConfigInfo(configID) then
            C_ClassTalents.SaveConfig(configID)
        end
    end
end)

-- Double click (and /lp load, and the zone-in prompt): stage + apply.
function ns.ApplyBuild(build)
    local configID = stage(build)
    if not configID then return end
    if not C_Traits.ConfigHasStagedChanges(configID) then
        ns.Print(("|cffffd100%s|r already matches your talents."):format(build.name))
        return
    end

    -- C_Traits.CommitConfig on the ACTIVE config is the call Talent Loadout
    -- Ex settled on after taint reports: it doesn't run any of Blizzard's
    -- talent-window Lua, so it doesn't spread taint into the action bars.
    -- The result is then saved into your selected loadout (above).
    if not C_Traits.CommitConfig(configID) then
        C_Traits.RollbackConfig(configID)
        ns.Print("The game refused the change. Wait a moment and try again.")
        return
    end
    local selected = ns.GetSelectedConfigID()
    if selected and not ns.IsStarterBuild(selected) then
        saveInto = selected
    end
    local info = selected and C_Traits.GetConfigInfo(selected)
    ns.ExpectLoad(build.name)
    ns.Print(("Applying |cffffd100%s|r%s..."):format(build.name,
        info and (" to your |cffffffff" .. info.name .. "|r loadout") or ""))
    ns.Notify()
end

------------------------------------------------------------------------
-- Click handling shared by every list of builds
------------------------------------------------------------------------
-- One click puts the talents on the talent screen (pending); a double
-- click applies them. We detect double clicks OURSELVES: a single click
-- waits a moment before staging, and a second click in that time cancels
-- it and applies instead, so a double click does the work ONCE. (WoW's
-- built-in OnDoubleClick fired only after the first click had already
-- staged everything, and if staging took long enough, the second click
-- stopped counting as a double click at all.)
local DOUBLE_CLICK_TIME = 0.3 -- seconds a single click waits for a second one

-- frame: the clicked row (the pending timer is stored on it).
-- build: { code, specID, name } - a saved build or a "top build".
function ns.HandleBuildClick(frame, build)
    -- Compare by code, not table identity: a list may rebuild its row
    -- data between the two clicks.
    if frame.clickTimer and frame.clickBuild and frame.clickBuild.code == build.code then
        frame.clickTimer:Cancel()
        frame.clickTimer = nil
        ns.ApplyBuild(build)
        return
    end
    if frame.clickTimer then frame.clickTimer:Cancel() end
    frame.clickBuild = build
    frame.clickTimer = C_Timer.NewTimer(DOUBLE_CLICK_TIME, function()
        frame.clickTimer = nil
        ns.StageBuild(build)
    end)
end
