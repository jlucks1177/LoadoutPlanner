-- TagPanel.lua
-- Tagging, as a panel instead of nested menus. (Four levels of submenus,
-- Tag > Raid > Boss > Difficulty, kept flipping back over each other at
-- the right edge of the screen.)
--
-- One flat, scrollable list: each raid (whole raid + every boss) and each
-- dungeon is a row, with a button per difficulty:
--   green = tagged to THIS build (click to untag)
--   gold  = tagged to ANOTHER build (hover to see which; click to replace)
--   gray  = not tagged (click to tag)

local addonName, ns = ...

local WIDTH, HEIGHT = 440, 520
local ROW_HEIGHT = 24
local CHIP_W, CHIP_H, CHIP_GAP = 36, 18, 2

-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local panel = ns.Style.CreatePanel("LoadoutPlannerTagPanel", UIParent)
panel:SetSize(WIDTH, HEIGHT)
panel:SetFrameStrata("FULLSCREEN")
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:Hide()
table.insert(UISpecialFrames, "LoadoutPlannerTagPanel") -- Escape closes it

local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
help:SetPoint("TOPLEFT", 14, ns.Style.CONTENT_TOP)
help:SetPoint("RIGHT", -14, 0)
help:SetJustifyH("LEFT")
help:SetText("Click a difficulty to tag or untag. |cff40ff40Green|r = this build, "
    .. "|cffffd100gold|r = another build (hover to see which). Works from anywhere.")


local scroll = ns.Style.CreateScrollFrame(panel, "LoadoutPlannerTagScroll")
scroll:SetPoint("TOPLEFT", 12, -62)
scroll:SetPoint("BOTTOMRIGHT", -24, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 36, 1)
scroll:SetScrollChild(content)

local current -- the item being tagged

------------------------------------------------------------------------
-- Building the list
------------------------------------------------------------------------
-- Rows: { header = "text" } or
--       { kind, id, label, icon, instanceType, text, indent }
local function buildRows()
    local rows = {}
    local season = ns.GetSeason()
    local inSeason = {}

    local function addTargets(instanceName, instanceID, icon, instanceType, bosses)
        table.insert(rows, { header = instanceName })
        table.insert(rows, {
            kind = "instances", id = instanceID, label = instanceName, icon = icon,
            instanceType = instanceType,
            text = instanceType == "raid" and "Whole raid" or "Whole dungeon",
        })
        for i, boss in ipairs(bosses or {}) do
            table.insert(rows, {
                kind = "bosses", id = boss.id or boss.encounterID, label = boss.name,
                icon = ns.GetBossIcon(boss.name) or icon, instanceType = instanceType,
                text = ("%d. %s"):format(i, boss.name), indent = 12,
            })
        end
    end

    -- Whole categories first: "every dungeon" / "every raid".
    table.insert(rows, { header = "All instances" })
    for _, category in ipairs(ns.CATEGORIES) do
        table.insert(rows, {
            kind = "categories", id = category.id, label = category.label, icon = category.icon,
            instanceType = category.id, text = category.label,
        })
    end

    for _, raid in ipairs(season.raids) do
        if raid.mapID then
            inSeason[raid.mapID] = true
            addTargets(raid.name, raid.mapID, raid.icon, "raid", raid.bosses)
        end
    end

    -- Dungeons: one row each, under a single header.
    local dungeons = {}
    for _, dungeon in ipairs(season.dungeons) do
        if dungeon.mapID then
            inSeason[dungeon.mapID] = true
            table.insert(dungeons, {
                kind = "instances", id = dungeon.mapID, label = dungeon.name, icon = dungeon.icon,
                instanceType = "party", text = dungeon.name,
            })
        end
    end
    if #dungeons > 0 then
        table.insert(rows, { header = "Dungeons" })
        for _, row in ipairs(dungeons) do
            table.insert(rows, row)
        end
    end

    -- Where you are now, if it isn't one of this season's instances
    -- (older content), goes first.
    local here = ns.GetCurrentInstance()
    if here and not inSeason[here.id] then
        local hereRows = {}
        local saved = rows
        rows = hereRows
        addTargets("Here: " .. here.name, here.id, ns.GetCurrentInstanceIcon(), here.type, ns.GetCurrentBosses())
        hereRows[2].label = here.name -- tag label without the "Here:" prefix
        for _, row in ipairs(saved) do
            table.insert(hereRows, row)
        end
    end
    return rows
end

------------------------------------------------------------------------
-- Difficulty buttons ("chips")
------------------------------------------------------------------------
local COLORS = {
    mine  = { bg = { 0.15, 0.55, 0.15, 1 }, text = { 1, 1, 1 } },
    other = { bg = { 0.45, 0.35, 0.08, 1 }, text = { 1, 0.82, 0 } },
    empty = { bg = { 0.14, 0.14, 0.14, 1 }, text = { 0.6, 0.6, 0.6 } },
}

local function chipState(target, difficultyID)
    local spec = ns.GetSpecData()
    local ref = spec and spec[target.kind][ns.TagKey(target.id, difficultyID)]
    local item = ref and ns.ResolveRef(ref)
    if not item then
        return "empty"
    end
    return (item.key == current.key) and "mine" or "other", item
end

local function createChip(parent)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetSize(CHIP_W, CHIP_H)
    chip.bg = chip:CreateTexture(nil, "BACKGROUND")
    chip.bg:SetAllPoints()
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("CENTER")
    chip:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    chip:SetScript("OnClick", function(self)
        local target, difficultyID = self.target, self.difficultyID
        local state = chipState(target, difficultyID)
        if state == "mine" then
            ns.ClearTag(target.kind, ns.TagKey(target.id, difficultyID))
        else
            ns.SetTag(target.kind, target.id, current, target.label, target.icon, difficultyID)
        end
        -- (SetTag/ClearTag call ns.Notify, which refreshes this panel too.)
    end)
    chip:SetScript("OnEnter", function(self)
        local state, other = chipState(self.target, self.difficultyID)
        local difficulty = self.difficultyID and ns.DIFFICULTY_BY_ID[self.difficultyID]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("%s, %s"):format(self.target.label, difficulty and difficulty.name or "any difficulty"))
        local scope = self.target.kind == "categories" and "any dungeon" or "this dungeon"
        if self.difficultyID == 8 then
            GameTooltip:AddLine(("Offered when you enter %s on any difficulty,\nbefore a key starts (talents lock once it does)."):format(scope), 0.8, 0.8, 0.8)
        elseif self.target.kind == "categories" then
            GameTooltip:AddLine(("Offered in every %s on this difficulty,\nunless a more specific tag applies there."):format(
                self.target.id == "party" and "dungeon" or "raid"), 0.8, 0.8, 0.8)
        end
        if state == "mine" then
            GameTooltip:AddLine("Tagged to this build. Click to remove.", 0.25, 1, 0.25)
        elseif state == "other" then
            GameTooltip:AddLine("Tagged to: " .. other.name, 1, 0.82, 0)
            GameTooltip:AddLine("Click to tag this build here instead.", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Click to tag this build here.", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", GameTooltip_Hide)
    return chip
end

local function styleChip(chip, target, difficultyID, text)
    chip.target, chip.difficultyID = target, difficultyID
    chip.text:SetText(text)
    local color = COLORS[chipState(target, difficultyID)]
    chip.bg:SetColorTexture(unpack(color.bg))
    chip.text:SetTextColor(unpack(color.text))
    chip:Show()
end

------------------------------------------------------------------------
-- Rows (pooled)
------------------------------------------------------------------------
local rowFrames = {}

local function createRowFrame()
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(content:GetWidth(), ROW_HEIGHT)

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 2, 5)
    -- A gold rule under each raid/dungeon name, like the talent window's headers.
    row.rule = row:CreateTexture(nil, "BORDER")
    row.rule:SetPoint("BOTTOMLEFT", 0, 1)
    row.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    row.rule:SetHeight(2)
    ns.Style.SetAtlas(row.rule, "header-horizontal-rule", function(t)
        t:SetColorTexture(1, 0.82, 0, 0.35)
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.chips = {}
    for i = 5, 1, -1 do -- laid out from the right edge
        local chip = createChip(row)
        if i == 5 then
            chip:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        else
            chip:SetPoint("RIGHT", row.chips[i + 1], "LEFT", -CHIP_GAP, 0)
        end
        row.chips[i] = chip
    end
    row.text:SetPoint("RIGHT", row.chips[1], "LEFT", -6, 0)
    return row
end

local function refresh()
    if not panel:IsShown() or not current then return end
    panel.title:SetText("Tag: " .. current.name)

    local rows = buildRows()
    for i, data in ipairs(rows) do
        rowFrames[i] = rowFrames[i] or createRowFrame()
        local row = rowFrames[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

        if data.header then
            row.header:SetText(data.header)
            row.header:Show()
            row.rule:Show()
            row.icon:Hide()
            row.text:Hide()
            for _, chip in ipairs(row.chips) do chip:Hide() end
        else
            row.header:Hide()
            row.rule:Hide()
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", 4 + (data.indent or 0), 0)
            ns.SetIcon(row.icon, data.icon or 134400, true)
            row.icon:Show()
            row.text:SetText(data.text)
            row.text:Show()

            -- "Any" first, then each difficulty for this kind of instance.
            styleChip(row.chips[1], data, nil, "Any")
            local difficulties = ns.DIFFICULTIES[data.instanceType] or {}
            for c = 2, 5 do
                local difficulty = difficulties[c - 1]
                if difficulty then
                    styleChip(row.chips[c], data, difficulty.id, difficulty.short)
                else
                    row.chips[c]:Hide()
                end
            end
        end
        row:Show()
    end
    for i = #rows + 1, #rowFrames do
        rowFrames[i]:Hide()
    end
    content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
end

ns.OnRefresh(refresh)
panel:SetScript("OnShow", refresh)

-- Open the panel for an item (Blizzard loadout or custom build), beside
-- LoadoutPlanner's window, on the side facing the middle of the screen.
function ns.CloseTagPanel()
    panel:Hide()
end

function ns.OpenTagPanel(item)
    current = item
    if ns.CloseTopBuilds then ns.CloseTopBuilds() end -- they open in the same spot
    panel:ClearAllPoints()
    local window = ns.window
    if window and window:IsShown() then
        panel:SetPoint("TOPRIGHT", window, "TOPLEFT", -6, 0)
    else
        panel:SetPoint("CENTER")
    end
    ns.GetSeason(true) -- make sure the season list is fresh
    if panel:IsShown() then
        refresh()
    else
        panel:Show()
    end
end

-- Close along with the talent window.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    if PlayerSpellsFrame then
        PlayerSpellsFrame:HookScript("OnHide", function() panel:Hide() end)
    end
end)
