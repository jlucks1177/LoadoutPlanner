-- Editor.lua
-- The "add / edit build" window: import code, name, group, and icon, all
-- in one place (the icon grid is embedded; see IconPicker.lua).
--
-- Laid out like the main window: the spec painting behind it, sections
-- under the same gold-ruled headers as the build groups, the chosen icon
-- in the same talent-node ring as the list, and the buttons on the
-- talent window's bottom bar.

local addonName, ns = ...
local Style = ns.Style

local WIDTH = 470
local PAD = 12        -- left/right padding for headers
local FIELD_X = 22    -- input boxes (their border art reaches ~6px left)

-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local editor = Style.CreatePanel("LoadoutPlannerEditor", UIParent)
editor:SetWidth(WIDTH)
editor:SetPoint("CENTER", 0, 40)
editor:SetFrameStrata("FULLSCREEN") -- above LoadoutPlanner's window
editor:EnableMouse(true)
editor:SetClampedToScreen(true)
Style.MakeMovable(editor)
editor:Hide()
table.insert(UISpecialFrames, "LoadoutPlannerEditor")
-- solid: this window floats over the talent tree, which showed through.
Style.AddSpecArt(editor, { solid = true })

-- A section header across the window at `y`.
local function section(text, y)
    local header = Style.CreateSectionHeader(editor, text)
    header:SetPoint("TOPLEFT", PAD, y)
    header:SetPoint("TOPRIGHT", -PAD, y)
    return header
end

-- A gold label with a text box under it. Returns the box.
local function makeInput(labelText, y, width)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", PAD + 4, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", FIELD_X, y - 14)
    if width then
        box:SetWidth(width)
    else
        box:SetPoint("RIGHT", -FIELD_X, 0) -- full width
    end
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

------------------------------------------------------------------------
-- Section 1: the talents (import code)
------------------------------------------------------------------------
section("Talents", -28)

-- Code first, like Blizzard's own import dialog: paste, then name it.
local codeBox = makeInput("Import code", -56)
codeBox:SetMaxLetters(0) -- 0 = no limit; import codes are long

-- Live validation of the code, right under it.
local status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", PAD + 4, -96)
status:SetPoint("RIGHT", -PAD, 0)
status:SetJustifyH("LEFT")

------------------------------------------------------------------------
-- Section 2: name, group, and the chosen icon
------------------------------------------------------------------------
section("Details", -116)

local nameBox = makeInput("Build name", -144, 250)
local groupBox = makeInput("Group (type a new name to create one)", -188, 222)

-- The arrow next to Group lists existing groups (the same arrow the
-- main window's group headers use).
local groupMenu = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
groupMenu:SetSize(24, 22)
groupMenu:SetPoint("LEFT", groupBox, "RIGHT", 4, 0)
groupMenu.arrow = groupMenu:CreateTexture(nil, "OVERLAY")
groupMenu.arrow:SetPoint("CENTER")
Style.SetToggle(groupMenu.arrow, false) -- the "open" (down) arrow
groupMenu:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle("Existing groups")
        for _, group in ipairs(ns.GetGroups()) do
            root:CreateButton(group.name, function() groupBox:SetText(group.name) end)
        end
    end)
end)
groupMenu:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Pick an existing group")
    GameTooltip:Show()
end)
groupMenu:SetScript("OnLeave", GameTooltip_Hide)

-- Tab moves between fields, like a web form.
codeBox:SetScript("OnTabPressed", function() nameBox:SetFocus() end)
nameBox:SetScript("OnTabPressed", function() groupBox:SetFocus() end)
groupBox:SetScript("OnTabPressed", function() codeBox:SetFocus() end)

-- The chosen icon, on the right of the name/group fields, in the list's
-- talent-node ring (gold: it's the selected one).
local chosenIcon -- nil = use the spec icon automatically

local preview = CreateFrame("Button", nil, editor)
preview:SetSize(46, 46)
preview:SetPoint("TOPRIGHT", -54, -160)
preview.icon = preview:CreateTexture(nil, "ARTWORK")
preview.icon:SetAllPoints()
preview.ring = Style.AddIconBorder(preview, preview.icon)
Style.SetIconActive(preview.ring, true)

local previewLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewLabel:SetPoint("BOTTOM", preview, "TOP", 0, 8)
previewLabel:SetText("Icon")

local previewHint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
previewHint:SetPoint("TOP", preview, "BOTTOM", 0, -8)
previewHint:SetText("Right-click: spec icon")

------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------
local validSpecID, validSpecIcon
local picker -- created below

local function refreshIcon()
    ns.SetIcon(preview.icon, chosenIcon or validSpecIcon or 134400) -- 134400 = question mark
    if picker then
        picker:SetSelected(chosenIcon)
    end
end

local function validate()
    local text = codeBox:GetText()
    local specID, specNameOrError, specIcon = ns.ReadCodeHeader(text)
    if specID then
        validSpecID, validSpecIcon = specID, specIcon
        status:SetText("|cff40ff40OK:|r " .. specNameOrError .. " build")
    else
        validSpecID, validSpecIcon = nil, nil
        if strtrim(text or "") == "" then
            -- Nothing typed yet isn't an error: a grey hint, not red.
            status:SetText("|cff9d9d9dPaste a talent import code (Blizzard's Share button, or a build site).|r")
        else
            status:SetText("|cffff6060" .. specNameOrError .. "|r")
        end
    end
    refreshIcon()
end
codeBox:SetScript("OnTextChanged", validate)

-- Right-click the preview to go back to the automatic spec icon.
preview:RegisterForClicks("RightButtonUp")
preview:SetScript("OnClick", function()
    chosenIcon = nil
    refreshIcon()
end)

------------------------------------------------------------------------
-- Section 3: the icon picker, embedded
------------------------------------------------------------------------
local PICKER_TOP = -262
section("Choose an icon", PICKER_TOP + 28)

picker = ns.CreateIconPicker(editor, function(texture)
    chosenIcon = texture
    refreshIcon()
end)
picker:SetPoint("TOPLEFT", (WIDTH - picker:GetWidth()) / 2, PICKER_TOP)

------------------------------------------------------------------------
-- Save / Cancel, on the bottom bar
------------------------------------------------------------------------
local editing -- the build being edited, or nil for a new one

local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
save:SetSize(110, 24)
save:SetPoint("BOTTOMRIGHT", -18, 18)
save:SetText("Save")
save:SetScript("OnClick", function()
    local name = strtrim(nameBox:GetText()) -- strtrim = WoW's trim()
    if name == "" then
        status:SetText("|cffff6060Give the build a name.|r")
        return
    end
    validate()
    if not validSpecID then
        if strtrim(codeBox:GetText() or "") == "" then
            status:SetText("|cffff6060Paste an import code first.|r")
        end
        return -- validate() already explained the problem
    end
    ns.SaveBuild({
        name = name,
        code = (codeBox:GetText():gsub("%s", "")),
        icon = chosenIcon,
        specID = validSpecID,
    }, strtrim(groupBox:GetText()), editing)
    ns.Print(("Saved build |cffffd100%s|r."):format(name))
    editor:Hide()
end)

local cancel = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
cancel:SetSize(110, 24)
cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
cancel:SetText("Cancel")
cancel:SetScript("OnClick", function() editor:Hide() end)

-- Height = everything above the picker + the picker + the bottom bar.
editor:SetHeight(-PICKER_TOP + picker:GetHeight() + 64)

-- opts: { build = existing } to edit, or { name, group, code } to prefill.
function ns.OpenEditor(opts)
    opts = opts or {}
    editing = opts.build
    -- Careful: `local _, group = editing and ns.GetBuildByID(...)` would NOT
    -- work. `and`/`or` keep only the FIRST return value (the build), so
    -- group would always be nil. select(2, ...) skips to the second value
    -- (the group) first, and then `and` keeps that.
    local group = editing and select(2, ns.GetBuildByID(editing.id))

    editor.title:SetText(editing and "Edit build" or "New build")
    codeBox:SetText(editing and editing.code or opts.code or "")
    codeBox:SetCursorPosition(0) -- show the start of long codes
    nameBox:SetText(editing and editing.name or opts.name or "")
    groupBox:SetText(group and group.name or opts.group or "")
    chosenIcon = editing and editing.icon or nil

    editor:Show()
    picker:Open(chosenIcon)
    validate()
    -- Empty code? Start there. Otherwise start at the name.
    if codeBox:GetText() == "" then codeBox:SetFocus() else nameBox:SetFocus() end
end
