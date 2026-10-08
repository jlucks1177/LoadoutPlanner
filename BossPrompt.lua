-- BossPrompt.lua
-- Boss-by-boss prompts inside an instance:
--   * when you reach a new MAP AREA (the pages in your map's dropdown),
--     you're offered the build for the next living boss there;
--   * after each KILL, you're offered the next one.
-- The prompt lists that boss's build first, then up to MAX_EXTRA builds of
-- the bosses after it (in kill order), marked as being for a different
-- kill order. If the next boss has no build tagged, there's no prompt.
--
-- Where the information comes from:
--   * which map area you're in: C_Map.GetBestMapForUnit("player"), with
--     the game's ZONE_CHANGED events telling us when it changes;
--   * which bosses are in that area: the Adventure Guide's boss pins,
--     C_EncounterJournal.GetEncountersOnMap(mapID);
--   * which bosses are dead: your lockout (ns.IsBossKilled) plus the kills
--     seen this visit (ENCOUNTER_END), since the lockout can lag a moment.
-- Inside instances Blizzard hides your exact position, so an area is as
-- precise as it gets; the after-kill prompt covers areas with several
-- bosses. If an area has no boss pins, "next" simply means the next
-- living boss in kill order.

local addonName, ns = ...

local MAX_EXTRA = 2         -- later bosses listed under the next one, at most
-- Re-offered every time you re-enter its area while it's alive. The only
-- limit: not the same boss twice within REPEAT_GAP seconds, because
-- walking along an area's edge can flip the map back and forth.
local REPEAT_GAP = 10
local lastOffered = {}     -- "journalEncounterID@difficulty" -> time it was last offered
local killedThisVisit = {} -- dungeonEncounterID -> true
local lastMapID
local pending              -- a trigger that arrived in combat: run it afterwards

local function enabled()
    return not (ns.db and ns.db.bossPrompts == false) -- on by default
end

function ns.ResetBossPrompts()
    lastOffered, killedThisVisit, lastMapID, pending = {}, {}, nil, nil
end

-- The game's encounter ID for a journal boss (what ENCOUNTER_END reports).
local function dungeonEncounterID(journalID)
    if not EJ_GetEncounterInfo then return nil end
    local ok, id = pcall(function() return select(7, EJ_GetEncounterInfo(journalID)) end)
    return ok and id or nil
end

local function isDead(boss, instance)
    local dungeonID = dungeonEncounterID(boss.id)
    if dungeonID and killedThisVisit[dungeonID] then return true end
    return ns.IsBossKilled and ns.IsBossKilled(boss.id, instance.rawDifficulty) or false
end

local function currentMapID()
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and id or nil
end

-- Journal boss IDs pinned on a map area, as a set. VERIFY in game:
-- /dump C_EncounterJournal.GetEncountersOnMap(C_Map.GetBestMapForUnit("player"))
local function bossesOnMap(mapID)
    local set = {}
    if not (mapID and C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap) then return set end
    local ok, pins = pcall(C_EncounterJournal.GetEncountersOnMap, mapID)
    for _, pin in ipairs(ok and type(pins) == "table" and pins or {}) do
        if pin.encounterID then set[pin.encounterID] = true end
    end
    return set
end

-- This boss's tag at your difficulty (or "any difficulty"), as a prompt
-- candidate, or nil if it has no build tagged in your current spec.
local function bossCandidate(boss, index, instance)
    local spec = ns.GetSpecData()
    local tags = spec and spec.bosses or {}
    local ref = (instance.difficulty and tags[ns.TagKey(boss.id, instance.difficulty)]) or tags[boss.id]
    local item = ref and ns.ResolveRef(ref)
    if item then
        return { item = item, ref = ref, label = ("Boss %d: %s"):format(index, boss.name), bossID = boss.id }
    end
end

-- What to offer right now: { next = { boss, index, candidate? }, list = { candidates } }.
-- `next` is the next living boss: in this map area first, else in kill
-- order. `list` is its build (if tagged) followed by the other living
-- bosses' builds in kill order. Returns nil if no boss is left.
function ns.GetBossOffer(instance)
    local ok, bosses = pcall(ns.GetCurrentBosses)
    if not ok or type(bosses) ~= "table" or #bosses == 0 then return nil end
    local here = bossesOnMap(currentMapID())

    local living = {}
    for index, boss in ipairs(bosses) do
        if not isDead(boss, instance) then
            table.insert(living, { boss = boss, index = index })
        end
    end
    if #living == 0 then return nil end

    local nextBoss
    for _, entry in ipairs(living) do
        if here[entry.boss.id] then nextBoss = entry break end
    end
    nextBoss = nextBoss or living[1]
    nextBoss.candidate = bossCandidate(nextBoss.boss, nextBoss.index, instance)

    local list = {}
    if nextBoss.candidate then
        nextBoss.candidate.label = "Next boss: " .. nextBoss.boss.name
        nextBoss.candidate.note = ("Next boss: %s"):format(nextBoss.boss.name)
        table.insert(list, nextBoss.candidate)
        -- Up to MAX_EXTRA bosses after it, in kill order, for groups taking
        -- a different route; their row says so.
        local extras = 0
        for _, entry in ipairs(living) do
            if extras >= MAX_EXTRA then break end
            if entry.index > nextBoss.index then
                local candidate = bossCandidate(entry.boss, entry.index, instance)
                if candidate then
                    candidate.note = ("Only if you're using a different kill order (boss %d)")
                        :format(entry.index)
                    table.insert(list, candidate)
                    extras = extras + 1
                end
            end
        end
    end
    return { next = nextBoss, list = list, mapID = currentMapID() }
end

-- Offer the next boss's build if there's one to offer. `extra`: other
-- candidates to list after the bosses (the zone-in prompt passes the
-- raid's own tags). Returns true when the next boss has a build tagged
-- (whether or not a prompt was needed), so the caller knows bosses are
-- being handled; false when there's nothing boss-related to do.
function ns.TryBossPrompt(instance, extra)
    if not (enabled() and instance) then return false end
    local offer = ns.GetBossOffer(instance)
    local nextBoss = offer and offer.next
    if not (nextBoss and nextBoss.candidate) then return false end -- next boss untagged: no prompt

    local key = ns.TagKey(nextBoss.boss.id, instance.difficulty)
    local now = (GetTime or time)()
    if lastOffered[key] and now - lastOffered[key] < REPEAT_GAP then return true end
    lastOffered[key] = now
    if ns.ItemMatchesCurrent(nextBoss.candidate.item) then
        return true -- already wearing it
    end

    local list = offer.list
    local seen = {}
    for _, c in ipairs(list) do seen[c.item.key] = true end
    for _, c in ipairs(extra or {}) do
        if not seen[c.item.key] then
            seen[c.item.key] = true
            table.insert(list, c)
        end
    end
    ns.ShowZonePrompt(instance, list, ("Change talents for %s?"):format(nextBoss.boss.name))
    return true
end

-- A trigger (new map area, a kill) arrived: check now, or after combat.
local function trigger()
    if not enabled() then return end
    local instance = ns.GetCurrentInstance()
    if not instance then return end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return -- talents are locked during a key
    end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = nil
    ns.TryBossPrompt(instance)
end

-- New map area. (The first reading after zoning in is handled by the
-- zone-in check in Context.lua, which calls ns.TryBossPrompt itself.)
local function mapChanged()
    local mapID = currentMapID()
    if not ns.GetCurrentInstance() then
        lastMapID = nil
        return
    end
    if mapID and lastMapID and mapID ~= lastMapID then
        lastMapID = mapID
        trigger()
    else
        lastMapID = mapID or lastMapID
    end
end
ns.On("ZONE_CHANGED", mapChanged)
ns.On("ZONE_CHANGED_INDOORS", mapChanged)
ns.NoteBossMap = function() lastMapID = currentMapID() end -- zone-in: remember where we started

-- A boss fight ended. success = 1 on a kill; a wipe changes nothing.
ns.On("ENCOUNTER_END", function(encounterID, _, _, _, success)
    if success ~= 1 then return end
    if encounterID then killedThisVisit[encounterID] = true end
    -- Give the game a moment (loot, the lockout updating, leaving combat).
    C_Timer.After(2, trigger)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if pending then
        C_Timer.After(0.5, trigger)
    end
end)

-- For /lp why: what the boss prompts see right now.
function ns.PrintBossStatus(instance)
    if not enabled() then
        print("  Boss prompts: off (... menu)")
        return
    end
    local mapID = currentMapID()
    local names = {}
    local here = bossesOnMap(mapID)
    local ok, bosses = pcall(ns.GetCurrentBosses)
    for _, boss in ipairs(ok and bosses or {}) do
        if here[boss.id] then table.insert(names, boss.name) end
    end
    print(("  Map area: %s | bosses pinned here: %s"):format(tostring(mapID),
        #names > 0 and table.concat(names, ", ") or "none"))
    local offer = ns.GetBossOffer(instance)
    if not offer then
        print("  Next boss: none left (or none found)")
    elseif not offer.next.candidate then
        print(("  Next boss: %s (no build tagged, so no prompt)"):format(offer.next.boss.name))
    else
        local key = ns.TagKey(offer.next.boss.id, instance.difficulty)
        print(("  Next boss: %s -> %s%s"):format(offer.next.boss.name, offer.next.candidate.item.name,
            lastOffered[key] and " (offered before; offered again each time you re-enter its area)" or ""))
    end
end
