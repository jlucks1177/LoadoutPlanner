-- UI.lua
-- The list inside LoadoutPlanner's window: Blizzard's saved loadouts, then
-- your own build groups, plus their right-click menus and popups.
-- Rows: left-click = load, right-click = options, hover = compare.

local addonName, ns = ...

local ROW_HEIGHT = 44
local HEADER_HEIGHT = 22

-- The window itself (frame, header, placement) is built in Window.lua.
local panel = ns.window
local LIST_WIDTH = panel:GetWidth() - 34

------------------------------------------------------------------------
-- Scrolling list
------------------------------------------------------------------------
-- The modern thin scroll bar (Style.lua), like the talent window's lists.
local scroll = ns.Style.CreateScrollFrame(panel, "LoadoutPlannerScrollFrame")
scroll:SetPoint("TOPLEFT", 10, ns.LIST_TOP)
scroll:SetPoint("BOTTOMRIGHT", -24, ns.LIST_BOTTOM)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(LIST_WIDTH, 1)
scroll:SetScrollChild(content)

------------------------------------------------------------------------
-- Popups (Blizzard's StaticPopup system; see Context.lua for the basics)
------------------------------------------------------------------------
-- The edit box field was renamed at some point; accept either spelling.
local function popupEditBox(dialog)
    return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

local function basePopup(extra)
    local popup = {
        button1 = ACCEPT, button2 = CANCEL,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    for k, v in pairs(extra) do
        popup[k] = v
    end
    return popup
end

StaticPopupDialogs.LOADOUTPLANNER_NEW_GROUP = basePopup({
    text = "Name for the new group:",
    hasEditBox = true,
    OnAccept = function(dialog)
        local name = strtrim(popupEditBox(dialog):GetText())
        if name ~= "" then
            ns.GetOrCreateGroup(name)
        end
    end,
})

StaticPopupDialogs.LOADOUTPLANNER_RENAME_GROUP = basePopup({
    text = "Rename group:",
    hasEditBox = true,
    OnShow = function(dialog, data)
        popupEditBox(dialog):SetText((data or dialog.data).name)
    end,
    OnAccept = function(dialog, data)
        ns.RenameGroup(data or dialog.data, strtrim(popupEditBox(dialog):GetText()))
    end,
})

StaticPopupDialogs.LOADOUTPLANNER_DELETE_GROUP = basePopup({
    text = "Delete group |cffffd100%s|r and its %s build(s)?",
    OnAccept = function(dialog, data)
        ns.DeleteGroup(data or dialog.data)
    end,
})

StaticPopupDialogs.LOADOUTPLANNER_DELETE_BUILD = basePopup({
    text = "Delete build |cffffd100%s|r?",
    OnAccept = function(dialog, data)
        ns.DeleteBuild(data or dialog.data)
    end,
})

StaticPopupDialogs.LOADOUTPLANNER_COPY = basePopup({
    text = "Import code for |cffffd100%s|r\n(Ctrl+C to copy)",
    button1 = CLOSE, button2 = nil,
    hasEditBox = true, editBoxWidth = 320,
    OnShow = function(dialog, data)
        local box = popupEditBox(dialog)
        box:SetText((data or dialog.data).code)
        box:HighlightText()
        box:SetFocus()
    end,
})

------------------------------------------------------------------------
-- Right-click menus
------------------------------------------------------------------------
-- Tagging happens in its own panel (TagPanel.lua): the old nested
-- Tag > Raid > Boss > Difficulty menus overlapped each other.
local function addTagOptions(root, item)
    root:CreateButton("Tag...", function() ns.OpenTagPanel(item) end)

    local tags = ns.GetTagsForItem(item.key)
    if #tags > 0 then
        local removeMenu = root:CreateButton("Remove tag")
        for _, tag in ipairs(tags) do
            removeMenu:CreateButton(tag.label, function()
                ns.ClearTag(tag.kind, tag.key)
            end)
        end
    end
end

local function openItemMenu(owner, item)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(item.name)
        if item.build then
            root:CreateButton("Edit...", function() ns.OpenEditor({ build = item.build }) end)
            root:CreateButton("Copy import code", function()
                StaticPopup_Show("LOADOUTPLANNER_COPY", item.name, nil, item.build)
            end)
            root:CreateButton("Move up", function() ns.MoveBuild(item.build, -1) end)
            root:CreateButton("Move down", function() ns.MoveBuild(item.build, 1) end)
        else
            root:CreateButton("Save as custom build...", function()
                local ok, code = pcall(C_Traits.GenerateImportString, item.configID)
                ns.OpenEditor({ name = item.name, code = ok and code or "" })
            end)
        end
        root:CreateDivider()
        addTagOptions(root, item)
        if item.build then
            root:CreateDivider()
            root:CreateButton("|cffff5050Delete|r", function()
                StaticPopup_Show("LOADOUTPLANNER_DELETE_BUILD", item.name, nil, item.build)
            end)
        end
    end)
end

local function openGroupMenu(owner, group)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(group.name)
        root:CreateButton("Rename...", function()
            StaticPopup_Show("LOADOUTPLANNER_RENAME_GROUP", nil, nil, group)
        end)
        root:CreateButton("Move up", function() ns.MoveGroup(group, -1) end)
        root:CreateButton("Move down", function() ns.MoveGroup(group, 1) end)
        root:CreateButton("Add build here...", function()
            ns.OpenEditor({ group = group.name })
        end)
        root:CreateDivider()
        root:CreateButton("|cffff5050Delete group|r", function()
            StaticPopup_Show("LOADOUTPLANNER_DELETE_GROUP", group.name, tostring(#group.builds), group)
        end)
    end)
end

------------------------------------------------------------------------
-- Row factories (pooled, as in earlier versions)
------------------------------------------------------------------------
local headers, items = {}, {}

local function createHeader()
    local header = CreateFrame("Button", nil, content)
    header:SetSize(content:GetWidth(), HEADER_HEIGHT)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    ns.Style.StyleHeader(header) -- dark band, gold rule, gold hover glow

    header.toggle = header:CreateTexture(nil, "ARTWORK")
    header.toggle:SetPoint("CENTER", header, "LEFT", 11, 0)

    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", 22, 0)
    header.text:SetPoint("RIGHT", -4, 0)
    header.text:SetJustifyH("LEFT")

    -- Callbacks are set per refresh, so one header frame can serve any group.
    header:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if self.onRightClick then self.onRightClick(self) end
        else
            self.onToggle()
        end
    end)
    return header
end

local function createItemRow()
    local row = CreateFrame("Button", nil, content)
    row:SetSize(content:GetWidth(), ROW_HEIGHT - 4)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.bg = ns.Style.AddRowBackground(row)
    ns.Style.SetRowHighlight(row) -- the PvP talent list's gold hover glow

    row.suggest = row:CreateTexture(nil, "ARTWORK")
    row.suggest:SetPoint("TOPLEFT")
    row.suggest:SetPoint("BOTTOMLEFT")
    row.suggest:SetWidth(3)
    row.suggest:SetColorTexture(0.25, 1, 0.25)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", 6, 0)
    -- Talent-node ring: green, or gold for the build you're using.
    row.ring = ns.Style.AddIconBorder(row, row.icon)

    row.check = row:CreateTexture(nil, "OVERLAY")
    ns.Style.SetCheck(row.check)
    row.check:SetSize(18, 18)
    row.check:SetPoint("RIGHT", -4, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row.check, "LEFT", -2, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.tags:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.tags:SetPoint("RIGHT", row.check, "LEFT", -2, 0)
    row.tags:SetJustifyH("LEFT")
    row.tags:SetWordWrap(false)

    -- Custom builds: click stages, double click applies (see
    -- ns.HandleBuildClick in Import.lua). Blizzard loadouts load on a
    -- single click, as in Blizzard's dropdown.
    row:SetScript("OnClick", function(self, button)
        ns.HideDiff()
        if button == "RightButton" then
            openItemMenu(self, self.item)
        elseif self.item.build then
            ns.HandleBuildClick(self, self.item.build)
        else
            ns.LoadItem(self.item)
        end
    end)
    row:SetScript("OnEnter", function(self) ns.ShowDiff(self, self.item) end)
    row:SetScript("OnLeave", ns.HideDiff)
    return row
end

-- Icon of the first tag that has one (a dungeon, raid, or boss icon).
local function tagIcon(tags)
    for _, tag in ipairs(tags) do
        if tag.icon then
            return tag.icon
        end
    end
end

------------------------------------------------------------------------
-- Refresh: rebuild the list top to bottom
------------------------------------------------------------------------
-- Rows are placed one after another with a running y offset, since
-- headers and items have different heights and groups can collapse.
local function refresh()
    if not panel:IsShown() or not ns.db then
        return
    end

    local instance = ns.GetCurrentInstance()
    panel.context:SetText(instance and ("Here: |cffffffff" .. instance.name .. "|r")
        or "Not in a dungeon or raid")

    local suggested = ns.GetSuggestedKeys()
    local specIcon = select(4, GetSpecializationInfoByID(ns.GetSpecID() or 0))
    local y, headerCount, itemCount = 0, 0, 0

    local function addHeader(text, count, collapsed, onToggle, onRightClick)
        headerCount = headerCount + 1
        headers[headerCount] = headers[headerCount] or createHeader()
        local header = headers[headerCount]
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -y)
        header.text:SetText(("%s |cff888888(%d)|r"):format(text, count))
        ns.Style.SetToggle(header.toggle, collapsed)
        header.onToggle, header.onRightClick = onToggle, onRightClick
        header:Show()
        y = y + HEADER_HEIGHT + 2
    end

    local function addItem(item, icon)
        itemCount = itemCount + 1
        items[itemCount] = items[itemCount] or createItemRow()
        local row = items[itemCount]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.item = item

        local tags = ns.GetTagsForItem(item.key)
        local labels = {}
        for _, tag in ipairs(tags) do
            table.insert(labels, tag.label)
        end
        row.name:SetText(item.name)
        row.tags:SetText(#labels > 0 and table.concat(labels, ", ") or "untagged")
        -- Your chosen icon wins; then the tag's icon; then the spec icon.
        ns.SetIcon(row.icon, icon or tagIcon(tags) or specIcon, true)
        local active = ns.IsItemActive(item)
        row.check:SetShown(active)
        ns.Style.SetIconActive(row.ring, active)
        row.suggest:SetShown(suggested[item.key] == true)
        row:Show()
        y = y + ROW_HEIGHT
    end

    -- Section 1: Blizzard's own saved loadouts
    local loadouts = ns.GetLoadouts()
    addHeader("Blizzard loadouts", #loadouts, ns.db.blizzCollapsed, function()
        ns.db.blizzCollapsed = not ns.db.blizzCollapsed
        ns.Notify()
    end)
    if not ns.db.blizzCollapsed then
        for _, loadout in ipairs(loadouts) do
            addItem(loadout)
        end
    end

    -- Section 2+: your groups. Only this spec's builds are listed, but
    -- every group shows, so you can organize before filling them.
    local specID = ns.GetSpecID()
    for _, group in ipairs(ns.GetGroups()) do
        local visible = {}
        for _, build in ipairs(group.builds) do
            if build.specID == specID then
                table.insert(visible, build)
            end
        end
        addHeader(group.name, #visible, group.collapsed, function()
            group.collapsed = not group.collapsed
            ns.Notify()
        end, function(header)
            openGroupMenu(header, group)
        end)
        if not group.collapsed then
            for _, build in ipairs(visible) do
                addItem(ns.ItemFromBuild(build), build.icon)
            end
        end
    end

    -- Hide pooled frames we didn't use this time.
    for i = headerCount + 1, #headers do headers[i]:Hide() end
    for i = itemCount + 1, #items do items[i]:Hide() end
    content:SetHeight(math.max(1, y))
end

ns.OnRefresh(refresh)
panel:HookScript("OnShow", refresh)
