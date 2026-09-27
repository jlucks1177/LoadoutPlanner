-- Builds.lua
-- Your own library of builds: import codes organized into groups, with
-- icons. Stored ACCOUNT-WIDE (SavedVariables, not ...PerCharacter), per
-- class, so every druid alt sees the same druid builds.
--
-- LoadoutPlannerBuilds = {
--   DRUID = {
--     groups = {
--       { name = "Raid", collapsed = false, builds = {
--           { id = "...", name = "Nymrissa", code = "...", icon = 136096, specID = 102 },
--       } },
--     },
--   },
-- }
-- Groups and builds are arrays (not keyed tables) because ORDER matters:
-- the player arranges them.

local addonName, ns = ...

ns.On("ADDON_LOADED", function(loadedName)
    if loadedName ~= addonName then return end
    LoadoutPlannerBuilds = LoadoutPlannerBuilds or {}
    local _, classFile = UnitClass("player")
    LoadoutPlannerBuilds[classFile] = LoadoutPlannerBuilds[classFile] or { groups = {} }
    ns.buildDB = LoadoutPlannerBuilds[classFile]
end)

function ns.GetGroups()
    return ns.buildDB and ns.buildDB.groups or {}
end

function ns.ItemFromBuild(build)
    return { key = "b:" .. build.id, name = build.name, build = build }
end

-- Custom builds for one spec, in display order.
function ns.GetBuildsForSpec(specID)
    specID = specID or ns.GetSpecID()
    local result = {}
    for _, group in ipairs(ns.GetGroups()) do
        for _, build in ipairs(group.builds) do
            if build.specID == specID then
                table.insert(result, build)
            end
        end
    end
    return result
end

-- Returns build, group, index-in-group (or nil).
function ns.GetBuildByID(id)
    for _, group in ipairs(ns.GetGroups()) do
        for index, build in ipairs(group.builds) do
            if build.id == id then
                return build, group, index
            end
        end
    end
end

------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------
function ns.FindGroup(name)
    local target = name:lower()
    for index, group in ipairs(ns.GetGroups()) do
        if group.name:lower() == target then
            return group, index
        end
    end
end

function ns.GetOrCreateGroup(name)
    local group = ns.FindGroup(name)
    if not group then
        group = { name = name, collapsed = false, builds = {} }
        table.insert(ns.GetGroups(), group)
        ns.Notify()
    end
    return group
end

function ns.RenameGroup(group, newName)
    if newName == "" or ns.FindGroup(newName) then
        ns.Print("That group name is empty or already used.")
        return
    end
    group.name = newName
    ns.Notify()
end

function ns.DeleteGroup(group)
    local groups = ns.GetGroups()
    for index, g in ipairs(groups) do
        if g == group then
            table.remove(groups, index)
            break
        end
    end
    ns.Notify()
end

-- Swap an element with its neighbor. Shared by group and build reordering.
local function move(list, index, delta)
    local target = index + delta
    if target < 1 or target > #list then
        return
    end
    list[index], list[target] = list[target], list[index] -- Lua can swap in one line
    ns.Notify()
end

function ns.MoveGroup(group, delta)
    local _, index = ns.FindGroup(group.name)
    if index then move(ns.GetGroups(), index, delta) end
end

------------------------------------------------------------------------
-- Builds
------------------------------------------------------------------------
-- Unique IDs: time + a counter + a random number. The counter matters
-- when many builds are created in the same second (e.g. an import):
-- random numbers alone would collide surprisingly often (the "birthday
-- problem": 100 builds with 10,000 possible values collide ~40% of the time).
local idCounter = 0
function ns.NewBuildID()
    idCounter = idCounter + 1
    return ("%d-%d-%d"):format(time(), idCounter, math.random(0, 9999))
end
local newID = ns.NewBuildID

-- Create (existing = nil) or update a build. `fields` has name/code/icon/specID.
function ns.SaveBuild(fields, groupName, existing)
    if groupName == "" then
        groupName = "Ungrouped"
    end
    local targetGroup = ns.GetOrCreateGroup(groupName)

    if existing then
        local _, oldGroup, index = ns.GetBuildByID(existing.id)
        for k, v in pairs(fields) do
            existing[k] = v
        end
        if oldGroup and oldGroup ~= targetGroup then
            table.remove(oldGroup.builds, index)
            table.insert(targetGroup.builds, existing)
        end
        ns.ForgetParsedBuild(existing.code)
    else
        fields.id = newID()
        table.insert(targetGroup.builds, fields)
    end
    ns.Notify()
end

function ns.DeleteBuild(build)
    local _, group, index = ns.GetBuildByID(build.id)
    if group then
        table.remove(group.builds, index)
        ns.Notify()
    end
end

function ns.MoveBuild(build, delta)
    local _, group, index = ns.GetBuildByID(build.id)
    if group then move(group.builds, index, delta) end
end

------------------------------------------------------------------------
-- Checking an import code before saving it
------------------------------------------------------------------------
-- Just the spec ID from a code's header, with no other checks (used when
-- importing from other addons). Returns nil if the code can't be read.
function ns.ParseCodeSpec(code)
    local ok, stream = pcall(ExportUtil.MakeImportDataStream, code)
    if not ok or not stream or stream:GetNumberOfBits() < 8 + 16 then
        return nil
    end
    stream:ExtractValue(8) -- skip the version
    return stream:ExtractValue(16)
end

-- Blizzard documents the code's header: 8 bits of format version, then
-- 16 bits of spec ID. Reading just that much tells us whether the code is
-- usable and which spec it's for, without needing the talent window.
-- Returns specID, specName, specIcon on success, or nil, errorMessage.
function ns.ReadCodeHeader(code)
    code = (code or ""):gsub("%s", "") -- pasted codes sometimes carry spaces/newlines
    if code == "" then
        return nil, "Paste an import code."
    end

    local ok, stream = pcall(ExportUtil.MakeImportDataStream, code)
    if not ok or not stream or stream:GetNumberOfBits() < 8 + 16 + 128 then
        return nil, "That doesn't look like a talent import code."
    end

    local version = stream:ExtractValue(8)
    local specID = stream:ExtractValue(16)

    local currentVersion = C_Traits.GetLoadoutSerializationVersion()
    if version ~= currentVersion then
        return nil, "This code is from an older game version. Re-export it."
    end

    local _, specName, _, specIcon, _, classFile = GetSpecializationInfoByID(specID)
    if not specName then
        return nil, "Unknown specialization in this code."
    end
    if classFile ~= select(2, UnitClass("player")) then
        return nil, "This code is for a different class."
    end
    return specID, specName, specIcon
end

------------------------------------------------------------------------
-- Saving builds that came from outside (a data addon, or pasted from
-- Archon), optionally tagged in the same step
------------------------------------------------------------------------
-- If your library already has a build with exactly this code, that one is
-- reused instead of making a duplicate.
-- tag: { kind, id, label, icon, difficulty } or nil.
-- Returns the build, and true if it was already in your library.
function ns.SaveExternalBuild(code, name, groupName, icon, tag)
    code = code:gsub("%s", "")
    local existing
    for _, group in ipairs(ns.GetGroups()) do
        for _, build in ipairs(group.builds) do
            if build.code == code then
                existing = build
                break
            end
        end
        if existing then break end
    end

    local build = existing
    if not build then
        build = { name = name, code = code, icon = icon, specID = ns.ParseCodeSpec(code) }
        ns.SaveBuild(build, groupName) -- gives the table its id and stores it
    end
    if tag then
        ns.SetTag(tag.kind, tag.id, ns.ItemFromBuild(build), tag.label, tag.icon, tag.difficulty)
    end
    return build, existing ~= nil
end
