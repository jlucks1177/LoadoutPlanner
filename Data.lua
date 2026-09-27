-- Data.lua
-- SavedVariables and tagging (roadmap Phase 3).
--
-- Saved shape (per character, see the TOC):
-- LoadoutPlannerDB = {
--   autoShowWithTalents = true,
--   specs = {
--     [specID] = {
--       instances = { [instanceID]  = ref },
--       bosses    = { [encounterID] = ref },
--     },
--   },
-- }
-- where ref = { configID = n, name = "...", exportString = "...", label = "..." }
--   or, for a custom build, ref = { buildID = "...", name = "...", label = "..." }
-- (label is the instance/boss name, saved so we can display it later
--  without having to look it up again)

local addonName, ns = ...

-- SavedVariables are loaded from disk just before YOUR ADDON_LOADED fires.
-- Reading LoadoutPlannerDB any earlier gives you nil.
ns.On("ADDON_LOADED", function(loadedName)
    if loadedName ~= addonName then
        return -- this event fires for every addon; ignore the others
    end

    LoadoutPlannerDB = LoadoutPlannerDB or {}
    local db = LoadoutPlannerDB
    db.specs = db.specs or {}
    db.artAlpha = db.artAlpha or 1        -- talent background art opacity (0-1)
    if db.autoShowWithTalents == nil then
        db.autoShowWithTalents = true
    end
    ns.db = db
end)

-- Get (or create) the tag tables for a spec. Tags are per spec because
-- loadouts are per spec: your Holy build means nothing to Retribution.
function ns.GetSpecData(specID)
    specID = specID or ns.GetSpecID()
    if not ns.db or not specID then
        return nil
    end
    local spec = ns.db.specs[specID]
    if not spec then
        spec = { instances = {}, bosses = {} }
        ns.db.specs[specID] = spec
    end
    -- "categories" was added in v0.14. Saved data from older versions
    -- doesn't have it yet, so create it on first use (no migration needed).
    spec.categories = spec.categories or {}
    return spec
end

------------------------------------------------------------------------
-- References: how a tag points at a loadout
------------------------------------------------------------------------
-- We store three things so a tag survives most changes:
--   configID     - fastest, exact match; breaks if the loadout is deleted
--   name         - fallback if the loadout was deleted and recreated
--   exportString - a talent string, kept for future recovery/sharing
function ns.MakeRef(loadout)
    if loadout.build then
        -- Custom builds have a permanent ID of our own, so that's all we need.
        return { buildID = loadout.build.id, name = loadout.name }
    end
    -- pcall runs a function in "protected mode": if it errors, we get
    -- ok = false instead of the whole addon breaking.
    local ok, exportString = pcall(C_Traits.GenerateImportString, loadout.configID)
    return {
        configID = loadout.configID,
        name = loadout.name,
        exportString = ok and exportString or nil,
    }
end

-- Turn a stored ref back into a live loadout, repairing it if needed.
function ns.ResolveRef(ref)
    if not ref then
        return nil
    end

    if ref.buildID then
        local build = ns.GetBuildByID(ref.buildID)
        if build then
            ref.name = build.name
            return ns.ItemFromBuild(build)
        end
        return nil -- the build was deleted
    end

    local byID = ns.GetLoadoutByID(ref.configID)
    if byID then
        ref.name = byID.name -- loadout was renamed; keep our copy current
        return byID
    end

    local byName = ns.FindLoadoutByName(ref.name)
    if byName then
        ref.configID = byName.configID -- loadout was recreated; re-point
        return byName
    end

    return nil -- gone entirely
end

------------------------------------------------------------------------
-- Tags, with optional difficulty
------------------------------------------------------------------------
-- A tag links an item to a target:
--   kind = "instances"  (key: the instance's map ID)
--   kind = "bosses"     (key: the boss's journal encounter ID)
--   kind = "categories" (key: "party" = every dungeon, "raid" = every raid)
-- optionally for ONE difficulty. The storage key is:
--   id              -> any difficulty (also every tag from before v0.10)
--   "id@difficulty" -> that difficulty only, e.g. "2657@16" = Mythic
function ns.TagKey(id, difficultyID)
    if difficultyID then
        return id .. "@" .. difficultyID
    end
    return id
end

-- label: the instance/boss name; icon: its icon (for list rows).
function ns.SetTag(kind, id, item, label, icon, difficultyID)
    local spec = ns.GetSpecData()
    if not spec then return end
    local ref = ns.MakeRef(item)
    ref.label = label
    ref.icon = icon
    ref.difficulty = difficultyID
    spec[kind][ns.TagKey(id, difficultyID)] = ref
    ns.Notify()
end

-- The tag for a target. With a difficulty, a tag for exactly that
-- difficulty wins; otherwise the "any difficulty" tag applies.
function ns.GetTag(kind, id, difficultyID)
    local spec = ns.GetSpecData()
    if not spec then return nil end
    return (difficultyID and spec[kind][ns.TagKey(id, difficultyID)]) or spec[kind][id]
end

-- Remove by storage key (as returned in GetTagsForItem's `key`).
function ns.ClearTag(kind, key)
    local spec = ns.GetSpecData()
    if not spec then return end
    spec[kind][key] = nil
    ns.Notify()
end

-- "Nymrissa (M)" / "Ara-Kara, City of Echoes (M+)" / "Manaforge Omega"
function ns.TagLabel(ref)
    local label = ref.label or "?"
    local difficulty = ref.difficulty and ns.DIFFICULTY_BY_ID[ref.difficulty]
    if difficulty then
        label = ("%s (%s)"):format(label, difficulty.short)
    end
    return label
end

-- Every tag that currently points at a given item, instance tags first.
-- `itemKey` is the item's key (a configID, or "b:<id>" for custom builds).
-- Returns a list of { kind, key, label, icon, difficulty }.
function ns.GetTagsForItem(itemKey)
    local result = {}
    local spec = ns.GetSpecData()
    if not spec then
        return result
    end
    for _, kind in ipairs({ "instances", "categories", "bosses" }) do
        for key, ref in pairs(spec[kind] or {}) do
            local loadout = ns.ResolveRef(ref)
            if loadout and loadout.key == itemKey then
                table.insert(result, {
                    kind = kind, key = key, label = ns.TagLabel(ref),
                    icon = ref.icon, difficulty = ref.difficulty,
                })
            end
        end
    end
    -- pairs() has no order; sort so the subtitle doesn't shuffle around.
    local order = { instances = 1, categories = 2, bosses = 3 }
    table.sort(result, function(a, b)
        if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
        return a.label < b.label
    end)
    return result
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns.commands.tags = function()
    local spec = ns.GetSpecData()
    if not spec then return end

    ns.Print("Tags for your current spec:")
    local any = false

    -- pairs() walks every key in a table (order not guaranteed);
    -- ipairs() walks 1, 2, 3... in order. These tables have ID keys, so pairs.
    for instanceID, ref in pairs(spec.instances) do
        any = true
        local instanceName = ns.TagLabel(ref)
        local status = ns.ResolveRef(ref) and "" or " |cffff4040(missing)|r"
        print(("  %s -> %s%s"):format(instanceName, ref.name, status))
    end
    for _, ref in pairs(spec.categories) do
        any = true
        local status = ns.ResolveRef(ref) and "" or " |cffff4040(missing)|r"
        print(("  %s -> %s%s"):format(ns.TagLabel(ref), ref.name, status))
    end
    for encounterID, ref in pairs(spec.bosses) do
        any = true
        local bossName = ns.TagLabel(ref)
        local status = ns.ResolveRef(ref) and "" or " |cffff4040(missing)|r"
        print(("  %s -> %s%s"):format(bossName, ref.name, status))
    end

    if not any then
        print("  (none yet)")
    end
end
