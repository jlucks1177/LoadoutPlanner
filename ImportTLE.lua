-- ImportTLE.lua
-- Copy groups and loadouts from the Talent Loadout Ex addon.
--
-- TLE saves everything in one account-wide global, TalentLoadoutEx:
--   TalentLoadoutEx[CLASS][specIndex] = ordered list of entries
-- An entry WITHOUT `text` is a group header; entries WITH `text` (a normal
-- Blizzard import code) are loadouts, belonging to the most recent header
-- above them. Loadouts before the first header are ungrouped.
--   group:   { name = "Raid", icon = 1234, isExpanded = false }
--   loadout: { name = "Nymrissa", icon = 5678, text = "CYGA...", pvp1 = ... }
-- (Learned by reading TLE's source: modules/data.lua.)
--
-- Another addon's SavedVariables are only loaded while THAT addon is
-- enabled, so TLE must be enabled when you import. You can disable it
-- afterwards; the builds are copied into LoadoutPlanner's own storage.

local addonName, ns = ...

local TLE_DEFAULT_ICON = 134400 -- TLE's "no icon chosen" question mark

-- CLASS file name ("DRUID") -> numeric class ID, for every class.
local function classIDsByFile()
    local map = {}
    for i = 1, GetNumClasses() do
        local _, classFile, classID = GetClassInfo(i)
        if classFile then
            map[classFile] = classID
        end
    end
    return map
end

-- These work on ANY class's storage (TLE holds all your classes),
-- unlike the helpers in Builds.lua, which use the current class.
local function findOrCreateGroup(classDB, name)
    for _, group in ipairs(classDB.groups) do
        if group.name:lower() == name:lower() then
            return group
        end
    end
    local group = { name = name, collapsed = false, builds = {} }
    table.insert(classDB.groups, group)
    return group
end

local function alreadyHave(classDB, name, code)
    for _, group in ipairs(classDB.groups) do
        for _, build in ipairs(group.builds) do
            if build.code == code and build.name == name then
                return true
            end
        end
    end
    return false
end

-- Which spec is this loadout for? The code's own header is the most
-- reliable answer; TLE's spec index is the fallback.
local function specFor(code, classFile, classID, specIndex)
    local specID = ns.ParseCodeSpec(code)
    if specID then
        local _, _, _, _, _, specClass = GetSpecializationInfoByID(specID)
        if specClass == classFile then
            return specID
        end
    end
    return GetSpecializationInfoForClassID(classID, specIndex)
end

function ns.ImportFromTLE()
    local source = _G.TalentLoadoutEx
    if type(source) ~= "table" then
        ns.Print("Talent Loadout Ex data wasn't found. Enable Talent Loadout Ex, /reload, "
            .. "then try again. You can disable it again afterwards.")
        return
    end

    local classIDs = classIDsByFile()
    local added, duplicates, skipped = 0, 0, 0
    local classesTouched = {}

    for classFile, classTable in pairs(source) do
        -- Skip TLE's "Option" table and anything that isn't a real class.
        if classIDs[classFile] and type(classTable) == "table" then
            LoadoutPlannerBuilds[classFile] = LoadoutPlannerBuilds[classFile] or { groups = {} }
            local classDB = LoadoutPlannerBuilds[classFile]

            -- pairs, not ipairs: TLE's own code notes its lists can contain gaps.
            for specIndex, specTable in pairs(classTable) do
                if type(specIndex) == "number" and type(specTable) == "table" then
                    local groupName = "Ungrouped"
                    for _, entry in ipairs(specTable) do
                        if type(entry) ~= "table" then
                            -- ignore stray values
                        elseif not entry.text then
                            groupName = entry.name or "Ungrouped" -- a group header
                        elseif entry.isLegacy then
                            skipped = skipped + 1 -- pre-Dragonflight format; unusable
                        else
                            local code = entry.text:gsub("%s", "")
                            local name = entry.name or "Imported"
                            local specID = specFor(code, classFile, classIDs[classFile], specIndex)
                            if not specID then
                                skipped = skipped + 1
                            elseif alreadyHave(classDB, name, code) then
                                duplicates = duplicates + 1 -- safe to import twice
                            else
                                local icon = entry.icon
                                if icon == TLE_DEFAULT_ICON or icon == "" then
                                    icon = nil -- let LoadoutPlanner pick automatically
                                end
                                table.insert(findOrCreateGroup(classDB, groupName).builds, {
                                    id = ns.NewBuildID(),
                                    name = name,
                                    code = code,
                                    icon = icon,
                                    specID = specID,
                                })
                                added = added + 1
                                classesTouched[classFile] = true
                            end
                        end
                    end
                end
            end
        end
    end

    local classNames = {}
    for classFile in pairs(classesTouched) do
        table.insert(classNames, classFile:sub(1, 1) .. classFile:sub(2):lower())
    end
    ns.Print(("Imported %d loadout(s) from Talent Loadout Ex%s."):format(added,
        #classNames > 0 and (" for " .. table.concat(classNames, ", ")) or ""))
    if duplicates > 0 then
        print(("  %d already existed and were skipped."):format(duplicates))
    end
    if skipped > 0 then
        print(("  %d couldn't be read (old format or unknown spec)."):format(skipped))
    end
    ns.Notify()
end

ns.commands.importtle = ns.ImportFromTLE
