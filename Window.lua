-- Window.lua
-- LoadoutPlanner's own window: its frame, header, and, most importantly,
-- WHERE it goes. The list inside it lives in UI.lua.
--
-- Placement: beside the talent window. If there isn't room, the talent
-- window slides (and if needed slightly shrinks) to make room. Only if it
-- would have to shrink a lot does the window go inside the talent window.
-- Closing the window tucks it into a small tab on the talent window's edge.

local addonName, ns = ...

local WIDTH = 260
-- Inside mode keeps clear of the talent window's title bar and bottom bar.
local INSIDE_TOP_GAP, INSIDE_BOTTOM_GAP = 30, 92

------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------
-- Blizzard's metal-bordered panel (see Style.lua), with the talent
-- window's own spec painting behind the list.
local window = ns.Style.CreatePanel("LoadoutPlannerWindow", UIParent)
window:SetWidth(WIDTH)
window:EnableMouse(true)
window:SetClampedToScreen(true) -- can never be dragged (or placed) off-screen
window:Hide()
window.title:SetText("LoadoutPlanner")
ns.Style.AddSpecArt(window)
ns.window = window

------------------------------------------------------------------------
-- Visibility: window open, or tucked into a tab
------------------------------------------------------------------------
-- The tab is always attached to the talent window, whatever the mode,
-- so you can always get the window back.
local tab = CreateFrame("Button", nil, UIParent)
tab:SetSize(22, 90)
tab:Hide()
tab.bg = tab:CreateTexture(nil, "BACKGROUND")
tab.bg:SetAllPoints()
ns.Style.SetAtlas(tab.bg, "talents-pvpflyout-background-middle", function(t)
    t:SetColorTexture(0.1, 0.08, 0.04, 0.9)
end)
tab.arrow = tab:CreateTexture(nil, "ARTWORK")
tab.arrow:SetSize(22, 22)
tab.arrow:SetPoint("TOP", 0, -4)
tab.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tab.label:SetPoint("TOP", tab.arrow, "BOTTOM", 0, -4)
tab.label:SetText("L\nP") -- stacked letters read as a vertical label
ns.Style.SetRowHighlight(tab)
tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Open LoadoutPlanner")
    GameTooltip:Show()
end)
tab:SetScript("OnLeave", GameTooltip_Hide)

local function talentsOpen()
    return PlayerSpellsFrame and PlayerSpellsFrame:IsShown()
end

function ns.UpdateWindowVisibility()
    if not ns.db then return end
    local open = talentsOpen()
    window:SetShown(open and not ns.db.collapsed)
    tab:SetShown(open and ns.db.collapsed)
end

function ns.SetWindowCollapsed(collapsed)
    ns.db.collapsed = collapsed
    -- Re-place (not just show/hide): opening may need to make room, and
    -- tucking away gives the talent window its natural size back.
    ns.PlaceWindow()
end

tab:SetScript("OnClick", function() ns.SetWindowCollapsed(false) end)

-- The panel's close button tucks the window away instead of hiding it.
local close = window.CloseButton
close:SetScript("OnClick", function() ns.SetWindowCollapsed(true) end)

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

-- One strata above the talent window, so "inside" mode draws over the tree.
local function strataAbove(frame)
    local current = frame:GetFrameStrata()
    for i, name in ipairs(STRATA_ORDER) do
        if name == current then
            return STRATA_ORDER[math.min(i + 1, #STRATA_ORDER)]
        end
    end
    return "HIGH"
end

-- Would the window fit to the right of the talent window, as it is now?
-- Positions are measured in each frame's own scale, so convert both sides
-- to real screen pixels (x effective scale) before comparing.
local function fitsBeside()
    local right = PlayerSpellsFrame:GetRight()
    if not right then
        return false -- not laid out yet
    end
    local needed = (right + 2 + WIDTH) * PlayerSpellsFrame:GetEffectiveScale()
    local available = UIParent:GetRight() * UIParent:GetEffectiveScale()
    return needed <= available
end

------------------------------------------------------------------------
-- Making room: sliding and shrinking the talent window
------------------------------------------------------------------------
-- Blizzard centers the talent window. When there isn't room beside it, we
-- move the talent window left and, if the pair still won't fit, shrink it
-- a little. Rules we follow to stay out of trouble:
--   * Only SetScale/SetPoint on the frame itself. We never call Blizzard's
--     panel-manager functions or change its settings, because addon code
--     running inside those spreads "taint" into Blizzard's own code.
--   * Never touch it in combat (it contains protected spellbook buttons),
--     and always be able to put it back exactly as Blizzard had it.
local MIN_AUTO_SCALE = 0.7 -- below this, auto mode prefers "inside"
local SCREEN_MARGIN = 8
local GAP = 2

local baseScale    -- Blizzard's own scale for the talent window
local naturalPoint -- Blizzard's own anchor for it
local ourPoint     -- the anchor WE last set (to tell ours from Blizzard's)
local pendingAfterCombat = false

local function samePoint(a, point, x, y)
    return a and a.point == point and a.x == x and a.y == y
end

-- Undo our changes so we can measure Blizzard's natural layout.
-- Returns false if we can't touch the frame right now (combat).
local function restoreNatural()
    if InCombatLockdown() then
        pendingAfterCombat = true
        return false
    end
    baseScale = baseScale or PlayerSpellsFrame:GetScale()
    if PlayerSpellsFrame:GetScale() ~= baseScale then
        PlayerSpellsFrame:SetScale(baseScale)
    end

    local point, rel, relPoint, x, y = PlayerSpellsFrame:GetPoint(1)
    if ourPoint and samePoint(ourPoint, point, x, y) then
        -- The frame is still where WE put it: put Blizzard's anchor back.
        if naturalPoint then
            PlayerSpellsFrame:ClearAllPoints()
            PlayerSpellsFrame:SetPoint(naturalPoint.point, naturalPoint.rel,
                naturalPoint.relPoint, naturalPoint.x, naturalPoint.y)
        end
    elseif point then
        -- Blizzard re-positioned it since we last looked; that's the new
        -- natural anchor.
        naturalPoint = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
    ourPoint = nil
    return true
end

-- The scale at which talent window + our window fit side by side.
local function fitScale()
    local available = UIParent:GetWidth() - 2 * SCREEN_MARGIN
    return math.min(baseScale, available / (PlayerSpellsFrame:GetWidth() + GAP + WIDTH))
end

-- Scale the talent window to `scale` and center the pair on screen,
-- keeping its distance from the top of the screen.
local function applyRoom(scale)
    -- A child's position times its scale = position in its parent's units.
    local fromTop = UIParent:GetHeight() - PlayerSpellsFrame:GetTop() * PlayerSpellsFrame:GetScale()
    PlayerSpellsFrame:SetScale(scale)
    local pairWidth = (PlayerSpellsFrame:GetWidth() + GAP + WIDTH) * scale
    local left = (UIParent:GetWidth() - pairWidth) / 2
    -- SetPoint offsets are in the frame's OWN units, so divide by scale.
    local x, y = left / scale, -fromTop / scale
    PlayerSpellsFrame:ClearAllPoints()
    PlayerSpellsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    ourPoint = { point = "TOPLEFT", x = x, y = y }
end

local function makeRoomEnabled()
    return ns.db.fitTalentWindow ~= false -- default on
end

-- Decide between "beside" and "inside", adjusting the talent window when needed.
local function resolveMode()
    local canAdjust = restoreNatural()
    if ns.db.collapsed or fitsBeside() then
        -- Tucked away (nothing to make room for), or it already fits.
        return "beside"
    end
    if canAdjust and makeRoomEnabled() then
        local scale = fitScale()
        if scale >= MIN_AUTO_SCALE then
            applyRoom(scale)
            return "beside"
        end
    end
    return "inside"
end

function ns.GetWindowMode()
    return window.mode or "auto"
end

local function placeWindow()
    if not (PlayerSpellsFrame and ns.db) then return end
    local mode = resolveMode()
    window.mode = mode
    window:ClearAllPoints()

    -- A child of the talent window, so it moves, scales, and hides with it.
    window:SetParent(PlayerSpellsFrame)
    if mode == "beside" then
        window:SetFrameStrata(PlayerSpellsFrame:GetFrameStrata())
        window:SetPoint("TOPLEFT", PlayerSpellsFrame, "TOPRIGHT", GAP, 0)
        window:SetPoint("BOTTOMLEFT", PlayerSpellsFrame, "BOTTOMRIGHT", GAP, 0)
    else -- inside
        window:SetFrameStrata(strataAbove(PlayerSpellsFrame))
        window:SetPoint("TOPRIGHT", PlayerSpellsFrame, "TOPRIGHT", -6, -INSIDE_TOP_GAP)
        window:SetPoint("BOTTOMRIGHT", PlayerSpellsFrame, "BOTTOMRIGHT", -6, INSIDE_BOTTOM_GAP)
    end

    -- The tab always hugs the talent window's inner right edge.
    tab:SetParent(PlayerSpellsFrame)
    tab:SetFrameStrata(strataAbove(PlayerSpellsFrame))
    tab:ClearAllPoints()
    tab:SetPoint("TOPRIGHT", PlayerSpellsFrame, "TOPRIGHT", -4, -80)

    ns.UpdateWindowVisibility()
end

-- Re-entry guard: placing the window changes the talent window's scale
-- and anchor, which could fire the very hooks that call us again. If we're
-- already mid-placement, ignore the nested call instead of looping forever.
local placing = false

function ns.PlaceWindow()
    if placing then return end
    placing = true
    local ok, err = pcall(placeWindow)
    placing = false -- reset even if placeWindow errored
    if not ok then
        geterrorhandler()(err) -- report it the normal way (BugSack sees it)
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingAfterCombat and PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
        pendingAfterCombat = false
        ns.PlaceWindow()
    end
end)

------------------------------------------------------------------------
-- Options menu ("..." button)
------------------------------------------------------------------------
local function openOptions(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Options")
        local roomOn = ns.db.fitTalentWindow ~= false
        root:CreateButton((roomOn and "|cff40ff40[x]|r " or "[  ] ") .. "Move/shrink talent window to make room", function()
            ns.db.fitTalentWindow = not roomOn
            ns.PlaceWindow()
        end)
        local barOn = ns.db.showTalentTabBar
        root:CreateButton((barOn and "|cff40ff40[x]|r " or "[  ] ") .. "Spec buttons on talent tab too", function()
            ns.db.showTalentTabBar = not ns.db.showTalentTabBar
            ns.UpdateTalentTabBar()
        end)
        root:CreateDivider()
        root:CreateButton("Import from Talent Loadout Ex", ns.ImportFromTLE)
    end)
end

local optionsButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
optionsButton:SetSize(26, 18)
optionsButton:SetPoint("RIGHT", close, "LEFT", 0, 0)
optionsButton:SetText("...")
optionsButton:SetScript("OnClick", openOptions)

------------------------------------------------------------------------
-- Header contents: spec buttons, action buttons, context line
------------------------------------------------------------------------
local function actionButton(text, width, previous, onClick)
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    if previous then
        button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    else
        button:SetPoint("TOPLEFT", 10, -70)
    end
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local importButton = actionButton("Import", 72, nil, function()
    ns.OpenEditor({})
end)
local saveButton = actionButton("Save current", 90, importButton, function()
    -- Export your CURRENT talents (the active config) as a code.
    local ok, code = pcall(C_Traits.GenerateImportString, C_ClassTalents.GetActiveConfigID())
    ns.OpenEditor({ code = ok and code or "" })
end)
actionButton("New group", 74, saveButton, function()
    StaticPopup_Show("LOADOUTPLANNER_NEW_GROUP")
end)

window.context = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
window.context:SetPoint("TOPLEFT", 12, -96)
window.context:SetPoint("RIGHT", -12, 0)
window.context:SetJustifyH("LEFT")

-- Where UI.lua should put the list (between the header and the slider).
ns.LIST_TOP, ns.LIST_BOTTOM = -112, 54

------------------------------------------------------------------------
-- Background art slider
------------------------------------------------------------------------
local artSlider = ns.CreatePercentSlider(window, "Talent background art", function(value)
    if ns.db then
        ns.db.artAlpha = value / 100
        ns.ApplyArtAlpha()
    end
end)
artSlider:SetPoint("BOTTOMLEFT", 14, 12)
artSlider:SetPoint("BOTTOMRIGHT", -14, 12)

window:HookScript("OnShow", function()
    artSlider.slider:SetValue((ns.db and ns.db.artAlpha or 1) * 100)
end)

------------------------------------------------------------------------
-- Hooking into the talent window
------------------------------------------------------------------------
-- VERIFY: addon/frame names - check with /fstack if nothing shows up.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    if not PlayerSpellsFrame then return end

    -- Spec buttons need spec data, which exists by the time this runs.
    local specRow = ns.CreateSpecButtons(window, 28, 6)
    specRow:SetPoint("TOPLEFT", 12, -34)

    -- "Top builds" sits on the spec row's right: builds for THIS spec.
    local topButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    topButton:SetSize(86, 22)
    topButton:SetPoint("TOPRIGHT", -10, -37)
    topButton:SetText("Top builds")
    topButton:SetScript("OnClick", function() ns.OpenTopBuilds() end)
    topButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Top builds for your spec")
        GameTooltip:AddLine("Most-played builds per dungeon and raid boss (needs the ArchonTalentsData addon), "
            .. "plus Archon links for each.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    topButton:SetScript("OnLeave", GameTooltip_Hide)

    PlayerSpellsFrame:HookScript("OnShow", function()
        ns.PlaceWindow()
        -- Blizzard positions its windows right AFTER showing them, so check
        -- again on the next frame, once the talent window is in its final spot.
        C_Timer.After(0, ns.PlaceWindow)
    end)
    PlayerSpellsFrame:HookScript("OnHide", ns.UpdateWindowVisibility)
    -- Re-check "does it fit?" whenever the talent window changes size.
    -- (e.g. Blizzard's own minimize button halves its width).
    PlayerSpellsFrame:HookScript("OnSizeChanged", function()
        if PlayerSpellsFrame:IsShown() then
            ns.PlaceWindow()
        end
    end)
    ns.PlaceWindow()
end)

-- Blizzard re-anchors its windows whenever another panel opens or closes.
-- hooksecurefunc runs our code AFTER Blizzard's, without tainting it.
if UpdateUIPanelPositions then
    hooksecurefunc("UpdateUIPanelPositions", function()
        if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
            C_Timer.After(0, ns.PlaceWindow)
        end
    end)
end

-- UI scale or resolution changes can change whether "beside" fits.
ns.On("UI_SCALE_CHANGED", function() ns.PlaceWindow() end)
ns.On("DISPLAY_SIZE_CHANGED", function() ns.PlaceWindow() end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns.commands.toggle = function()
    if not talentsOpen() then
        ns.Print("Open your talent window first (default key: N).")
        return
    end
    ns.SetWindowCollapsed(not ns.db.collapsed)
end
ns.commands.auto = ns.commands.toggle -- old command name still works

ns.commands.reset = function()
    ns.db.collapsed = false
    ns.db.fitTalentWindow = nil
    ns.PlaceWindow()
    ns.Print("Window reset.")
end
