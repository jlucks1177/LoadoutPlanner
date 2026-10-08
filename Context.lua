-- Context.lua
-- Knowing where you are, and offering the right build (roadmap Phase 4).

local addonName, ns = ...

-- Returns info about the current dungeon/raid, or nil in the open world.
function ns.GetCurrentInstance()
    -- GetInstanceInfo returns many values; we only need a few. The `_`
    -- names are a Lua convention for "I'm skipping this one".
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "party" or instanceType == "raid" then
        local instance = {
            id = instanceID, name = name, type = instanceType,
            difficulty = ns.NormalizeDifficulty(difficultyID, instanceType), -- our ID
            rawDifficulty = difficultyID,                                    -- the game's
            ids = { [instanceID] = true },
        }
        -- The Encounter Journal can know this place under a DIFFERENT map ID
        -- than GetInstanceInfo reports (tags made from the tag panel use the
        -- journal's). Accept both, so a tag is found either way.
        local ok, journalMapID = pcall(function()
            local uiMapID = C_Map.GetBestMapForUnit("player")
            local journalID = uiMapID and EJ_GetInstanceForMap(uiMapID)
            if journalID and journalID ~= 0 then
                return select(10, EJ_GetInstanceInfo(journalID)) -- 10th value: map ID
            end
        end)
        if ok and journalMapID then
            instance.ids[journalMapID] = true
        end
        return instance
    end
end

-- Bosses of the current instance, read from the Encounter Journal.
-- Returns a list of { id = journalEncounterID, name = "..." }.
function ns.GetCurrentBosses()
    if not ns.GetCurrentInstance() then
        return {}
    end

    -- The Encounter Journal uses its own instance IDs, so we translate
    -- from the map the player is standing on.
    local mapID = C_Map.GetBestMapForUnit("player")
    local journalInstanceID = mapID and EJ_GetInstanceForMap(mapID)
    if not journalInstanceID or journalInstanceID == 0 then
        return {}
    end

    local bosses = {}
    local index = 1
    while true do
        local name, _, journalEncounterID = EJ_GetEncounterInfoByIndex(index, journalInstanceID)
        if not name then
            break -- ran past the last boss
        end
        table.insert(bosses, { id = journalEncounterID, name = name })
        index = index + 1 -- Lua has no ++ operator
    end
    return bosses
end

------------------------------------------------------------------------
-- What's tagged for where you are?
------------------------------------------------------------------------
local MYTHIC_PLUS = 8

local function keystoneRunning()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

-- Has this boss already been killed on this difficulty (raid lockout)?
-- Returns false when it can't tell. The journal's encounter info gives
-- the IDs the lockout API wants (as Blizzard's own journal code does).
local function bossKilled(journalEncounterID, difficultyID)
    if not (C_RaidLocks and C_RaidLocks.IsEncounterComplete) then return false end
    local ok, killed = pcall(function()
        local _, _, _, _, _, _, dungeonEncounterID, mapID = EJ_GetEncounterInfo(journalEncounterID)
        return mapID and dungeonEncounterID
            and C_RaidLocks.IsEncounterComplete(mapID, dungeonEncounterID, difficultyID)
    end)
    return ok and killed or false
end
ns.IsBossKilled = bossKilled -- BossPrompt.lua uses it too

-- All instance tags in one spec's tag table that belong to `instance`,
-- as { ref, difficulty } (difficulty nil = "any difficulty").
-- A tag belongs to it if its ID is one of the instance's IDs, OR if its
-- saved label is the instance's name. The name check is a safety net in
-- case the game and the journal ever disagree about the ID.
local function instanceTagsIn(specTable, instance)
    local found = {}
    local wantedName = instance.name and instance.name:lower()
    for key, ref in pairs(specTable.instances or {}) do
        -- Keys are either 2813 or "2813@23": split into ID and difficulty.
        local id, difficulty = tostring(key):match("^(%d+)@?(%d*)$")
        id, difficulty = tonumber(id), tonumber(difficulty)
        local sameName = ref.label and ref.label:lower() == wantedName
        if id and (instance.ids[id] or sameName) then
            table.insert(found, { ref = ref, difficulty = difficulty })
        end
    end
    return found
end

-- Every build tagged for your current instance and difficulty in one
-- spec, in order of relevance, without duplicates. Each: { item?, ref, label }.
--   1. the instance, this exact difficulty
--   2. in ANY dungeon, its Mythic+ tag: a key can only be started from
--      inside, and talents lock once it starts, so walking in (on any
--      difficulty) is the only moment a Mythic+ build can be offered
--   3. the instance, any difficulty
--   4. DUNGEONS ONLY: the instance's tags for every other difficulty too.
--      Being in a dungeon at all is enough to be offered its builds (since
--      v0.19); the difficulty only decides the order.
--   5. "All dungeons" / "All raids" tags (same rules)
--   6. its bosses (skipping ones already killed, if asked to)
-- Raids stay strict about difficulty: a Mythic raid build is rarely right
-- on Normal, and raid difficulty is set before you zone in.
-- specTable defaults to your current spec. For OTHER specs, items can't
-- be resolved (Blizzard loadouts belong to a spec), so only `ref` is set.
-- noBosses: leave boss tags out (the zone-in prompt does, when the
-- boss-by-boss prompts in BossPrompt.lua are handling them).
function ns.GetCandidates(instance, skipKilled, specTable, noBosses)
    local list, seen = {}, {}
    local isCurrentSpec = (specTable == nil)
    specTable = specTable or ns.GetSpecData()
    if not (instance and specTable) then return list end

    -- general: an "All dungeons" / "All raids" tag rather than one for
    -- this place or one of its bosses (see CheckContext for why it matters).
    local function add(ref, label, general)
        if not ref then return end
        local item = isCurrentSpec and ns.ResolveRef(ref) or nil
        local key = item and item.key or (ref.buildID or ref.configID or ref.name)
        if (item or not isCurrentSpec) and not seen[key] then
            seen[key] = true
            table.insert(list, { item = item, ref = ref, label = label, general = general or nil })
        end
    end

    local tags = instanceTagsIn(specTable, instance)
    local function tagFor(difficulty)
        for _, tag in ipairs(tags) do
            if tag.difficulty == difficulty then return tag.ref end
        end
    end

    local difficulty = ns.DIFFICULTY_BY_ID[instance.difficulty]
    if instance.difficulty and instance.difficulty ~= MYTHIC_PLUS then
        add(tagFor(instance.difficulty), difficulty and difficulty.name or "This difficulty")
    end
    if instance.type == "party" then
        add(tagFor(MYTHIC_PLUS), "Mythic+")
    end
    add(tagFor(nil), "Any difficulty")
    local isDungeon = instance.type == "party"
    if isDungeon then
        for _, other in ipairs(ns.DIFFICULTIES.party) do
            add(tagFor(other.id), other.name .. " tag")
        end
    end

    -- 4. "All dungeons" / "All raids" tags, with the same difficulty rules:
    --    exact difficulty, then (dungeons) Mythic+, then any difficulty.
    --    Specific tags come first, so a build tagged for THIS dungeon
    --    outranks your general dungeon build.
    local categories = specTable.categories or {}
    local category = ns.CATEGORY_BY_ID[instance.type]
    if category then
        local function categoryTag(difficultyID)
            return categories[ns.TagKey(instance.type, difficultyID)]
        end
        if instance.difficulty and instance.difficulty ~= MYTHIC_PLUS then
            add(categoryTag(instance.difficulty),
                ("%s, %s"):format(category.label, difficulty and difficulty.name or "this difficulty"), true)
        end
        if instance.type == "party" then
            add(categoryTag(MYTHIC_PLUS), category.label .. ", Mythic+", true)
        end
        add(categoryTag(nil), category.label .. ", any difficulty", true)
        if isDungeon then
            for _, other in ipairs(ns.DIFFICULTIES.party) do
                add(categoryTag(other.id), ("%s, %s tag"):format(category.label, other.name), true)
            end
        end
    end

    -- Reading bosses touches the Encounter Journal; if that fails for any
    -- reason, still offer the instance's builds rather than nothing.
    local ok, bosses = pcall(ns.GetCurrentBosses)
    if noBosses then ok = false end
    for i, boss in ipairs(ok and bosses or {}) do
        if not (skipKilled and bossKilled(boss.id, instance.rawDifficulty)) then
            local bossTags = specTable.bosses or {}
            local ref = (instance.difficulty and bossTags[ns.TagKey(boss.id, instance.difficulty)]) or bossTags[boss.id]
            add(ref, ("Boss %d: %s"):format(i, boss.name))
        end
    end
    return list
end

-- Other specs of this character that have builds tagged here.
-- Returns { { specID, name, icon, candidates }, ... }.
function ns.GetOtherSpecMatches(instance)
    local result = {}
    local currentSpec = ns.GetSpecID()
    for specID, specTable in pairs(ns.db and ns.db.specs or {}) do
        if specID ~= currentSpec then
            local candidates = ns.GetCandidates(instance, true, specTable)
            local _, name, _, icon = GetSpecializationInfoByID(specID)
            if #candidates > 0 and name then
                table.insert(result, { specID = specID, name = name, icon = icon, candidates = candidates })
            end
        end
    end
    return result
end

-- Items to highlight (green strip) in the list: everything tagged here.
function ns.GetSuggestedKeys()
    local set = {}
    for _, candidate in ipairs(ns.GetCandidates(ns.GetCurrentInstance(), false)) do
        set[candidate.item.key] = true
    end
    return set
end

------------------------------------------------------------------------
-- The zone-in prompt
------------------------------------------------------------------------
-- Remember where we already asked (instance + difficulty), so declining
-- doesn't nag, but switching difficulty inside the instance asks again.
local promptedKey
local MAX_ATTEMPTS = 6 -- x 2 seconds: how long to wait for talent data

function ns.CheckContext(attempt)
    -- Only accept a real number: timers and events may pass other values.
    attempt = type(attempt) == "number" and attempt or 1
    ns.Notify() -- the panel's contents depend on where you are

    local instance = ns.GetCurrentInstance()
    if not instance then
        promptedKey = nil -- left the instance; allow a fresh prompt next time
        if ns.ResetBossPrompts then ns.ResetBossPrompts() end
        ns.HideZonePrompt()
        return
    end
    -- Move any old "Keystone Dungeons" tags to "All dungeons" (Data.lua)
    -- before we look for tags here. Cheap, and does nothing once done.
    pcall(function() ns.MigratePseudoTags((ns.GetSeason() or {}).skipped) end)
    local key = ns.TagKey(instance.id, instance.difficulty)
    if key == promptedKey or keystoneRunning() then
        return
    end
    if InCombatLockdown() then
        return -- PLAYER_REGEN_ENABLED checks again (see the bottom of this file)
    end

    -- Only builds tagged in the spec you're IN are ever offered: tags are
    -- per spec, and GetCandidates reads only this spec's tags.
    -- Boss tags are handled boss by boss (BossPrompt.lua) when that's on:
    -- if the next boss has a build, that prompt comes first and lists this
    -- place's own builds under it.
    local bossPrompts = ns.TryBossPrompt and not (ns.db and ns.db.bossPrompts == false)
    local candidates = ns.GetCandidates(instance, true, nil, bossPrompts)
    if bossPrompts then
        if ns.NoteBossMap then ns.NoteBossMap() end
        if ns.TryBossPrompt(instance, candidates) then
            promptedKey = key
            return
        end
    end
    if #candidates == 0 then
        promptedKey = key
        -- Optional (off by default since v0.19): if another spec has builds
        -- tagged here, offer to switch spec. Switching re-runs this check.
        if ns.db and ns.db.promptOtherSpecs then
            local others = ns.GetOtherSpecMatches(instance)
            if #others > 0 then
                ns.ShowSpecPrompt(instance, others)
            end
        end
        return
    end

    -- If you already have one of the tagged builds, there's nothing to ask.
    -- But when this place has builds of its OWN (tagged to it or its
    -- bosses), wearing your general "All dungeons/raids" build doesn't
    -- count: that's usually your active Blizzard loadout, which always
    -- matches your talents because custom builds save into it. Counting it
    -- hid every dungeon's own build (fixed in v0.20).
    -- ItemMatchesCurrent returns nil while talent data is still loading
    -- after the loading screen: wait and try again instead of guessing.
    local hasOwn = false
    for _, candidate in ipairs(candidates) do
        if not candidate.general then hasOwn = true break end
    end
    for _, candidate in ipairs(candidates) do
        -- (Not `cond and false or x`: in Lua that always gives x.)
        local matches = false
        if not (hasOwn and candidate.general) then
            matches = ns.ItemMatchesCurrent(candidate.item)
        end
        if matches == nil and attempt < MAX_ATTEMPTS then
            C_Timer.After(2, function() ns.CheckContext(attempt + 1) end)
            return
        end
        if matches then
            promptedKey = key
            ns.Print(("You already have |cffffd100%s|r (tagged: %s) for %s.")
                :format(candidate.item.name, candidate.label, instance.name))
            return
        end
    end

    promptedKey = key
    ns.ShowZonePrompt(instance, candidates)
end

-- Zoning fires several events and game data can lag slightly behind,
-- so wait a moment before checking.
-- Wrapped in a function so the timer can't pass anything unexpected in.
local function checkSoon()
    C_Timer.After(1, function() ns.CheckContext() end)
end
ns.On("PLAYER_ENTERING_WORLD", checkSoon)
ns.On("ZONE_CHANGED_NEW_AREA", checkSoon)
ns.On("PLAYER_DIFFICULTY_CHANGED", checkSoon) -- e.g. the raid leader switches to Mythic
ns.On("PLAYER_REGEN_ENABLED", checkSoon)      -- zoned in mid-combat? ask afterwards
ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        promptedKey = nil -- a different spec has different tags: ask again
        ns.HideZonePrompt()
        -- Talent data for the new spec takes a moment; CheckContext retries.
        C_Timer.After(2, function() ns.CheckContext() end)
    end
end)
ns.On("CHALLENGE_MODE_START", function()      -- key started: talents are locked now
    ns.HideZonePrompt()
end)

------------------------------------------------------------------------
-- /lp why: explain what the prompt logic sees right now
------------------------------------------------------------------------
-- A diagnostic command: when something "doesn't happen", make the code
-- tell you what it saw instead of guessing.
ns.commands.why = function()
    local instance = ns.GetCurrentInstance()
    if not instance then
        ns.Print("Not in a dungeon or raid, so there's nothing to prompt for.")
        return
    end
    local difficulty = ns.DIFFICULTY_BY_ID[instance.difficulty]
    ns.Print(("In %s (%s): instance ID %s, game difficulty ID %s -> treated as %s."):format(instance.name,
        instance.type, tostring(instance.id), tostring(instance.rawDifficulty), tostring(instance.difficulty)))
    print("  Difficulty: " .. (difficulty and difficulty.name or "not one LoadoutPlanner knows"))
    print("  In combat: " .. tostring(InCombatLockdown()) .. " | Keystone running: " .. tostring(keystoneRunning() or false))
    print("  Already prompted here this visit: " .. tostring(promptedKey == ns.TagKey(instance.id, instance.difficulty)))

    local ids = {}
    for id in pairs(instance.ids) do table.insert(ids, tostring(id)) end
    print("  Instance IDs checked: " .. table.concat(ids, ", ") .. " (plus any tag labeled \"" .. instance.name .. "\")")

    if ns.PrintBossStatus then ns.PrintBossStatus(instance) end
    local candidates = ns.GetCandidates(instance, true)
    if #candidates == 0 then
        print("  No builds are tagged for this instance/difficulty in your current spec.")
        local spec = ns.GetSpecData()
        local count = 0
        for key, ref in pairs(spec and spec.instances or {}) do
            count = count + 1
            if count <= 8 then
                print(("    (this spec has a tag on %s: \"%s\")"):format(tostring(key), ref.label or "?"))
            end
        end
        for _, other in ipairs(ns.GetOtherSpecMatches(instance)) do
            local names = {}
            for _, candidate in ipairs(other.candidates) do
                table.insert(names, (candidate.ref.name or "?") .. " [" .. candidate.label .. "]")
            end
            print(("  |cffffd100%s|r has builds tagged here: %s"):format(other.name, table.concat(names, ", ")))
        end
        return
    end
    local hasOwn = false
    for _, candidate in ipairs(candidates) do
        if not candidate.general then hasOwn = true break end
    end
    for _, candidate in ipairs(candidates) do
        local matches = ns.ItemMatchesCurrent(candidate.item)
        local note = (hasOwn and candidate.general and matches)
            and " (general tag: doesn't stop the prompt, since this place has its own builds)" or ""
        print(("  %s -> %s: %s%s"):format(candidate.label, candidate.item.name,
            matches == nil and "can't compare yet" or (matches and "you already have it" or "different from your talents"), note))
    end
end

-- /lp journal: what the Encounter Journal gives us this season, including
-- the pages we leave out (world bosses, "Keystone Dungeons").
ns.commands.journal = function()
    local season = ns.GetSeason(true)
    ns.Print(("Encounter Journal tier: %s"):format(tostring(season.tierName)))
    local function show(entry, note)
        print(("  %s %s | map %s | shows difficulty %s | %d bosses%s"):format(
            entry.isRaid and "[raid]" or "[dungeon]", tostring(entry.name), tostring(entry.mapID),
            tostring(entry.showsDifficulty), entry.bossCount or #entry.bosses, note or ""))
    end
    for _, raid in ipairs(season.raids) do show(raid) end
    for _, dungeon in ipairs(season.dungeons) do show(dungeon) end
    for _, entry in ipairs(season.skipped) do show(entry, " |cffff8040(left out)|r") end
end

ns.commands.prompt = function()
    -- Re-run the prompt even if it was already shown/declined here.
    promptedKey = nil
    ns.CheckContext()
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
local function requireInstance()
    local instance = ns.GetCurrentInstance()
    if not instance then
        ns.Print("You need to be inside a dungeon or raid for that.")
    end
    return instance
end

local function requireLoadout(name)
    local loadout = ns.FindItemByName(name)
    if not loadout then
        ns.Print(("No loadout named '%s'. Try /lp list."):format(name))
    end
    return loadout
end

ns.commands.tag = function(name)
    local instance = requireInstance()
    if not instance then return end
    if name == "" then
        ns.Print("Usage: /lp tag <loadout name>")
        return
    end
    local loadout = requireLoadout(name)
    if not loadout then return end

    ns.SetTag("instances", instance.id, loadout, instance.name, ns.GetCurrentInstanceIcon())
    ns.Print(("Tagged |cffffd100%s|r to %s."):format(loadout.name, instance.name))
end

ns.commands.untag = function()
    local instance = requireInstance()
    if not instance then return end
    ns.ClearTag("instances", instance.id)
    ns.Print(("Removed the tag for %s."):format(instance.name))
end

ns.commands.bosses = function()
    local bosses = ns.GetCurrentBosses()
    if #bosses == 0 then
        ns.Print("No bosses found here.")
        return
    end
    for i, boss in ipairs(bosses) do
        local ref = ns.GetTag("bosses", boss.id, (ns.GetCurrentInstance() or {}).difficulty)
        local tagText = ref and (" -> |cffffd100" .. ref.name .. "|r") or ""
        print(("  %d. %s%s"):format(i, boss.name, tagText))
    end
end

ns.commands.tagboss = function(args)
    -- "3 My Build" -> number = "3", name = "My Build"
    local number, name = args:match("^(%d+)%s+(.+)$")
    local boss = number and ns.GetCurrentBosses()[tonumber(number)]
    if not boss then
        ns.Print("Usage: /lp tagboss <boss #> <loadout name>  (see /lp bosses)")
        return
    end
    local loadout = requireLoadout(name)
    if not loadout then return end

    ns.SetTag("bosses", boss.id, loadout, boss.name, ns.GetBossIcon(boss.name) or ns.GetCurrentInstanceIcon())
    ns.Print(("Tagged |cffffd100%s|r to %s."):format(loadout.name, boss.name))
end

ns.commands.boss = function(args)
    local boss = ns.GetCurrentBosses()[tonumber(args) or 0]
    if not boss then
        ns.Print("Usage: /lp boss <boss #>  (see /lp bosses)")
        return
    end
    local loadout = ns.ResolveRef(ns.GetTag("bosses", boss.id, (ns.GetCurrentInstance() or {}).difficulty))
    if not loadout then
        ns.Print(("No build tagged for %s."):format(boss.name))
        return
    end
    ns.LoadItem(loadout)
end
