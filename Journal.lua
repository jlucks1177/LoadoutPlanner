-- Journal.lua
-- Everything we read from the Encounter Journal and achievements:
--   * this season's raids (with bosses) and dungeons  - ns.GetSeason
--   * square boss icons                                - ns.GetBossIcon
--   * the current instance's icon                      - ns.GetCurrentInstanceIcon
--   * short dungeon labels ("AKCE")                    - ns.Initials
--   * difficulty names for tags                        - ns.DIFFICULTIES
-- Plus ns.SetIcon, which draws any kind of icon (file or atlas).
-- Used by the icon picker AND the tagging menus, so it lives on its own.

local addonName, ns = ...

------------------------------------------------------------------------
-- Difficulties
------------------------------------------------------------------------
-- The game identifies difficulties by number. These have been stable for
-- many expansions (they're the same numbers GetInstanceInfo reports).
ns.DIFFICULTIES = {
    raid = {
        { id = 17, short = "LFR", name = "Raid Finder" },
        { id = 14, short = "N", name = "Normal" },
        { id = 15, short = "H", name = "Heroic" },
        { id = 16, short = "M", name = "Mythic" },
    },
    party = {
        { id = 1, short = "N", name = "Normal" },
        { id = 2, short = "H", name = "Heroic" },
        { id = 23, short = "M", name = "Mythic" },
        { id = 8, short = "M+", name = "Mythic+" },
    },
}

-- Quick lookup by ID: ns.DIFFICULTY_BY_ID[16].short == "M"
ns.DIFFICULTY_BY_ID = {}
for _, list in pairs(ns.DIFFICULTIES) do
    for _, difficulty in ipairs(list) do
        ns.DIFFICULTY_BY_ID[difficulty.id] = difficulty
    end
end

-- Turn whatever difficulty the game reports into one of OUR IDs above.
-- Known numbers are used directly. For anything else, ask the game to
-- describe the difficulty (GetDifficultyInfo) and classify it, so a new
-- or renumbered difficulty (or a special version of one) still maps to
-- LFR / Normal / Heroic / Mythic / Mythic+.
function ns.NormalizeDifficulty(difficultyID, instanceType)
    if not difficultyID or difficultyID == 0 then return nil end
    if ns.DIFFICULTY_BY_ID[difficultyID] then return difficultyID end
    if not GetDifficultyInfo then return nil end
    -- name, groupType, isHeroic, isChallengeMode, displayHeroic,
    -- displayMythic, toggleDifficultyID, isLFR, ...
    local _, _, isHeroic, isChallengeMode, displayHeroic, displayMythic, _, isLFR = GetDifficultyInfo(difficultyID)
    if instanceType == "raid" then
        if isLFR then return 17 end
        if displayMythic then return 16 end
        if isHeroic or displayHeroic then return 15 end
        return 14
    elseif instanceType == "party" then
        if isChallengeMode then return 8 end
        if displayMythic then return 23 end
        if isHeroic or displayHeroic then return 2 end
        return 1
    end
    return nil
end

-- Tags that cover a whole KIND of instance rather than one place.
-- `id` is the key they're stored under, matching GetInstanceInfo's
-- instance type ("party" = dungeon, "raid" = raid).
ns.CATEGORIES = {
    { id = "party", label = "All dungeons", icon = 4352494 }, -- Mythic Keystone icon
    { id = "raid", label = "All raids", icon = "Interface\\Icons\\Achievement_Boss_Ragnaros" },
}
ns.CATEGORY_BY_ID = {}
for _, category in ipairs(ns.CATEGORIES) do
    ns.CATEGORY_BY_ID[category.id] = category
end

------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------
-- "Ara-Kara, City of Echoes" -> "AKCE" (skipping small words), max 4 letters.
-- One-word names get their first three letters: "The Dawnbreaker" -> "DAW".
local SMALL_WORDS = { of = true, the = true, ["and"] = true }
function ns.Initials(name)
    local words = {}
    for word in name:gmatch("[%a']+") do -- each run of letters is a word
        if not SMALL_WORDS[word:lower()] then
            table.insert(words, word)
        end
    end
    if #words == 1 then
        return words[1]:sub(1, 3):upper()
    end
    local letters = {}
    for _, word in ipairs(words) do
        table.insert(letters, word:sub(1, 1):upper())
    end
    return table.concat(letters):sub(1, 4)
end

------------------------------------------------------------------------
-- Icons can be a file ID (number), a file path, or an ATLAS name (a named
-- piece of a larger texture sheet, e.g. hero talent emblems). Atlases need
-- SetAtlas instead of SetTexture. `crop` trims the built-in icon border.
------------------------------------------------------------------------
function ns.SetIcon(texture, icon, crop)
    if type(icon) == "string" and C_Texture.GetAtlasInfo(icon) then
        texture:SetAtlas(icon)
        return
    end
    texture:SetTexture(icon)
    -- SetAtlas changes texture coordinates, and SetTexture doesn't reset
    -- them, so always set them explicitly.
    if crop then
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

------------------------------------------------------------------------
-- Square boss icons, found through achievements
------------------------------------------------------------------------
-- The Encounter Journal only offers round portraits for bosses. Raid
-- achievements, though, have square artwork for each boss (the
-- "Mythic: <Boss>" achievements). There's no API linking a boss to its
-- achievement, so we match by NAME: among achievements whose name contains
-- the boss's name, take the one with the fewest extra characters, which
-- is usually "Mythic: <Boss>". This avoids any hard-coded icon lists, and
-- it works in any language.
local RAIDS_CATEGORY = 168 -- "Dungeons & Raids". VERIFY if boss icons don't appear.
local achievements -- { { name = lowercase name, icon = fileID }, ... }

local function readAchievements()
    if achievements then return achievements end
    achievements = {}
    if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then
        return achievements
    end

    local categories = GetCategoryList() or {}
    local function isRaidCategory(categoryID)
        local _, parentID = GetCategoryInfo(categoryID)
        return categoryID == RAIDS_CATEGORY or parentID == RAIDS_CATEGORY
    end
    -- If the category number ever changes, fall back to scanning everything.
    local found = false
    for _, categoryID in ipairs(categories) do
        if isRaidCategory(categoryID) then found = true break end
    end

    for _, categoryID in ipairs(categories) do
        if not found or isRaidCategory(categoryID) then
            local total = GetCategoryNumAchievements(categoryID, true) or 0
            for i = 1, total do
                -- 2nd return is the name, 10th is the icon.
                local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(categoryID, i)
                if name and icon then
                    table.insert(achievements, { name = name:lower(), icon = icon })
                end
            end
        end
    end
    return achievements
end

local bossIconCache = {}

-- Square icon for a boss, or nil if no achievement matched.
function ns.GetBossIcon(bossName)
    if not bossName then return nil end
    if bossIconCache[bossName] ~= nil then
        return bossIconCache[bossName] or nil -- false = "looked, found nothing"
    end
    local target = bossName:lower()
    local bestIcon, bestExtra
    for _, achievement in ipairs(readAchievements()) do
        if achievement.name:find(target, 1, true) then
            local extra = #achievement.name - #target
            if not bestExtra or extra < bestExtra then
                bestIcon, bestExtra = achievement.icon, extra
            end
        end
    end
    bossIconCache[bossName] = bestIcon or false
    return bestIcon
end

-- The Encounter Journal's small icon for the instance you're standing in.
function ns.GetCurrentInstanceIcon()
    local mapID = C_Map.GetBestMapForUnit("player")
    local journalID = mapID and EJ_GetInstanceForMap(mapID)
    if not journalID or journalID == 0 then return nil end
    -- Returns: name, description, background, button image, lore image,
    -- small button image, ...
    local _, _, _, buttonImage, _, smallImage = EJ_GetInstanceInfo(journalID)
    return smallImage or buttonImage
end

-- Current raids and dungeons from the Encounter Journal. The journal's
-- LAST tier is the newest; during a season it's "Current Season", which
-- holds exactly this season's raids and Mythic+ dungeons.
local seasonCache

-- Returns { tierName, raids = {...}, dungeons = {...} }. Each instance:
--   { name, icon, mapID, journalID, isRaid, bosses = { { name, icon, encounterID, label } } }
-- mapID is the same number GetInstanceInfo() reports inside the instance,
-- which is what lets you tag an instance without being there.
-- Pass true to re-read instead of using the cached copy.
function ns.GetSeason(refresh)
    if seasonCache and not refresh then return seasonCache end
    local result = { raids = {}, dungeons = {} }
    seasonCache = result
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then
        return result
    end

    -- EJ_SelectTier changes the journal's selected tier, which the
    -- Encounter Journal window also uses. Remember it and put it back.
    local previousTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local ok, err = pcall(function()
        local tier = EJ_GetNumTiers()
        EJ_SelectTier(tier)
        result.tierName = EJ_GetTierInfo(tier)

        for _, isRaid in ipairs({ true, false }) do
            local i = 1
            while true do
                -- Returns (in order): journal id, name, description, background,
                -- button image, lore image, small button image, area map,
                -- link, shows difficulty, INSTANCE MAP ID (confirmed in
                -- Blizzard's own Encounter Journal code).
                local instanceID, name, _, _, buttonImage, _, smallImage, _, _, _, mapID =
                    EJ_GetInstanceByIndex(i, isRaid)
                if not instanceID then break end
                local entry = {
                    name = name, icon = smallImage or buttonImage, mapID = mapID,
                    journalID = instanceID, isRaid = isRaid, bosses = {},
                }

                if isRaid then
                    local b = 1
                    while true do
                        local bossName, _, encounterID = EJ_GetEncounterInfoByIndex(b, instanceID)
                        if not bossName then break end
                        -- Square achievement icon; the round journal
                        -- portrait only if no achievement matched.
                        local icon = ns.GetBossIcon(bossName)
                        if not icon then
                            local _, _, _, _, portrait = EJ_GetCreatureInfo(1, encounterID)
                            icon = portrait
                        end
                        table.insert(entry.bosses, {
                            icon = icon, name = bossName, encounterID = encounterID, label = tostring(b),
                        })
                        b = b + 1
                    end
                    table.insert(result.raids, entry)
                else
                    table.insert(result.dungeons, entry)
                end
                i = i + 1
            end
        end
    end)
    if previousTier then
        EJ_SelectTier(previousTier)
    end
    if not ok then
        geterrorhandler()(err)
    end
    return result
end
