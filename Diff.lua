-- Diff.lua
-- Compare a saved loadout with your current talents, and draw the result
-- as a mini talent tree in a tooltip.
--
-- Two separate jobs, kept separate on purpose:
--   ns.ComputeDiff  - pure data: which nodes differ, and how
--   the tooltip     - drawing: turn that data into dots and lines
-- Keeping them apart means you can test/print the diff without any UI.

local addonName, ns = ...

------------------------------------------------------------------------
-- Part 1: computing the diff
------------------------------------------------------------------------
local COLORS = {
    same    = { 1.00, 0.82, 0.00 }, -- gold: in both
    added   = { 0.25, 1.00, 0.25 }, -- green: loadout has it, you don't
    removed = { 1.00, 0.25, 0.25 }, -- red: you have it, loadout doesn't
    changed = { 1.00, 0.55, 0.10 }, -- orange: different rank or choice
    none    = { 0.30, 0.30, 0.30 }, -- gray: in neither
}

-- Statuses that mean "the loadout has this talent" (for coloring edges).
local IN_LOADOUT = { same = true, added = true, changed = true }

local function isSubTreeActive(configID, subTreeID)
    if not subTreeID then
        return true -- not a hero talent, so always "active"
    end
    local info = C_Traits.GetSubTreeInfo and C_Traits.GetSubTreeInfo(configID, subTreeID)
    return (info and info.isActive) or false
end

-- Read one node from one config: its info, rank, and chosen entry.
-- Returns nil if the node doesn't exist.
local function readNode(configID, nodeID)
    local info = C_Traits.GetNodeInfo(configID, nodeID)
    if not info or not info.ID or info.ID == 0 then
        return nil
    end
    local rank = math.max(info.currentRank or 0, info.ranksPurchased or 0)
    if not isSubTreeActive(configID, info.subTreeID) then
        rank = 0 -- talents in an inactive hero tree don't count
    end
    -- For choice nodes (pick one of two), the entry tells us WHICH one.
    local entryID = (rank > 0 and info.activeEntry) and info.activeEntry.entryID or nil
    return info, rank, entryID
end

-- Entry -> definition -> spell -> name. The talent system has layers.
local function entryName(configID, entryID)
    if not entryID then return nil end
    local entry = C_Traits.GetEntryInfo(configID, entryID)
    local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    if not definition then return nil end
    if definition.overrideName and definition.overrideName ~= "" then
        return definition.overrideName
    end
    return definition.spellID and C_Spell.GetSpellName(definition.spellID)
end

local CHOICE_TYPE = Enum.TraitNodeType and Enum.TraitNodeType.Selection

-- Only compare WHICH option was picked on choice nodes. Other node types
-- can report different entry IDs for the same talent (tiered nodes), which
-- would show false differences.
local function classify(curRank, curEntry, newRank, newEntry, nodeType)
    if curRank == 0 and newRank == 0 then return "none" end
    if curRank == 0 then return "added" end
    if newRank == 0 then return "removed" end
    if curRank ~= newRank then return "changed" end
    if nodeType == CHOICE_TYPE and curEntry ~= newEntry then return "changed" end
    return "same"
end

local function subTreeName(configID, subTreeID)
    local info = C_Traits.GetSubTreeInfo and C_Traits.GetSubTreeInfo(configID, subTreeID)
    return info and info.name
end

------------------------------------------------------------------------
-- "Readers": one interface over two very different data sources
------------------------------------------------------------------------
-- A saved Blizzard loadout can be asked about each node directly. A
-- custom build is just a list of entries from its import code. Both get
-- wrapped in the same small interface, so the diff code below doesn't
-- care which one it's comparing against:
--   reader.read(nodeID, nodeInfo) -> rank, entryID
--   reader.heroActive(subTreeID)  -> is that hero tree chosen?

local function configReader(configID)
    return {
        read = function(nodeID)
            local _, rank, entryID = readNode(configID, nodeID)
            return rank or 0, entryID
        end,
        heroActive = function(subTreeID)
            return isSubTreeActive(configID, subTreeID)
        end,
    }
end

local function entriesReader(entries, activeConfigID)
    local byNode = {}
    for _, entry in ipairs(entries) do
        local node = byNode[entry.nodeID] or { rank = 0 }
        node.rank = node.rank + (entry.ranksPurchased or 0) + (entry.ranksGranted or 0)
        node.entryID = entry.selectionEntryID
        byNode[entry.nodeID] = node
    end

    -- Which hero tree does this build pick? The hidden hero-choice node's
    -- selected entry points at a sub-tree.
    local HERO_CHOICE_NODE = Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection
    local heroSubTree
    for nodeID, node in pairs(byNode) do
        local info = C_Traits.GetNodeInfo(activeConfigID, nodeID)
        if info and info.type == HERO_CHOICE_NODE and node.entryID then
            local entryInfo = C_Traits.GetEntryInfo(activeConfigID, node.entryID)
            heroSubTree = entryInfo and entryInfo.subTreeID
        end
    end

    return {
        read = function(nodeID, info)
            local node = byNode[nodeID]
            if not node then return 0 end
            if info.subTreeID and info.subTreeID ~= heroSubTree then return 0 end
            return node.rank, node.rank > 0 and node.entryID or nil
        end,
        heroActive = function(subTreeID)
            return subTreeID == heroSubTree
        end,
    }
end

local function computeDiff(reader)
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local configInfo = activeConfigID and C_Traits.GetConfigInfo(activeConfigID)
    local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
    if not treeID then
        return nil
    end

    -- The hidden node that holds your hero-tree choice; we don't draw it.
    local HERO_CHOICE_NODE = Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection

    local diff = { nodes = {}, added = {}, removed = {}, changed = {} }
    local currentHero, targetHero

    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info, curRank, curEntry = readNode(activeConfigID, nodeID)

        if info and info.isVisible and info.type ~= HERO_CHOICE_NODE then
            local newRank, newEntry = reader.read(nodeID, info)
            local subTreeID = info.subTreeID
            if subTreeID and isSubTreeActive(activeConfigID, subTreeID) then
                currentHero = subTreeName(activeConfigID, subTreeID)
            end
            if subTreeID and reader.heroActive(subTreeID) then
                targetHero = subTreeName(activeConfigID, subTreeID)
            end

            -- Only draw the hero tree the TARGET uses. (The other one sits
            -- in the same spot and would overlap.)
            if not subTreeID or reader.heroActive(subTreeID) then
                local status = classify(curRank or 0, curEntry, newRank or 0, newEntry, info.type)
                table.insert(diff.nodes, {
                    id = nodeID,
                    x = info.posX,
                    y = info.posY,
                    hero = subTreeID ~= nil,
                    status = status,
                    edges = info.visibleEdges or {},
                })

                -- Names for the text list under the tree. Every build uses
                -- the same class tree, so the active config can name them.
                local name
                if status == "added" or status == "changed" then
                    name = entryName(activeConfigID, newEntry or (info.entryIDs and info.entryIDs[1]))
                elseif status == "removed" then
                    name = entryName(activeConfigID, curEntry)
                end
                if name then
                    table.insert(diff[status], name)
                end
            end
        end
    end

    if currentHero and targetHero and currentHero ~= targetHero then
        diff.heroChange = currentHero .. " -> " .. targetHero
    end
    return diff
end

-- Compare an item (Blizzard loadout or custom build) with your talents.
-- Returns diff, or nil + an error message.
function ns.ComputeDiff(item)
    if item.build then
        local entries, err = ns.GetBuildEntries(item.build.code)
        if not entries then
            return nil, err
        end
        return computeDiff(entriesReader(entries, C_ClassTalents.GetActiveConfigID()))
    end
    return computeDiff(configReader(item.configID))
end

------------------------------------------------------------------------
-- Fingerprints: "do these two builds have exactly the same talents?"
------------------------------------------------------------------------
-- A fingerprint is a text summary of a build's PURCHASED talents, like
-- "82101:1:0,82102:2:0,82150:1:103452". Two builds with the same
-- fingerprint are identical, so matching becomes one string comparison.
-- Only purchased ranks count. Free/granted talents are the same for
-- everyone, and import codes and saved loadouts record them differently,
-- which would cause false mismatches. The hidden hero-tree choice node is
-- skipped for the same reason; the hero tree still shows through its
-- purchased talents.
local HERO_CHOICE = Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection

local function currentTree()
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetConfigInfo(configID)
    return configID, info and info.treeIDs and info.treeIDs[1]
end

-- nodeID, ranks, chosen entry (choice nodes only) -> "id:ranks:entry"
local function part(nodeID, ranks, nodeType, entryID)
    local choice = (nodeType == CHOICE_TYPE) and entryID or 0
    return nodeID .. ":" .. ranks .. ":" .. tostring(choice)
end

local function fingerprintConfig(configID, treeID)
    local parts = {}
    -- GetTreeNodes returns nodes in ascending ID order, so the result is
    -- always in the same order: equal builds give equal strings.
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        local ranks = info and info.ranksPurchased or 0
        if ranks > 0 and info.type ~= HERO_CHOICE and isSubTreeActive(configID, info.subTreeID) then
            table.insert(parts, part(nodeID, ranks, info.type, info.activeEntry and info.activeEntry.entryID))
        end
    end
    return table.concat(parts, ",")
end

local function fingerprintEntries(entries, activeConfigID, treeID)
    local byNode = {}
    for _, entry in ipairs(entries) do
        local node = byNode[entry.nodeID] or { ranks = 0 }
        node.ranks = node.ranks + (entry.ranksPurchased or 0)
        node.entryID = entry.selectionEntryID
        byNode[entry.nodeID] = node
    end

    -- Which hero tree does the build pick? (Same approach as entriesReader.)
    local heroSubTree
    for nodeID, node in pairs(byNode) do
        local info = C_Traits.GetNodeInfo(activeConfigID, nodeID)
        if info and info.type == HERO_CHOICE and node.entryID then
            local entryInfo = C_Traits.GetEntryInfo(activeConfigID, node.entryID)
            heroSubTree = entryInfo and entryInfo.subTreeID
        end
    end

    local parts = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local node = byNode[nodeID]
        if node and node.ranks > 0 then
            local info = C_Traits.GetNodeInfo(activeConfigID, nodeID)
            if info and info.type ~= HERO_CHOICE
                and (not info.subTreeID or info.subTreeID == heroSubTree) then
                table.insert(parts, part(nodeID, node.ranks, info.type, node.entryID))
            end
        end
    end
    return table.concat(parts, ",")
end

-- Caches. Custom builds never change for a given code, so they're cached
-- until you change spec. Blizzard loadouts and your current talents change
-- whenever talents do, so those caches are cleared on talent events.
local buildPrints, configPrints, currentPrint = {}, {}, nil

local function forgetTalentPrints()
    configPrints, currentPrint = {}, nil
end
-- Import.lua calls this right after changing talents itself, because the
-- game's "talents changed" events may not have arrived yet.
ns.ForgetTalentPrints = forgetTalentPrints

-- BUG FIX (v0.11): right after a loading screen, talent data can be
-- briefly unavailable, and every fingerprint comes out EMPTY. Two empty
-- fingerprints are equal, so the addon concluded "you already have this
-- build" and skipped the zone-in prompt. An empty fingerprint now means
-- "don't know yet": it's never cached and never counts as a match.
function ns.GetFingerprint(item)
    local activeConfigID, treeID = currentTree()
    if not treeID then return nil end
    if item.build then
        local code = item.build.code
        if buildPrints[code] == nil then
            local entries = ns.GetBuildEntries(code)
            if not entries then
                buildPrints[code] = false -- unreadable code: remember that
            else
                local print = fingerprintEntries(entries, activeConfigID, treeID)
                if print == "" then return nil end -- data not ready; try later
                buildPrints[code] = print
            end
        end
        return buildPrints[code] or nil
    end
    if not configPrints[item.configID] then
        local print = fingerprintConfig(item.configID, treeID)
        if print == "" then return nil end
        configPrints[item.configID] = print
    end
    return configPrints[item.configID]
end

-- Does this item have exactly your current talents?
-- Returns nil (not false) when it can't tell yet, so callers can wait or
-- fall back.
function ns.ItemMatchesCurrent(item)
    local activeConfigID, treeID = currentTree()
    if not treeID then return nil end
    if not currentPrint or currentPrint == "" then
        currentPrint = fingerprintConfig(activeConfigID, treeID)
    end
    if currentPrint == "" then return nil end -- your talents aren't loaded yet
    local itemPrint = ns.GetFingerprint(item)
    if itemPrint == nil then return nil end
    return itemPrint == currentPrint
end

-- Talents changed: forget cached prints and redraw, but only ONCE per
-- burst. Applying a build fires TRAIT_NODE_CHANGED for every single node,
-- and redrawing the list hundreds of times would freeze the game.
local refreshQueued = false
local function talentsChanged()
    forgetTalentPrints()
    if not refreshQueued then
        refreshQueued = true
        C_Timer.After(0.2, function()
            refreshQueued = false
            ns.Notify()
        end)
    end
end
ns.On("TRAIT_NODE_CHANGED", talentsChanged)
ns.On("TRAIT_CONFIG_UPDATED", talentsChanged)
ns.On("TRAIT_CONFIG_LIST_UPDATED", talentsChanged)
ns.On("ACTIVE_COMBAT_CONFIG_CHANGED", talentsChanged)
ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        buildPrints = {} -- different spec, different tree
        talentsChanged()
    end
end)

------------------------------------------------------------------------
-- Part 2: laying out the mini tree
------------------------------------------------------------------------
-- Talent nodes come with posX/posY in the game's own coordinate space.
-- We squeeze them into our small map. The class tree and spec tree sit
-- side by side in those coordinates, separated by the widest horizontal
-- gap, so we find that gap, split there, and put the hero tree between.
local MAP_W, MAP_H = 460, 210
local PAD = 6

-- Scale a group of nodes to fit a rectangle (region = {x, y, w, h}).
local function placeGroup(nodes, region, positions)
    if #nodes == 0 then return end
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(nodes) do
        minX, maxX = math.min(minX, n.x), math.max(maxX, n.x)
        minY, maxY = math.min(minY, n.y), math.max(maxY, n.y)
    end
    local spanX, spanY = maxX - minX, maxY - minY
    for _, n in ipairs(nodes) do
        -- If a group is a single column/row, center it instead of dividing by 0.
        local fx = spanX > 0 and (n.x - minX) / spanX or 0.5
        local fy = spanY > 0 and (n.y - minY) / spanY or 0.5
        positions[n.id] = {
            x = region[1] + PAD + fx * (region[3] - 2 * PAD),
            y = region[2] + PAD + fy * (region[4] - 2 * PAD),
        }
    end
end

local function layout(nodes)
    local main, hero = {}, {}
    for _, n in ipairs(nodes) do
        table.insert(n.hero and hero or main, n)
    end

    -- Find the widest gap between neighboring x positions.
    table.sort(main, function(a, b) return a.x < b.x end)
    local splitX, widest = nil, 0
    for i = 2, #main do
        local gap = main[i].x - main[i - 1].x
        if gap > widest then
            widest, splitX = gap, main[i - 1].x
        end
    end

    local classNodes, specNodes = {}, {}
    for _, n in ipairs(main) do
        table.insert((splitX and n.x > splitX) and specNodes or classNodes, n)
    end

    local positions = {}
    local hasHero = #hero > 0
    local side = hasHero and 180 or 225
    local middle = MAP_W - 2 * side
    placeGroup(classNodes, { 0, 0, side, MAP_H }, positions)
    placeGroup(specNodes, { MAP_W - side, 0, side, MAP_H }, positions)
    if hasHero then
        placeGroup(hero, { side + 10, MAP_H * 0.15, middle - 20, MAP_H * 0.7 }, positions)
    end
    return positions
end

------------------------------------------------------------------------
-- Part 3: the tooltip frame
------------------------------------------------------------------------
-- Blizzard's own tooltip frame (the same border as GameTooltip).
local tip, isTooltipTemplate = ns.Style.CreateTooltipFrame("LoadoutPlannerDiffTip", UIParent)
tip:SetFrameStrata("TOOLTIP")
tip:SetClampedToScreen(true)
tip:SetWidth(MAP_W + 20)
if not isTooltipTemplate then
    tip:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    tip:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
end
tip:Hide()

tip.header = tip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tip.header:SetPoint("TOPLEFT", 10, -9)

tip.summary = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tip.summary:SetPoint("TOPLEFT", tip.header, "BOTTOMLEFT", 0, -4)

local map = CreateFrame("Frame", nil, tip)
map:SetSize(MAP_W, MAP_H)
map:SetPoint("TOPLEFT", 10, -44)

tip.list = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tip.list:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -8)
tip.list:SetWidth(MAP_W)
tip.list:SetJustifyH("LEFT")

tip.legend = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tip.legend:SetPoint("BOTTOMLEFT", 10, 8)
local function colorCode(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end
tip.legend:SetText(
    colorCode(COLORS.same) .. "same|r   "
    .. colorCode(COLORS.added) .. "loadout adds|r   "
    .. colorCode(COLORS.removed) .. "loadout removes|r   "
    .. colorCode(COLORS.changed) .. "rank/choice differs|r")

-- Pools of dots and lines, reused on every hover (frames and textures
-- can't be deleted, so we create them once and recycle).
local dots, lines = {}, {}

local function getDot(i)
    if not dots[i] then
        local dot = map:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        -- A mask texture clips the square color texture into a circle.
        local mask = map:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(dot)
        dot:AddMaskTexture(mask)
        dots[i] = dot
    end
    return dots[i]
end

local function getLine(i)
    if not lines[i] then
        local line = map:CreateLine(nil, "ARTWORK")
        line:SetThickness(2)
        lines[i] = line
    end
    return lines[i]
end

-- "+ Name, Name" with a cap so the tooltip doesn't grow forever.
local function nameLine(prefix, color, names, cap)
    if #names == 0 then return nil end
    local shown = {}
    for i = 1, math.min(#names, cap) do
        shown[i] = names[i]
    end
    local text = table.concat(shown, ", ")
    if #names > cap then
        text = text .. (" and %d more"):format(#names - cap)
    end
    return colorCode(color) .. prefix .. " " .. text .. "|r"
end

-- Position the tooltip to the LEFT of the row, over the talent window.
local function placeTip(owner)
    tip:ClearAllPoints()
    tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -8, 0)
    tip:Show()
end

function ns.ShowDiff(owner, loadout)
    tip.header:SetText(loadout.name)
    local diff, err = ns.ComputeDiff(loadout)
    if not diff then
        -- Can't compare (e.g. the build is for another spec): say why.
        tip.summary:SetText("|cffff8080" .. (err or "Talent data not available.") .. "|r")
        map:Hide()
        tip.list:SetText("")
        tip.legend:Hide()
        tip:SetHeight(50)
        placeTip(owner)
        return
    end
    map:Show()
    tip.legend:Show()
    local changes = #diff.added + #diff.removed + #diff.changed
    if changes == 0 and not diff.heroChange then
        tip.summary:SetText("Matches your current talents.")
    else
        tip.summary:SetText(("Compared to your current talents:  %s+%d|r  %s-%d|r  %s~%d|r"):format(
            colorCode(COLORS.added), #diff.added,
            colorCode(COLORS.removed), #diff.removed,
            colorCode(COLORS.changed), #diff.changed))
    end

    -- Draw edges first so dots sit on top of them.
    local positions = layout(diff.nodes)
    local statusByID = {}
    for _, n in ipairs(diff.nodes) do
        statusByID[n.id] = n.status
    end

    local lineCount = 0
    for _, n in ipairs(diff.nodes) do
        for _, edge in ipairs(n.edges) do
            local from, to = positions[n.id], positions[edge.targetNode]
            if from and to then
                lineCount = lineCount + 1
                local line = getLine(lineCount)
                local lit = IN_LOADOUT[n.status] and IN_LOADOUT[statusByID[edge.targetNode]]
                if lit then
                    line:SetColorTexture(1, 0.82, 0, 0.8)
                else
                    line:SetColorTexture(0.4, 0.4, 0.4, 0.35)
                end
                -- Map y grows downward, WoW's y grows upward: hence the minus.
                line:SetStartPoint("TOPLEFT", map, from.x, -from.y)
                line:SetEndPoint("TOPLEFT", map, to.x, -to.y)
                line:Show()
            end
        end
    end
    for i = lineCount + 1, #lines do
        lines[i]:Hide()
    end

    local dotCount = 0
    for _, n in ipairs(diff.nodes) do
        local pos = positions[n.id]
        if pos then
            dotCount = dotCount + 1
            local dot = getDot(dotCount)
            local c = COLORS[n.status]
            dot:SetColorTexture(c[1], c[2], c[3], 1)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", map, "TOPLEFT", pos.x, -pos.y)
            dot:Show()
        end
    end
    for i = dotCount + 1, #dots do
        dots[i]:Hide()
    end

    -- Text list of changes under the tree.
    local textLines = {}
    if diff.heroChange then
        table.insert(textLines, colorCode(COLORS.changed) .. "Hero tree: " .. diff.heroChange .. "|r")
    end
    for _, textLine in ipairs({
        nameLine("+", COLORS.added, diff.added, 8) or false,
        nameLine("-", COLORS.removed, diff.removed, 8) or false,
        nameLine("~", COLORS.changed, diff.changed, 6) or false,
    }) do
        if textLine then
            table.insert(textLines, textLine)
        end
    end
    tip.list:SetText(table.concat(textLines, "\n"))

    local listHeight = #textLines > 0 and (tip.list:GetStringHeight() + 8) or 0
    tip:SetHeight(44 + MAP_H + listHeight + 26)

    placeTip(owner)
end

function ns.HideDiff()
    tip:Hide()
end
