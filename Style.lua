-- Style.lua
-- One place for the look: every LoadoutPlanner window is built from the
-- same Blizzard templates and art the talent window itself uses, so the
-- addon looks like part of the game rather than bolted on.
--
-- The parts, and where Blizzard uses them:
--   * DefaultPanelFlatTemplate: the metal-bordered panel with a title bar
--     (the same border family as the talent window's frame).
--   * MinimalScrollBar: the thin modern scroll bar from the talent window's
--     loadout lists and the PvP talent list.
--   * talents-pvpflyout-rowhighlight: the gold glow when you hover a PvP
--     talent in the talent window.
--   * talents-node-pvpflyout-yellow: the PvP talent list's GOLD ring, for
--     the build you're using; everything else gets the talent tree's GREY
--     square (talents-node-square-gray), like an unlearned talent.
--
-- Every helper checks that the template or atlas exists and falls back to
-- plain textures if not, so a renamed asset in a future patch makes the
-- addon look plainer instead of breaking it.

local addonName, ns = ...

local Style = {}
ns.Style = Style

-- Where content can start below a panel's title bar.
Style.CONTENT_TOP = -28
Style.GOLD = { 1, 0.82, 0 }

------------------------------------------------------------------------
-- Small safety helpers
------------------------------------------------------------------------
local function atlasExists(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end
Style.AtlasExists = atlasExists

-- texture:SetAtlas(atlas) if it exists; otherwise run the fallback.
-- Returns true when the atlas was used.
function Style.SetAtlas(texture, atlas, fallback)
    if atlasExists(atlas) then
        texture:SetAtlas(atlas)
        return true
    end
    if fallback then
        fallback(texture)
    end
    return false
end

-- CreateFrame with a template, or nil if the template doesn't exist.
local function tryCreate(frameType, name, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
    if ok then
        return frame
    end
end

------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------
-- A movable panel with Blizzard's metal border and title bar, a title
-- string (panel.title) and a close button (panel.CloseButton).
function Style.CreatePanel(name, parent, width, height)
    parent = parent or UIParent
    local panel = tryCreate("Frame", name, parent, "DefaultPanelFlatTemplate")
    local container = panel and panel.TitleContainer
    if type(container) == "table" and container.TitleText then
        panel.title = container.TitleText
    else
        -- Fallback: the old dark dialog look.
        panel = panel or CreateFrame("Frame", name, parent, "BackdropTemplate")
        if panel.SetBackdrop then
            panel:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            panel:SetBackdropBorderColor(0.6, 0.5, 0.3)
        end
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetPoint("TOP", 0, -6)
        panel.title:SetPoint("LEFT", 30, 0)
        panel.title:SetPoint("RIGHT", -24, 0)
    end
    if width and height then
        panel:SetSize(width, height)
    end

    local close = tryCreate("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors")
    if not close then
        close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 1, 0)
    end
    panel.CloseButton = close
    return panel
end

-- Drag the panel by its title bar (the top 22 pixels).
function Style.MakeMovable(panel)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        local _, cursorY = GetCursorPosition()
        local top = self:GetTop()
        -- Only start a drag from the title bar, so dragging inside lists works.
        if top and cursorY / self:GetEffectiveScale() >= top - 22 then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
end

-- A darker recessed area (Blizzard's "inset") behind a list.
function Style.CreateInset(parent)
    local inset = tryCreate("Frame", nil, parent, "InsetFrameTemplate")
    if not inset then
        inset = CreateFrame("Frame", nil, parent)
        local bg = inset:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.35)
    end
    return inset
end

------------------------------------------------------------------------
-- Spec art: the talent window's painting, behind our main window
------------------------------------------------------------------------
-- The talent window paints a 1612x774 spec picture (atlas names like
-- "talents-background-mage-frost"). We read whichever one it is showing
-- and show a slice of it, darkened so text stays readable.
local function currentSpecAtlas()
    local talents = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    local background = talents and talents.Background
    if background and background.GetAtlas then
        return background:GetAtlas()
    end
end

-- Show a vertical slice of `atlas` that fills `texture` without stretching.
-- SetTexCoord on an atlas is unreliable, so use the atlas's own file and
-- work out the coordinates of the slice inside it.
local function showSlice(texture, atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    if not info or not info.file then
        return false
    end
    local w, h = texture:GetWidth(), texture:GetHeight()
    if not w or not h or w <= 0 or h <= 0 then
        return false
    end
    local left, right = info.leftTexCoord, info.rightTexCoord
    local top, bottom = info.topTexCoord, info.bottomTexCoord
    -- What fraction of the picture's width matches our shape?
    local fraction = math.min(1, (w / h) / (info.width / info.height))
    -- Take it from the middle: the class emblem sits in the centre.
    local span = (right - left) * fraction
    local start = left + ((right - left) - span) / 2
    texture:SetTexture(info.file)
    texture:SetTexCoord(start, start + span, top, bottom)
    return true
end

-- opts.solid: also paint a dark base under the art. Blizzard's flat panel
-- is see-through, which the main window hides with its art; a dialog that
-- floats over the talent tree (the build editor, Top builds) needs the base
-- so the tree doesn't show through when the art is turned down or missing.
function Style.AddSpecArt(frame, opts)
    if opts and opts.solid then
        local base = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        base:SetPoint("TOPLEFT", 6, -21)
        base:SetPoint("BOTTOMRIGHT", -2, 2)
        base:SetColorTexture(0.03, 0.03, 0.04, 0.96)
        frame.solidBase = base
    end
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    art:SetPoint("TOPLEFT", 6, -21)
    art:SetPoint("BOTTOMRIGHT", -2, 2)
    art:SetVertexColor(0.55, 0.55, 0.55) -- darkened
    art:Hide()

    -- A gradient from dark at the top (behind the buttons) to clear.
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    shade:SetAllPoints(art)
    shade:SetColorTexture(1, 1, 1, 1)
    if shade.SetGradient and CreateColor then
        shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0.75))
    else
        shade:SetColorTexture(0, 0, 0, 0.5)
    end

    -- The talent window's own bottom bar, along our bottom edge.
    local bar = frame:CreateTexture(nil, "BACKGROUND", nil, 4)
    bar:SetPoint("BOTTOMLEFT", art)
    bar:SetPoint("BOTTOMRIGHT", art)
    bar:SetHeight(60)
    if not Style.SetAtlas(bar, "talents-background-bottombar") then
        bar:Hide()
    end

    local function update()
        local atlas = currentSpecAtlas()
        art:SetShown(atlas ~= nil and showSlice(art, atlas))
    end
    frame:HookScript("OnShow", function()
        update()
        C_Timer.After(0, update) -- the talent window may swap its art a frame later
    end)
    frame:HookScript("OnSizeChanged", update)
    ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
        if unit == "player" then
            C_Timer.After(0.5, update)
        end
    end)
    frame.specArt = art
    return art
end

------------------------------------------------------------------------
-- Scroll lists
------------------------------------------------------------------------
-- A ScrollFrame with the modern thin scroll bar. The bar sits just right
-- of the scroll area, so leave about 16 pixels for it. Falls back to the
-- classic template if the modern parts are missing.
function Style.CreateScrollFrame(parent, name)
    local bar = tryCreate("EventFrame", nil, parent, "MinimalScrollBar")
    if not (bar and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then
        if bar then bar:Hide() end
        return CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    end
    local scroll = CreateFrame("ScrollFrame", name, parent)
    -- Inset a few pixels top and bottom so the arrows sit clearly inside
    -- the list's area rather than flush with its edges.
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 4)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    scroll:EnableMouseWheel(true)
    scroll.ScrollBar = bar
    return scroll
end

------------------------------------------------------------------------
-- Rows, icons, headers
------------------------------------------------------------------------
-- The gold hover glow from the PvP talent list.
function Style.SetRowHighlight(button)
    if atlasExists("talents-pvpflyout-rowhighlight") and button.SetHighlightAtlas then
        button:SetHighlightAtlas("talents-pvpflyout-rowhighlight", "ADD")
    else
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
end

-- A faint dark band behind a row, so rows read as rows over the art.
function Style.AddRowBackground(button)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    return bg
end

-- A talent-node ring around an icon: GREY normally, GOLD when active
-- (the build whose talents you have right now).
-- Returns the ring; call Style.SetIconActive(ring, true/false).
local RING_ACTIVE = "talents-node-pvpflyout-yellow"
-- First one that exists wins: the tree's grey square node, the choice
-- flyout's grey square, then the dimmed gold ring as a last resort.
-- (Square, to match the gold ring's shape; the circles looked wrong.)
local RING_IDLE_CHOICES = { "talents-node-square-gray", "talents-node-choiceflyout-square-gray",
    "talents-node-pvpflyout-yellow-dimmed" }
local ringIdle
local function idleAtlas()
    if not ringIdle then
        for _, atlas in ipairs(RING_IDLE_CHOICES) do
            if atlasExists(atlas) then ringIdle = atlas break end
        end
    end
    return ringIdle
end

-- How far the ring reaches past the icon on each side. Blizzard's ring art
-- has its frame INSIDE the square, so a ring exactly the icon's size left
-- the icon's corners poking out. A slightly bigger ring, plus a mask that
-- rounds the icon's corners (as the talent window does), fixes that.
local RING_OUTSET = 3
local ICON_MASK = "talents-node-choiceflyout-mask"

function Style.AddIconBorder(owner, icon)
    local ring = owner:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -RING_OUTSET, RING_OUTSET)
    ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", RING_OUTSET, -RING_OUTSET)
    -- Round the icon's corners so nothing sticks out past the ring.
    if atlasExists(ICON_MASK) and owner.CreateMaskTexture and icon.AddMaskTexture then
        local mask = owner:CreateMaskTexture()
        mask:SetAtlas(ICON_MASK)
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        ring.mask = mask
    end
    local idle = idleAtlas()
    if idle and atlasExists(RING_ACTIVE) then
        ring:SetAtlas(idle)
    else
        ring:Hide()
        ring.missing = true
    end
    return ring
end

function Style.SetIconActive(ring, active)
    if ring.missing then return end
    ring:SetAtlas(active and RING_ACTIVE or idleAtlas())
end

-- The talent window's checkmark.
function Style.SetCheck(texture)
    Style.SetAtlas(texture, "common-icon-checkmark", function(t)
        t:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end)
end

-- Section headers: a dark band, a gold rule underneath, and the
-- friends-list arrow (right = collapsed, down = open).
function Style.StyleHeader(header, static)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    header.bg = bg

    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(2)
    if not Style.SetAtlas(rule, "header-horizontal-rule") then
        rule:SetColorTexture(1, 0.82, 0, 0.35)
    end
    header.rule = rule
    if not static then
        Style.SetRowHighlight(header) -- only clickable headers glow on hover
    end
end

-- A section title that looks like the main window's group headers (dark
-- band, gold rule, gold text) but isn't clickable. Used to split the build
-- editor and Top builds into the same kind of sections as the main list.
Style.HEADER_HEIGHT = 22
function Style.CreateSectionHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(Style.HEADER_HEIGHT)
    Style.StyleHeader(header, true)
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", 8, 0)
    header.text:SetPoint("RIGHT", -8, 0)
    header.text:SetJustifyH("LEFT")
    header.text:SetText(text)
    return header
end

-- Buttons that act as tabs (Top builds' M+/LFR/..., the icon sections).
-- The chosen one keeps its gold hover glow and can't be re-clicked; the
-- rest look like normal buttons. (Greying out the chosen tab, as v0.18
-- did, made it look unavailable instead of selected.)
function Style.SetTabSelected(button, selected)
    button.isSelectedTab = selected
    if selected then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
end

-- Lay out `buttons` side by side to exactly fill `width` (from `x`, `y`
-- inside `parent`), with `gap` pixels between them.
function Style.LayoutButtonRow(buttons, parent, x, y, width, gap)
    local count = #buttons
    if count == 0 then return end
    local each = math.floor((width - gap * (count - 1)) / count)
    for i, button in ipairs(buttons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (each + gap), y)
        button:SetWidth(each)
    end
end

function Style.SetToggle(texture, collapsed)
    local atlas = collapsed and "friendslist-categorybutton-arrow-right" or "friendslist-categorybutton-arrow-down"
    if atlasExists(atlas) then
        texture:SetAtlas(atlas, true) -- true: use the atlas's own size (11x16 / 16x11)
    else
        texture:SetSize(14, 14)
        texture:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")
    end
end

------------------------------------------------------------------------
-- Tooltip-style frames (the hover comparison)
------------------------------------------------------------------------
function Style.CreateTooltipFrame(name, parent)
    local frame = tryCreate("Frame", name, parent or UIParent, "TooltipBackdropTemplate")
    if frame then
        return frame, true
    end
    return CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate"), false
end
