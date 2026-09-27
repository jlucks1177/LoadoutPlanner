-- IconPicker.lua
-- An icon grid that lives INSIDE the build editor (no separate window).
--
-- Order, most useful first:
--   1. Current raid(s): the raid's icon, then each boss's square icon,
--      numbered in kill order
--   2. This season's dungeons            - labeled with short initials
--   3. Your specializations
--   4. Your talents (every talent in your class tree)
--   5. All icons (thousands, from Blizzard's macro icon list)
-- Search matches boss, dungeon, spec, and talent NAMES. A number searches
-- spell IDs and item IDs. (Most icons have no name, so there's nothing
-- to search in the "all icons" list; that's why the old search failed.)
--
-- The grid is VIRTUALIZED: only enough rows to fill the view are ever
-- created, and scrolling just changes what they show. Thousands of icons
-- cost the same as a hundred.

local addonName, ns = ...

local COLS, SIZE, GAP = 11, 34, 4
local ROW_H = SIZE + GAP
local VISIBLE_ROWS = 8

------------------------------------------------------------------------
-- Data sources (raids, dungeons, boss icons: see Journal.lua)
------------------------------------------------------------------------
-- Every talent in your class tree, alphabetically, without duplicates.
local function readTalents()
    local list, seen = {}, {}
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetConfigInfo(configID)
    local treeID = info and info.treeIDs and info.treeIDs[1]
    if not treeID then return list end

    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local node = C_Traits.GetNodeInfo(configID, nodeID)
        if node and node.isVisible then
            for _, entryID in ipairs(node.entryIDs or {}) do
                local entry = C_Traits.GetEntryInfo(configID, entryID)
                local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                local spellID = def and def.spellID
                if spellID and not seen[spellID] then
                    seen[spellID] = true -- a set: "have we added this spell yet?"
                    local icon = (def.overrideIcon and def.overrideIcon ~= 0) and def.overrideIcon
                        or C_Spell.GetSpellTexture(spellID)
                    local name = (def.overrideName and def.overrideName ~= "") and def.overrideName
                        or C_Spell.GetSpellName(spellID)
                    if icon and name then
                        table.insert(list, { icon = icon, name = name })
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Blizzard's full icon list, loaded once (it's large).
local allIcons
local function readAllIcons()
    if allIcons then return allIcons end
    allIcons = {}
    -- These fill the table you pass in. VERIFY in 12.x if this section is empty.
    if GetLooseMacroIcons then GetLooseMacroIcons(allIcons) end
    if GetMacroIcons then GetMacroIcons(allIcons) end
    return allIcons
end

-- Older entries are bare names; newer ones are numeric file IDs.
local function toTexture(icon)
    if type(icon) == "string" and not icon:find("[\\/]") then
        return "Interface\\Icons\\" .. icon
    end
    return icon
end

------------------------------------------------------------------------
-- Turning data into rows
------------------------------------------------------------------------
-- The grid shows a flat list of rows. A row is either a section header
-- ({ header = "..." }) or up to COLS icons ({ icons = {...} }). The huge
-- "all icons" section stores only a start index per row ({ allStart = n })
-- instead of building thousands of small tables.

local function addSection(rows, jumps, title, icons)
    if #icons == 0 then return end
    table.insert(rows, { header = title })
    jumps[title] = #rows -- remember where this section starts
    for i = 1, #icons, COLS do -- step through the list COLS at a time
        local row = { icons = {} }
        for j = i, math.min(i + COLS - 1, #icons) do
            table.insert(row.icons, icons[j])
        end
        table.insert(rows, row)
    end
end

local function matches(item, query)
    return item.name and item.name:lower():find(query, 1, true) -- plain find, no patterns
end

local function filtered(list, query)
    if not query then return list end
    local result = {}
    for _, item in ipairs(list) do
        if matches(item, query) then
            table.insert(result, item)
        end
    end
    return result
end

local function buildRows(query)
    local rows, jumps = {}, {}
    local season = ns.GetSeason()

    -- A number searches spell and item IDs directly.
    local id = query and tonumber(query)
    if id then
        local found = {}
        local spellIcon = C_Spell.GetSpellTexture(id)
        if spellIcon then
            table.insert(found, { icon = spellIcon, name = "Spell: " .. (C_Spell.GetSpellName(id) or id) })
        end
        local itemIcon = C_Item.GetItemIconByID(id)
        if itemIcon then
            table.insert(found, { icon = itemIcon, name = "Item: " .. (C_Item.GetItemNameByID(id) or id) })
        end
        addSection(rows, jumps, "ID " .. id, found)
    end

    for _, raid in ipairs(season.raids) do
        -- The raid's own icon first, then its bosses.
        local icons = {}
        if raid.icon then
            table.insert(icons, { icon = raid.icon, name = raid.name, label = "R" })
        end
        for _, boss in ipairs(raid.bosses) do
            if boss.icon then
                table.insert(icons, boss)
            end
        end
        addSection(rows, jumps, "Raid: " .. raid.name, filtered(icons, query))
    end

    local dungeons = {}
    for _, dungeon in ipairs(season.dungeons) do
        if dungeon.icon then
            table.insert(dungeons, { icon = dungeon.icon, name = dungeon.name, label = ns.Initials(dungeon.name) })
        end
    end
    addSection(rows, jumps, "Dungeons", filtered(dungeons, query))
    addSection(rows, jumps, "Specializations", filtered(ns.GetSpecList(), query))
    addSection(rows, jumps, "Talents", filtered(readTalents(), query))

    if not query then
        local icons = readAllIcons()
        if #icons > 0 then
            table.insert(rows, { header = ("All icons (%d)"):format(#icons) })
            jumps["All icons"] = #rows
            for i = 1, #icons, COLS do
                table.insert(rows, { allStart = i })
            end
        end
    end

    if #rows == 0 then
        table.insert(rows, { header = "No matches. Try a boss, dungeon, talent, or a spell/item ID." })
    end
    return rows, jumps
end

------------------------------------------------------------------------
-- The widget
------------------------------------------------------------------------
-- Creates the picker inside `parent`. onPick(texture) is called on click.
-- Returns the picker frame, with :Open(selectedTexture) to (re)load it.
function ns.CreateIconPicker(parent, onPick)
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetSize(COLS * ROW_H - GAP + 22, 58 + VISIBLE_ROWS * ROW_H)

    local rows, jumps = {}, {}
    local offset = 0 -- index of the first visible row, minus one
    local selected

    -- Search box
    local search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    search:SetSize(picker:GetWidth() - 8, 20)
    search:SetPoint("TOPLEFT", 6, 0)
    search:SetAutoFocus(false)
    if search.Instructions then
        search.Instructions:SetText("Search bosses, dungeons, talents, or a spell/item ID")
    end

    -- Jump buttons: scroll straight to a section.
    local jumpBar = CreateFrame("Frame", nil, picker)
    jumpBar:SetPoint("TOPLEFT", 0, -26)
    jumpBar:SetSize(picker:GetWidth(), 22)

    -- Grid area
    local grid = CreateFrame("Frame", nil, picker)
    grid:SetPoint("TOPLEFT", 0, -54)
    grid:SetSize(COLS * ROW_H - GAP, VISIBLE_ROWS * ROW_H)
    grid:EnableMouseWheel(true)

    -- Scroll bar: a vertical Slider whose value is the first visible row.
    local bar = CreateFrame("Slider", nil, picker)
    bar:SetPoint("TOPLEFT", grid, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", grid, "BOTTOMRIGHT", 6, 0)
    bar:SetWidth(8)
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    -- Styled like Blizzard's minimal scroll bar (see Style.lua).
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    ns.Style.SetAtlas(track, "!minimal-scrollbar-track-middle", function(t)
        t:SetColorTexture(0, 0, 0, 0.4)
    end)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 32)
    thumb:SetColorTexture(0.75, 0.62, 0.35, 0.9)
    bar:SetThumbTexture(thumb)

    -- The pool: VISIBLE_ROWS row frames, each able to be a header or icons.
    local rowFrames = {}
    for r = 1, VISIBLE_ROWS do
        local rowFrame = CreateFrame("Frame", nil, grid)
        rowFrame:SetSize(grid:GetWidth(), SIZE)
        rowFrame:SetPoint("TOPLEFT", 0, -(r - 1) * ROW_H)

        rowFrame.header = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rowFrame.header:SetPoint("BOTTOMLEFT", 2, 4)

        rowFrame.buttons = {}
        for c = 1, COLS do
            local button = CreateFrame("Button", nil, rowFrame)
            button:SetSize(SIZE, SIZE)
            button:SetPoint("LEFT", (c - 1) * ROW_H, 0)
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints()
            button.label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            button.label:SetPoint("BOTTOM", 0, 2)
            -- The chosen icon gets the talent window's gold node ring.
            button.selectedGlow = button:CreateTexture(nil, "OVERLAY")
            button.selectedGlow:SetAllPoints()
            ns.Style.SetAtlas(button.selectedGlow, "talents-node-pvpflyout-yellow", function(t)
                t:SetTexture("Interface\\Buttons\\CheckButtonHilight")
                t:SetBlendMode("ADD")
            end)
            button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            button:SetScript("OnClick", function(self)
                selected = self.texture
                picker:Render()
                onPick(self.texture)
            end)
            button:SetScript("OnEnter", function(self)
                if self.name then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self.name)
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            rowFrame.buttons[c] = button
        end
        rowFrames[r] = rowFrame
    end

    local function fillButton(button, icon, name, label)
        button.texture = toTexture(icon)
        button.name = name
        ns.SetIcon(button.icon, button.texture)
        button.label:SetText(label or "")
        button.selectedGlow:SetShown(selected ~= nil and button.texture == selected)
        button:Show()
    end

    -- Draw the rows currently in view.
    function picker:Render()
        for r = 1, VISIBLE_ROWS do
            local rowFrame = rowFrames[r]
            local data = rows[offset + r]
            rowFrame.header:SetText(data and data.header or "")
            for c, button in ipairs(rowFrame.buttons) do
                if data and data.icons and data.icons[c] then
                    local item = data.icons[c]
                    fillButton(button, item.icon, item.name, item.label)
                elseif data and data.allStart and allIcons[data.allStart + c - 1] then
                    fillButton(button, allIcons[data.allStart + c - 1])
                else
                    button:Hide()
                end
            end
        end
    end

    local function scrollTo(rowOffset)
        bar:SetValue(rowOffset) -- OnValueChanged does the rest
    end

    bar:SetScript("OnValueChanged", function(_, value)
        offset = math.floor(value + 0.5)
        picker:Render()
    end)
    grid:SetScript("OnMouseWheel", function(_, delta)
        scrollTo(offset - delta * 2) -- two rows per notch
    end)

    local jumpButtons = {}
    local function rebuildJumps()
        for _, b in ipairs(jumpButtons) do b:Hide() end
        local x, n = 0, 0
        -- Fixed order; only sections that exist get a button.
        local wanted = { { "Raid", "Raid:" }, { "Dungeons", "Dungeons" }, { "Specs", "Specializations" },
            { "Talents", "Talents" }, { "All", "All icons" } }
        for _, pair in ipairs(wanted) do
            local text, prefix = pair[1], pair[2]
            local target
            for title, index in pairs(jumps) do
                if title:sub(1, #prefix) == prefix and (not target or index < target) then
                    target = index
                end
            end
            if target then
                n = n + 1
                local b = jumpButtons[n] or CreateFrame("Button", nil, jumpBar, "UIPanelButtonTemplate")
                jumpButtons[n] = b
                b:SetSize(72, 20)
                b:ClearAllPoints()
                b:SetPoint("LEFT", x + 6, 0)
                b:SetText(text)
                b:SetScript("OnClick", function() scrollTo(target - 1) end)
                b:Show()
                x = x + 76
            end
        end
    end

    local function reload()
        local text = strtrim(search:GetText() or ""):lower()
        rows, jumps = buildRows(text ~= "" and text or nil)
        bar:SetMinMaxValues(0, math.max(0, #rows - VISIBLE_ROWS))
        rebuildJumps()
        -- SetValue(0) doesn't fire OnValueChanged if the bar is already at
        -- 0, so set the offset ourselves and draw directly.
        offset = 0
        bar:SetValue(0)
        picker:Render()
    end

    -- SearchBoxTemplate has its own OnTextChanged (clear button, hint
    -- text); HookScript adds ours after it instead of replacing it.
    search:HookScript("OnTextChanged", reload)

    function picker:Open(selectedTexture)
        selected = selectedTexture
        ns.GetSeason(true) -- re-read: the season can change between sessions
        search:SetText("") -- triggers reload via OnTextChanged
        reload()
    end

    function picker:SetSelected(texture)
        selected = texture
        picker:Render()
    end

    return picker
end
