-- Editor.lua
-- The "add / edit build" window: import code, name, group, and icon, all
-- in one place (the icon grid is embedded; see IconPicker.lua).

local addonName, ns = ...

local WIDTH = 470

-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local editor = ns.Style.CreatePanel("LoadoutPlannerEditor", UIParent)
editor:SetWidth(WIDTH)
editor:SetPoint("CENTER", 0, 40)
editor:SetFrameStrata("FULLSCREEN") -- above LoadoutPlanner's window
editor:EnableMouse(true)
editor:SetMovable(true)
editor:SetClampedToScreen(true)
editor:RegisterForDrag("LeftButton")
editor:SetScript("OnDragStart", editor.StartMoving)
editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
editor:Hide()
table.insert(UISpecialFrames, "LoadoutPlannerEditor")


-- A label with a text box under it. Returns the box.
local function makeInput(labelText, x, y, width)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

-- Code first, like Blizzard's own import dialog: paste, then name it.
local codeBox = makeInput("Import code", 18, -42, WIDTH - 50)
codeBox:SetMaxLetters(0) -- 0 = no limit; import codes are long
local nameBox = makeInput("Build name", 18, -90, 250)
local groupBox = makeInput("Group (type a new name to create one)", 18, -138, 220)

-- The little arrow next to Group lists existing groups.
local groupMenu = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
groupMenu:SetSize(24, 20)
groupMenu:SetPoint("LEFT", groupBox, "RIGHT", 4, 0)
groupMenu:SetText("v")
groupMenu:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle("Existing groups")
        for _, group in ipairs(ns.GetGroups()) do
            root:CreateButton(group.name, function() groupBox:SetText(group.name) end)
        end
    end)
end)

-- Tab moves between fields, like a web form.
codeBox:SetScript("OnTabPressed", function() nameBox:SetFocus() end)
nameBox:SetScript("OnTabPressed", function() groupBox:SetFocus() end)
groupBox:SetScript("OnTabPressed", function() codeBox:SetFocus() end)

------------------------------------------------------------------------
-- Selected icon preview (top right, like "Currently Selected")
------------------------------------------------------------------------
local chosenIcon -- nil = use the spec icon automatically

local preview = CreateFrame("Button", nil, editor)
preview:SetSize(48, 48)
preview:SetPoint("TOPRIGHT", -24, -90)
preview.icon = preview:CreateTexture(nil, "ARTWORK")
preview.icon:SetAllPoints()

local previewLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewLabel:SetPoint("RIGHT", preview, "LEFT", -8, 8)
previewLabel:SetJustifyH("RIGHT")
previewLabel:SetText("Selected icon")

local previewHint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
previewHint:SetPoint("TOPRIGHT", previewLabel, "BOTTOMRIGHT", 0, -2)
previewHint:SetJustifyH("RIGHT")
previewHint:SetText("right-click: use spec icon")

------------------------------------------------------------------------
-- Live validation of the import code
------------------------------------------------------------------------
local status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", 24, -186)
status:SetPoint("RIGHT", -24, 0)
status:SetJustifyH("LEFT")

local validSpecID, validSpecIcon
local picker -- created below

local function refreshIcon()
    ns.SetIcon(preview.icon, chosenIcon or validSpecIcon or 134400) -- 134400 = question mark
    if picker then
        picker:SetSelected(chosenIcon)
    end
end

local function validate()
    local specID, specNameOrError, specIcon = ns.ReadCodeHeader(codeBox:GetText())
    if specID then
        validSpecID, validSpecIcon = specID, specIcon
        status:SetText("|cff40ff40OK:|r " .. specNameOrError .. " build")
    else
        validSpecID, validSpecIcon = nil, nil
        status:SetText("|cffff6060" .. specNameOrError .. "|r")
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
-- The icon picker, embedded
------------------------------------------------------------------------
local iconsLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
iconsLabel:SetPoint("TOPLEFT", 18, -208)
iconsLabel:SetText("Choose an icon")

picker = ns.CreateIconPicker(editor, function(texture)
    chosenIcon = texture
    refreshIcon()
end)
picker:SetPoint("TOPLEFT", 16, -228)

------------------------------------------------------------------------
-- Save / Cancel
------------------------------------------------------------------------
local editing -- the build being edited, or nil for a new one

local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
save:SetSize(100, 22)
save:SetPoint("BOTTOMRIGHT", -18, 14)
save:SetText("Save")
save:SetScript("OnClick", function()
    local name = strtrim(nameBox:GetText()) -- strtrim = WoW's trim()
    if name == "" then
        status:SetText("|cffff6060Give the build a name.|r")
        return
    end
    validate()
    if not validSpecID then
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
cancel:SetSize(100, 22)
cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
cancel:SetText("Cancel")
cancel:SetScript("OnClick", function() editor:Hide() end)

-- Height = everything above the picker + the picker + the button row.
editor:SetHeight(228 + picker:GetHeight() + 50)

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
